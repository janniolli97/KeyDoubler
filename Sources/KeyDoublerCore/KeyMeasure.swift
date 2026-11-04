import Foundation
import CoreGraphics

/// Coins usable as a size reference, with their official diameters.
public struct ReferenceCoin: Identifiable, Hashable {
    public let name: String
    public let diameterMM: Double
    public var id: String { name }
    public static let all = [
        ReferenceCoin(name: "1 Euro", diameterMM: 23.25), ReferenceCoin(name: "2 Euro", diameterMM: 25.75),
        ReferenceCoin(name: "50 Cent", diameterMM: 24.25), ReferenceCoin(name: "20 Cent", diameterMM: 22.25),
        ReferenceCoin(name: "10 Cent", diameterMM: 19.75), ReferenceCoin(name: "5 Cent", diameterMM: 21.25),
    ]
}

/// System and combination values measured from a photo of a key lying flat.
public struct KeyMeasurement {
    public var keyLength = 0.0, profileHeight = 0.0, shoulder = 0.0, pinSpacing = 0.0
    public var deepestCut = 0.0, cutStep = 0.0, cutAngle = 90.0, plateau = 0.0
    public var levels: [Int] = []
    public var depths: [Double] = []
    public var markers: [(a: V2, b: V2)] = []
    public var shoulderLine: (a: V2, b: V2) = (V2(0, 0), V2(0, 0))
}

public extension PhotoTrace {
    /// Separates a round coin from the key in a subject mask. The key mask is empty-safe: without a coin it is the whole subject.
    func splitCoin(from subject: [Bool]) -> (key: [Bool], coinDiameterPixels: Double?) {
        let w = width, h = height
        var label = [Int32](repeating: 0, count: w * h)
        var next: Int32 = 0
        var stack: [Int] = []
        var shapes: [(id: Int32, area: Int, minX: Int, maxX: Int, minY: Int, maxY: Int)] = []
        for s in 0..<(w * h) where subject[s] && label[s] == 0 {
            next += 1
            var c = (id: next, area: 0, minX: Int.max, maxX: 0, minY: Int.max, maxY: 0)
            stack = [s]; label[s] = next
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                c.area += 1
                c.minX = min(c.minX, x); c.maxX = max(c.maxX, x); c.minY = min(c.minY, y); c.maxY = max(c.maxY, y)
                if x > 0, subject[i - 1], label[i - 1] == 0 { label[i - 1] = next; stack.append(i - 1) }
                if x < w - 1, subject[i + 1], label[i + 1] == 0 { label[i + 1] = next; stack.append(i + 1) }
                if y > 0, subject[i - w], label[i - w] == 0 { label[i - w] = next; stack.append(i - w) }
                if y < h - 1, subject[i + w], label[i + w] == 0 { label[i + w] = next; stack.append(i + w) }
            }
            shapes.append(c)
        }
        let largest = shapes.map(\.area).max() ?? 0
        let round = shapes.filter { c in
            let bw = Double(c.maxX - c.minX + 1), bh = Double(c.maxY - c.minY + 1)
            let fill = Double(c.area) / (Double.pi / 4 * bw * bh)
            return c.area * 20 >= largest && abs(bw / bh - 1) < 0.1 && abs(fill - 1) < 0.08
        }
        guard let coin = round.max(by: { $0.area < $1.area }) else { return (subject, nil) }
        let key = (0..<(w * h)).map { subject[$0] && label[$0] != coin.id }
        guard key.contains(true) else { return (subject, nil) }
        return (key, (4 * Double(coin.area) / Double.pi).squareRoot())
    }
}

