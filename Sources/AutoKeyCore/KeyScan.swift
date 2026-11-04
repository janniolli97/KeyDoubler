import Foundation
import CoreGraphics
import simd

/// Reads the cut depths (bitting) from a photo or flatbed scan of a key lying flat.
public struct KeyScan {
    public struct Result {
        public var depthsMM: [Double]        // measured cut depth per pin, from the uncut edge
        public var levels: [Int]             // nearest cut level (0 = deepest, as in the system definition)
        public var residuals: [Double]       // distance to the nearest level in units of cutspace (0...0.5)
        public var mmPerPixel: Double
        public var shoulderU: Double, tipU: Double   // in pixels along the key axis
        public var markers: [(a: V2, b: V2)]         // pin lines in image pixel coordinates
        public var shoulderLine: (a: V2, b: V2)
    }

    public enum ScanError: LocalizedError {
        case noKey, tooShort
        public var errorDescription: String? {
            switch self {
            case .noKey: return "Kein Schlüssel erkannt. Schwellwert ändern oder 'dunkel' umschalten."
            case .tooShort: return "Der erkannte Schlüssel ist zu klein oder unvollständig im Bild."
            }
        }
    }

    let trace: PhotoTrace
    let mask: [Bool]
    // key axis frame
    let mean: V2, axis: V2, perp: V2
    var vmin: [Double] = [], vmax: [Double] = [], u0 = 0.0
    var flipped = false
    public static let scanDimension = 2400
    public let bins: Int
    public let detectedShoulder: Double   // in bins

    public init(trace: PhotoTrace, threshold: Int, keyIsDark: Bool) throws {
        self.trace = trace
        mask = trace.mask(threshold: threshold, keyIsDark: keyIsDark, bridgeGaps: false)
        var pts: [V2] = []
        for i in 0..<mask.count where mask[i] { pts.append(V2(Double(i % trace.width), Double(i / trace.width))) }
        guard pts.count > 500 else { throw ScanError.noKey }
        let m = pts.reduce(V2(0, 0), +) / Double(pts.count)
        var cxx = 0.0, cyy = 0.0, cxy = 0.0
        for p in pts { let d = p - m; cxx += d.x * d.x; cyy += d.y * d.y; cxy += d.x * d.y }
        var ang = 0.5 * atan2(2 * cxy, cxx - cyy)

        struct Bins { var lo: [Double]; var hi: [Double]; var umin: Double; var n: Int; var flipped: Bool }
        func binned(_ ang: Double) throws -> Bins {
            let ax = V2(cos(ang), sin(ang)), pp = V2(-sin(ang), cos(ang))
            var umin = Double.infinity, umax = -Double.infinity
            for p in pts { let u = simd_dot(p - m, ax); umin = min(umin, u); umax = max(umax, u) }
            let n = Int(umax - umin) + 1
            guard n > 60 else { throw ScanError.tooShort }
            var lo = [Double](repeating: .infinity, count: n), hi = [Double](repeating: -.infinity, count: n)
            for p in pts {
                let d = p - m
                let b = min(n - 1, Int(simd_dot(d, ax) - umin)), v = simd_dot(d, pp)
                lo[b] = min(lo[b], v); hi[b] = max(hi[b], v)
            }
            for i in 0..<n where lo[i] == .infinity { lo[i] = i > 0 ? lo[i - 1] : 0; hi[i] = i > 0 ? hi[i - 1] : 0 }
            func meanWidth(_ r: Range<Int>) -> Double { r.map { hi[$0] - lo[$0] }.reduce(0, +) / Double(r.count) }
            let k = max(5, n / 7)
            var fl = false
            if !(meanWidth((n - k)..<n) < meanWidth(0..<k)) { lo.reverse(); hi.reverse(); fl = true }
            return Bins(lo: lo, hi: hi, umin: umin, n: n, flipped: fl)
        }
        func shoulder(_ b: Bins) -> Int {
            let tipHalf = (b.n / 2..<b.n).map { b.hi[$0] - b.lo[$0] }.sorted()
            let limit = tipHalf[Int(Double(tipHalf.count) * 0.9)] * 1.15
            var sh = 0
            for i in stride(from: b.n - 1, through: 0, by: -1) where b.hi[i] - b.lo[i] > limit { sh = i + 1; break }
            return min(max(sh, 0), b.n - 20)
        }
        // Refine the axis: fit a line to the straight (uncut) blade edge so the key is exactly horizontal.
        for _ in 0..<2 {
            let b = try binned(ang)
            let sh = shoulder(b)
            let seg = Array(sh..<b.n)
            func std(_ x: [Double]) -> Double { let mu = x.reduce(0, +) / Double(x.count); return (x.map { ($0 - mu) * ($0 - mu) }.reduce(0, +) / Double(x.count)).squareRoot() }
            let hiv = seg.map { b.hi[$0] }, lov = seg.map { b.lo[$0] }
            let straight = std(hiv) < std(lov) ? hiv : lov
            let usesHigh = std(hiv) < std(lov)
            // robust line fit v = k*u + c on the straight edge (outer 50% of values on the extreme side)
            var us = seg.map(Double.init), vs = straight
            var k = 0.0
            for _ in 0..<3 {
                let nU = Double(us.count), su = us.reduce(0, +), sv = vs.reduce(0, +)
                let suu = us.map { $0 * $0 }.reduce(0, +), suv = zip(us, vs).map { $0 * $1 }.reduce(0, +)
                let den = nU * suu - su * su
                if abs(den) < 1e-9 { break }
                k = (nU * suv - su * sv) / den
                let c = (sv - k * su) / nU
                let res = zip(us, vs).map { $1 - (k * $0 + c) }
                let thr = max(1.5, std(res) * 1.0)
                let keep = zip(us, vs).enumerated().filter { abs(res[$0.offset]) <= thr }.map { $0.element }
                if keep.count < 20 { break }
                us = keep.map { $0.0 }; vs = keep.map { $0.1 }
            }
            _ = usesHigh
            if abs(k) < 2e-4 { break }
            // when flipped, the bin axis points opposite to the image axis: slope sign flips with it
            ang += (b.flipped ? -1 : 1) * atan(k)
        }
        let fin = try binned(ang)
        axis = V2(cos(ang), sin(ang)); perp = V2(-sin(ang), cos(ang)); mean = m
        vmin = fin.lo; vmax = fin.hi; u0 = fin.umin; bins = fin.n; flipped = fin.flipped
        detectedShoulder = Double(shoulder(fin))
    }

