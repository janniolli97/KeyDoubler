import Foundation
import CoreGraphics
import ImageIO
import simd
import Vision
import CoreVideo

/// Turns a photo of a key (seen end-on, i.e. the cross-section, against a contrasting background)
/// into a closed profile outline.
public struct PhotoTrace {
    public let width: Int
    public let height: Int
    public private(set) var gray: [UInt8]
    let source: CGImage
    public static let maxDimension = 900

    public enum TraceError: LocalizedError {
        case unreadable, noShape
        public var errorDescription: String? {
            switch self {
            case .unreadable: return "Das Bild konnte nicht gelesen werden."
            case .noShape: return "Keine Form gefunden. Schwellwert ändern oder 'Invertieren' umschalten."
            }
        }
    }

    /// Reads JPEG/PNG/HEIC and applies EXIF orientation (iPhone photos).
    public init(url: URL, maxDimension: Int = PhotoTrace.maxDimension) throws {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw TraceError.unreadable }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxDimension]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw TraceError.unreadable }
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h)
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { throw TraceError.unreadable }
        width = w; height = h; gray = buf; source = img
    }

    public func otsuThreshold() -> Int {
        var hist = [Double](repeating: 0, count: 256)
        for v in gray { hist[Int(v)] += 1 }
        let total = Double(gray.count)
        var sum = 0.0; for i in 0..<256 { sum += Double(i) * hist[i] }
        var wB = 0.0, sumB = 0.0, best = 0.0, thr = 128
        for t in 0..<256 {
            wB += hist[t]; if wB == 0 { continue }
            let wF = total - wB; if wF == 0 { break }
            sumB += Double(t) * hist[t]
            let mB = sumB / wB, mF = (sum - sumB) / wF
            let between = wB * wF * (mB - mF) * (mB - mF)
            if between > best { best = between; thr = t }
        }
        return thr
    }

    /// The main subject of the photo as found by Vision, which copes with uneven light. nil if none was found.
    /// Vision's mask is coarse relative to its input, so a small subject is detected again on a crop around it.
    public func subjectMask() -> [Bool]? {
        guard #available(macOS 14.0, *), let first = visionMask(of: source) else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height { for x in 0..<width where first[y * width + x] {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { return nil }
        let margin = max(maxX - minX, maxY - minY) / 6
        let crop = CGRect(x: max(0, minX - margin), y: max(0, minY - margin),
                          width: min(width, maxX + margin + 1) - max(0, minX - margin),
                          height: min(height, maxY + margin + 1) - max(0, minY - margin))
        guard crop.width * crop.height < CGFloat(width * height) * 0.7, let image = source.cropping(to: crop),
              let detail = visionMask(of: image) else { return first }
        var out = [Bool](repeating: false, count: width * height)
        let cw = Int(crop.width)
        for y in 0..<Int(crop.height) { for x in 0..<cw where detail[y * cw + x] {
            out[(y + Int(crop.minY)) * width + x + Int(crop.minX)] = true
        } }
        return out.contains(true) ? out : first
    }

    @available(macOS 14.0, *)
    private func visionMask(of image: CGImage) -> [Bool]? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let result = request.results?.first,
              let buffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = image.width, h = image.height
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              CVPixelBufferGetWidth(buffer) == w, CVPixelBufferGetHeight(buffer) == h else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var out = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<w { out[y * w + x] = row[x] > 0.5 }
        }
        return out.contains(true) ? out : nil
    }

    /// True when the picture's border is bright, i.e. the background is light and the key is the dark part.
    public func suggestedKeyIsDark(threshold: Int) -> Bool {
        var bright = 0, total = 0
        func count(_ i: Int) { total += 1; if Int(gray[i]) > threshold { bright += 1 } }
        for x in 0..<width { count(x); count((height - 1) * width + x) }
        for y in 0..<height { count(y * width); count(y * width + width - 1) }
        return bright * 2 >= total
    }

    /// Binary mask of the key: the largest shape not touching the image border, holes filled.
    /// Pieces separated by reflections are grouped; `bridgeGaps` also closes the gaps between them,
    /// which a contour needs. Measuring edges should use the original pixels instead.
    public func mask(threshold: Int, keyIsDark: Bool, bridgeGaps: Bool = true) -> [Bool] {
        let raw = gray.map { keyIsDark ? Int($0) <= threshold : Int($0) > threshold }
        let w = width, h = height

        struct Component { var area = 0, minX = Int.max, minY = Int.max, maxX = 0, maxY = 0, touchesBorder = false }
        func components(_ m: [Bool]) -> (labels: [Int32], list: [Component]) {
            var label = [Int32](repeating: -1, count: w * h)
            var list: [Component] = []
            var stack: [Int] = []
            for s in 0..<(w * h) where m[s] && label[s] < 0 {
                let id = Int32(list.count)
                var c = Component()
                stack = [s]; label[s] = id
                while let i = stack.popLast() {
                    let x = i % w, y = i / w
                    c.area += 1
                    c.minX = min(c.minX, x); c.maxX = max(c.maxX, x); c.minY = min(c.minY, y); c.maxY = max(c.maxY, y)
                    if x == 0 || y == 0 || x == w - 1 || y == h - 1 { c.touchesBorder = true }
                    if x > 0, m[i - 1], label[i - 1] < 0 { label[i - 1] = id; stack.append(i - 1) }
                    if x < w - 1, m[i + 1], label[i + 1] < 0 { label[i + 1] = id; stack.append(i + 1) }
                    if y > 0, m[i - w], label[i - w] < 0 { label[i - w] = id; stack.append(i - w) }
                    if y < h - 1, m[i + w], label[i + w] < 0 { label[i + w] = id; stack.append(i + w) }
                }
                list.append(c)
            }
            return (label, list)
        }
        func largest(_ list: [Component], where keep: (Component) -> Bool) -> Int? {
            list.indices.filter { keep(list[$0]) }.max { list[$0].area < list[$1].area }
        }
        func spread(_ m: [Bool], _ r: Int, value: Bool) -> [Bool] {   // square dilate (true) or erode (false)
            var a = m
            for (count, step, lines, lineStep) in [(w, 1, h, w), (h, w, w, 1)] {
                var out = a
                for line in 0..<lines {
                    let base = line * lineStep
                    var hits = 0
                    for i in 0..<min(r + 1, count) where a[base + i * step] == value { hits += 1 }
                    for i in 0..<count {
                        out[base + i * step] = (hits > 0) == value
                        if i + r + 1 < count, a[base + (i + r + 1) * step] == value { hits += 1 }
                        if i - r >= 0, a[base + (i - r) * step] == value { hits -= 1 }
                    }
                }
                a = out
            }
            return a
        }

        // Close small gaps first, so that a speckled background patch counts as one shape that reaches the border.
        let denoise = max(1, max(w, h) * 3 / 1000)
        let (labels, list) = components(spread(spread(raw, denoise, value: true), denoise, value: false))
        var m: [Bool]
        if let main = largest(list, where: { !$0.touchesBorder }) {
            // Group the pieces of the key that lie apart only by a small gap, sized relative to the key in the image.
            func isPiece(_ c: Component) -> Bool { !c.touchesBorder && c.area * 100 >= list[main].area }
            let big = list.filter { !$0.touchesBorder && $0.area * 20 >= list[main].area }
            let span = max(big.map(\.maxX).max()! - big.map(\.minX).min()!, big.map(\.maxY).max()! - big.map(\.minY).min()!)
            let r = max(1, span * 12 / 1000)
            let candidates = (0..<(w * h)).map { raw[$0] && isPiece(list[Int(labels[$0])]) }
            let closed = spread(spread(candidates, r, value: true), r, value: false)
            let (groupLabels, groups) = components(closed)
            guard let group = largest(groups, where: { _ in true }) else { return [Bool](repeating: false, count: w * h) }
            m = (0..<(w * h)).map { groupLabels[$0] == Int32(group) && (bridgeGaps || raw[$0]) }
        } else {
            guard let main = largest(list, where: { _ in true }) else { return raw }
            m = (0..<(w * h)).map { labels[$0] == Int32(main) && raw[$0] }
        }
        return filled(m)
    }

    /// Fills enclosed holes by flooding the background from the image border.
    func filled(_ input: [Bool]) -> [Bool] {
        var m = input
        let w = width, h = height
        var outside = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        func seed(_ i: Int) { if !m[i] && !outside[i] { outside[i] = true; stack.append(i) } }
        for x in 0..<w { seed(x); seed((h - 1) * w + x) }
        for y in 0..<h { seed(y * w); seed(y * w + w - 1) }
        while let i = stack.popLast() {
            let x = i % w, y = i / w
            if x > 0 { seed(i - 1) }; if x < w - 1 { seed(i + 1) }
            if y > 0 { seed(i - w) }; if y < h - 1 { seed(i + w) }
        }
        for i in 0..<(w * h) where !outside[i] { m[i] = true }
        return m
    }

    /// The largest connected shape of a mask, holes filled.
    public func keyShape(in input: [Bool]) -> [Bool] {
        let w = width, h = height
        var label = [Int32](repeating: 0, count: w * h)
        var next: Int32 = 0, best: Int32 = 0, bestArea = 0
        var stack: [Int] = []
        for s in 0..<(w * h) where input[s] && label[s] == 0 {
            next += 1
            var area = 0
            stack = [s]; label[s] = next
            while let i = stack.popLast() {
                area += 1
                let x = i % w, y = i / w
                if x > 0, input[i - 1], label[i - 1] == 0 { label[i - 1] = next; stack.append(i - 1) }
                if x < w - 1, input[i + 1], label[i + 1] == 0 { label[i + 1] = next; stack.append(i + 1) }
                if y > 0, input[i - w], label[i - w] == 0 { label[i - w] = next; stack.append(i - w) }
                if y < h - 1, input[i + w], label[i + w] == 0 { label[i + w] = next; stack.append(i + w) }
            }
            if area > bestArea { bestArea = area; best = next }
        }
        return filled(label.map { $0 == best && best != 0 })
    }

    /// Outer contour (pixel corner coordinates, y down) via boundary following on the pixel grid.
    public func contour(mask m: [Bool]) throws -> [V2] {
        let w = width, h = height
        func fg(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h && m[y * w + x] }
        // find a starting pixel (top-most, left-most)
        guard let start = (0..<(w * h)).first(where: { m[$0] }) else { throw TraceError.noShape }
        let sx = start % w, sy = start / w
        // Walk along pixel edges keeping foreground on the right-hand side.
        var x = sx, y = sy            // vertex (corner) coordinates
        var dir = 0                   // 0:right 1:down 2:left 3:up ; start at top-left corner moving right
        let dx = [1, 0, -1, 0], dy = [0, 1, 0, -1]
        var pts: [V2] = []
        var guardN = 0
        repeat {
            pts.append(V2(Double(x), Double(y)))
            // pixels ahead-left / ahead-right of the current edge direction
            let ahead: (Bool, Bool)   // (left pixel, right pixel) beyond the vertex
            switch dir {
            case 0: ahead = (fg(x, y - 1), fg(x, y))
            case 1: ahead = (fg(x, y), fg(x - 1, y))
            case 2: ahead = (fg(x - 1, y), fg(x - 1, y - 1))
            default: ahead = (fg(x - 1, y - 1), fg(x, y - 1))
            }
            if ahead.0 { dir = (dir + 3) % 4 }          // turn left
            else if !ahead.1 { dir = (dir + 1) % 4 }    // turn right
            x += dx[dir]; y += dy[dir]
            guardN += 1
        } while !(x == sx && y == sy) && guardN < w * h * 4
        return pts
    }

    /// Smoothed, simplified outline in "y-up" form as expected by Outline (pixels).
    public func outline(threshold: Int, keyIsDark: Bool) throws -> Outline {
        try outline(mask: mask(threshold: threshold, keyIsDark: keyIsDark))
    }

    public func outline(mask m: [Bool]) throws -> Outline {
        var p = try contour(mask: m)
        // light smoothing to remove pixel staircase
        for _ in 0..<2 {
            let n = p.count
            p = (0..<n).map { (p[($0 + n - 1) % n] + 2 * p[$0] + p[($0 + 1) % n]) / 4 }
        }
        var o = Outline(points: p.map { V2($0.x, -$0.y) })
        if signedArea(o.points) < 0 { o.points.reverse() }
        o = o.simplified(tolerance: 0.8)
        guard o.points.count >= 8 else { throw TraceError.noShape }
        return o
    }

    /// Writes the outline as SVG (y-down, like Inkscape output) so it can be used as a profile.
    public static func svg(_ o: Outline) -> String {
        let b = o.bounds
        let pts = o.points.map { V2($0.x - b.min.x, b.max.y - $0.y) }
        let d = "M " + pts.map { String(format: "%.2f,%.2f", $0.x, $0.y) }.joined(separator: " L ") + " Z"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(b.max.x - b.min.x)" height="\(b.max.y - b.min.y)" viewBox="0 0 \(b.max.x - b.min.x) \(b.max.y - b.min.y)">
        <path style="fill:#000000" d="\(d)"/></svg>
        """
    }

    /// Preview image: photo with the detected shape tinted and its outline drawn.
    public func preview(mask m: [Bool], outline o: Outline?) -> CGImage? {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            let g = Double(gray[i])
            let t: Double = m[i] ? 0.55 : 0
            rgba[i * 4] = UInt8(g * (1 - t) + 255 * t)
            rgba[i * 4 + 1] = UInt8(g * (1 - t) + 60 * t)
            rgba[i * 4 + 2] = UInt8(g * (1 - t) + 60 * t)
        }
        guard let ctx = rgba.withUnsafeMutableBytes({ raw in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { return nil }
        if let o = o, o.points.count > 2 {
            ctx.setStrokeColor(CGColor(red: 0.1, green: 0.9, blue: 0.3, alpha: 1)); ctx.setLineWidth(2)
            // context origin is bottom-left; outline y is already "up" in pixel units relative to image top => flip
            ctx.move(to: CGPoint(x: o.points[0].x, y: Double(height) + o.points[0].y))
            for q in o.points.dropFirst() { ctx.addLine(to: CGPoint(x: q.x, y: Double(height) + q.y)) }
            ctx.closePath(); ctx.strokePath()
        }
        return ctx.makeImage()
    }
}