public extension PhotoTrace {
    /// Looks for a round shape beside the key by its form alone, because subject detection may skip a coin.
    /// Returns its diameter in pixels; nil rather than a guess when nothing is clearly round.
    func findCoin(besideKey key: [Bool]) -> Double? {
        let w = width, h = height
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where key[y * w + x] {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { return nil }
        let keyLength = Double(max(maxX - minX, maxY - minY))
        let keep = closed(key, radius: max(2, Int(keyLength) / 100))
        var best: (score: Double, diameter: Double)?
        for threshold in stride(from: 40, through: 220, by: 30) {
            for bright in [true, false] {
                let raw = (0..<(w * h)).map { !keep[$0] && (Int(gray[$0]) > threshold) == bright }
                let solid = filled(closed(raw, radius: max(1, Int(keyLength) / 200)))
                var seen = [Bool](repeating: false, count: w * h)
                var stack: [Int] = []
                for s in 0..<(w * h) where solid[s] && !seen[s] {
                    var area = 0, x0 = w, x1 = 0, y0 = h, y1 = 0, border = false
                    stack = [s]; seen[s] = true
                    while let i = stack.popLast() {
                        area += 1
                        let x = i % w, y = i / w
                        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
                        if x == 0 || y == 0 || x == w - 1 || y == h - 1 { border = true }
                        if x > 0, solid[i - 1], !seen[i - 1] { seen[i - 1] = true; stack.append(i - 1) }
                        if x < w - 1, solid[i + 1], !seen[i + 1] { seen[i + 1] = true; stack.append(i + 1) }
                        if y > 0, solid[i - w], !seen[i - w] { seen[i - w] = true; stack.append(i - w) }
                        if y < h - 1, solid[i + w], !seen[i + w] { seen[i + w] = true; stack.append(i + w) }
                    }
                    let bw = Double(x1 - x0 + 1), bh = Double(y1 - y0 + 1)
                    let diameter = (bw + bh) / 2
                    guard !border, diameter >= keyLength * 0.15, diameter <= keyLength * 1.1 else { continue }
                    let shape = abs(bw / bh - 1), fill = abs(Double(area) / (Double.pi / 4 * bw * bh) - 1)
                    guard shape < 0.06, fill < 0.04 else { continue }
                    if best == nil || shape + fill < best!.score { best = (shape + fill, (4 * Double(area) / Double.pi).squareRoot()) }
                }
            }
        }
        return best?.diameter
    }
}

public extension KeyScan {
    enum MeasureError: LocalizedError {
        case noCuts
        public var errorDescription: String? { "Es wurden zu wenige Einschnitte gefunden. Die Zahnkante muss frei und gut sichtbar sein." }
    }

    /// Photo with the key tinted and the measured shoulder and pin positions drawn on it.
    func preview(_ m: KeyMeasurement) -> CGImage? {
        preview(Result(depthsMM: m.depths, levels: m.levels, residuals: [], mmPerPixel: 0, shoulderU: 0, tipU: 0, markers: m.markers, shoulderLine: m.shoulderLine))
    }

    /// Blade height in pixels, measured over the uncut parts of the blade.
    var bladeHeightPixels: Double {
        let widths = (Int(detectedShoulder)..<bins).map { vmax[$0] - vmin[$0] }.sorted()
        return widths[Int(Double(widths.count) * 0.9)]
    }