    /// Converts (bin along the oriented axis, v) back to image pixel coordinates.
    func point(_ bin: Double, _ v: Double) -> V2 {
        let b = flipped ? Double(bins - 1) - bin : bin
        return mean + axis * (b + u0) + perp * v
    }

    public func analyze(kl: Double, aspace: Double, pinspace: Double, pins: Int, hcut: Double, cutspace: Double,
                        shoulderBin: Double? = nil) throws -> Result {
        let sh = shoulderBin ?? detectedShoulder
        let tip = Double(bins - 1)
        guard tip - sh > 40, kl > 1 else { throw ScanError.tooShort }
        let mmpx = kl / (tip - sh)
        let a = Int(sh), b = bins - 1
        func std(_ x: [Double]) -> Double { let m = x.reduce(0, +) / Double(x.count); return (x.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(x.count)).squareRoot() }
        let hiSeg = Array(vmax[a...b]), loSeg = Array(vmin[a...b])
        let cutOnHigh = std(hiSeg) >= std(loSeg)
        let edge = cutOnHigh ? hiSeg : loSeg
        let sorted = edge.sorted()
        let outer = cutOnHigh ? sorted[Int(Double(sorted.count) * 0.95)] : sorted[Int(Double(sorted.count) * 0.05)]
        var depths: [Double] = [], levels: [Int] = [], res: [Double] = [], marks: [(a: V2, b: V2)] = []
        let half = max(2, Int(0.22 * pinspace / mmpx))
        for i in 0..<pins {
            let c = sh + (aspace + Double(i) * pinspace) / mmpx
            let lo = max(a, Int(c) - half), hi = min(b, Int(c) + half)
            guard lo < hi else { depths.append(0); levels.append(0); res.append(0.5); continue }
            var best = 0.0
            for j in lo...hi { best = max(best, cutOnHigh ? outer - vmax[j] : vmin[j] - outer) }
            let depthMM = best * mmpx
            depths.append(depthMM)
            let lvlF = cutspace > 0 ? (hcut - depthMM) / cutspace : 0
            let lvl = max(0, Int(lvlF.rounded()))
            levels.append(lvl)
            res.append(cutspace > 0 ? abs(lvlF - Double(lvl)) : 0)
            marks.append((point(c, -Double(bins)), point(c, Double(bins))))
        }
        return Result(depthsMM: depths, levels: levels, residuals: res, mmPerPixel: mmpx, shoulderU: sh, tipU: tip,
                      markers: marks, shoulderLine: (point(sh, -Double(bins)), point(sh, Double(bins))))
    }

    /// Photo with tinted key and pin / shoulder markers.
    public func preview(_ r: Result?) -> CGImage? {
        let w = trace.width, h = trace.height
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            let g = Double(trace.gray[i]), t = mask[i] ? 0.45 : 0.0
            rgba[i * 4] = UInt8(g * (1 - t) + 255 * t); rgba[i * 4 + 1] = UInt8(g * (1 - t) + 150 * t); rgba[i * 4 + 2] = UInt8(g * (1 - t))
        }
        guard let ctx = rgba.withUnsafeMutableBytes({ CGContext(data: $0.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) }) else { return nil }
        func line(_ a: V2, _ b: V2, _ c: CGColor, _ lw: CGFloat) {
            ctx.setStrokeColor(c); ctx.setLineWidth(lw)
            ctx.move(to: CGPoint(x: a.x, y: Double(h) - a.y)); ctx.addLine(to: CGPoint(x: b.x, y: Double(h) - b.y)); ctx.strokePath()
        }
        if let r = r {
            let scale = CGFloat(max(w, h)) / 900
            line(r.shoulderLine.a, r.shoulderLine.b, CGColor(red: 0.2, green: 0.6, blue: 1, alpha: 1), 3 * scale)
            for m in r.markers { line(m.a, m.b, CGColor(red: 0.1, green: 0.9, blue: 0.3, alpha: 1), 2 * scale) }
        }
        return ctx.makeImage()
    }
}