    /// Derives the system values from the outline of the cut edge at the given scale.
    func measure(mmPerPixel mm: Double, shoulderBin: Double? = nil) throws -> KeyMeasurement {
        let sh = Int(shoulderBin ?? detectedShoulder), last = bins - 1
        func spread(_ x: ArraySlice<Double>) -> Double {
            let mean = x.reduce(0, +) / Double(x.count)
            return x.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
        }
        let cutOnHigh = spread(vmax[sh...last]) >= spread(vmin[sh...last])
        let edge = (sh...last).map { cutOnHigh ? vmax[$0] : vmin[$0] }
        let sorted = edge.sorted()
        let outer = cutOnHigh ? sorted[Int(Double(sorted.count) * 0.95)] : sorted[Int(Double(sorted.count) * 0.05)]
        let raw = edge.map { max(0, (cutOnHigh ? outer - $0 : $0 - outer) * mm) }
        // Depth along the blade in mm, lightly smoothed.
        let d = raw.indices.map { i -> Double in
            let r = max(0, i - 1)...min(raw.count - 1, i + 1)
            return raw[r].reduce(0, +) / Double(r.count)
        }

        // Valleys: local depth maxima with a wall on both sides. The bevelled tip has no wall towards the end.
        let minProminence = 0.3, plateauBand = 0.1
        var centers: [Double] = [], floors: [Double] = []
        var i = 1
        while i < d.count - 1 {
            guard d[i] > 0.5, d[i] >= d[i - 1] else { i += 1; continue }
            var end = i
            while end + 1 < d.count, d[end + 1] >= d[i] - plateauBand / 2 { end += 1; if d[end] > d[i] { break } }
            if d[end] > d[i] { i = end; continue }
            var left = d[i], right = d[i]
            var l = i
            while l > 0, d[l - 1] <= d[i] + 1e-9 { l -= 1; left = min(left, d[l]) }
            var r = end
            while r < d.count - 1, d[r + 1] <= d[i] + 1e-9 { r += 1; right = min(right, d[r]) }
            if d[i] - left >= minProminence, d[i] - right >= minProminence {
                centers.append(Double(i + end) / 2 * mm)
                floors.append(Double(end - i) * mm)
            }
            i = end + 1
        }
        guard centers.count >= 2 else { throw MeasureError.noCuts }

        // Regular pin grid, so that a pin without a visible valley still gets its place.
        let gaps = zip(centers.dropFirst(), centers).map { $0 - $1 }.filter { $0 >= 1.5 }.sorted()
        guard let smallest = gaps.first else { throw MeasureError.noCuts }
        let index = centers.map { (($0 - centers[0]) / smallest).rounded() }
        let n = Double(centers.count)
        let si = index.reduce(0, +), sc = centers.reduce(0, +)
        let sii = index.map { $0 * $0 }.reduce(0, +), sic = zip(index, centers).map { $0 * $1 }.reduce(0, +)
        let den = n * sii - si * si
        let spacing = den > 0 ? (n * sic - si * sc) / den : smallest
        let first = (sc - spacing * si) / n
        let pins = Int(index.max() ?? 0) + 1

        var result = KeyMeasurement()
        let half = max(2, Int(0.22 * spacing / mm))
        for p in 0..<pins {
            let c = Int((first + Double(p) * spacing) / mm)
            let window = max(0, c - half)...min(d.count - 1, c + half)
            result.depths.append(d[window].max() ?? 0)
            let bin = Double(sh) + (first + Double(p) * spacing) / mm
            result.markers.append((point(bin, -Double(bins)), point(bin, Double(bins))))
        }
        result.shoulderLine = (point(Double(sh), -Double(bins)), point(Double(sh), Double(bins)))
        result.keyLength = Double(last - sh) * mm
        result.profileHeight = bladeHeightPixels * mm
        result.shoulder = first
        result.pinSpacing = spacing
        result.deepestCut = result.depths.max() ?? 0

        // One key shows only some depths: the smallest clear difference is the best estimate of the step.
        let distinct = result.depths.sorted()
        let steps = zip(distinct.dropFirst(), distinct).map { $0 - $1 }.filter { $0 >= 0.15 }
        result.cutStep = min(1, max(0.2, steps.min() ?? 0.5))
        result.levels = result.depths.map { Int(((result.deepestCut - $0) / result.cutStep).rounded()) }

        // Flank slope gives the cut angle, the flat floor the plateau.
        var slopes: [Double] = []
        for c in centers {
            let center = Int(c / mm), reach = Int(0.5 * spacing / mm)
            for j in stride(from: max(1, center - reach), to: min(d.count - 1, center + reach), by: 1) {
                let depth = d[center]
                if d[j] > depth * 0.3, d[j] < depth * 0.7 { slopes.append(abs(d[j + 1] - d[j - 1]) / (2 * mm)) }
            }
        }
        if !slopes.isEmpty {
            let slope = slopes.sorted()[slopes.count / 2]
            if slope > 0.01 { result.cutAngle = min(130, max(50, 2 * atan(1 / slope) * 180 / .pi)) }
        }
        result.plateau = min(1.5, floors.sorted()[floors.count / 2])
        return result
    }
}
