import Foundation
import simd

/// A closed 2D outline (counter-clockwise, y up).
public struct Outline {
    public var points: [V2]
    public init(points: [V2]) { self.points = points }
}

// MARK: - SVG path parsing (M L H V C S Q T Z, absolute and relative)

public enum SVGProfile {
    public enum ParseError: Error { case noPath, tooFewPoints }

    public static func load(url: URL) throws -> Outline {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parse(text)
    }

    public static func parse(_ svg: String) throws -> Outline {
        // Collect all <path ... d="..." ... transform="..."> elements.
        var best: [V2] = []
        var bestArea = 0.0
        let pathRegex = try! NSRegularExpression(pattern: "<path\\b[^>]*>", options: [.dotMatchesLineSeparators])
        let ns = svg as NSString
        for m in pathRegex.matches(in: svg, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range)
            guard let d = attribute("d", in: tag) else { continue }
            let tf = attribute("transform", in: tag).map(parseTransform) ?? (1, 0, 0, 1, 0, 0)
            for sub in flatten(d) where sub.count >= 3 {
                let pts = sub.map { p -> V2 in
                    // SVG is y-down; the original pipeline (Inkscape -> EPS -> DXF) yields y-up.
                    let x = tf.0 * p.x + tf.2 * p.y + tf.4
                    let y = tf.1 * p.x + tf.3 * p.y + tf.5
                    return V2(x, -y)
                }
                let a = abs(signedArea(pts))
                if a > bestArea { bestArea = a; best = pts }   // largest sub-path is the outer outline
            }
        }
        guard !best.isEmpty else { throw ParseError.noPath }
        if signedArea(best) < 0 { best.reverse() }
        return Outline(points: best)
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        guard let r = tag.range(of: "\\s\(name)\\s*=\\s*\"([^\"]*)\"", options: .regularExpression) else { return nil }
        let s = String(tag[r])
        guard let q1 = s.firstIndex(of: "\""), let q2 = s.lastIndex(of: "\""), q1 < q2 else { return nil }
        return String(s[s.index(after: q1)..<q2])
    }

    typealias Mat = (Double, Double, Double, Double, Double, Double)

    static func parseTransform(_ s: String) -> Mat {
        var m: Mat = (1, 0, 0, 1, 0, 0)
        func mul(_ a: Mat, _ b: Mat) -> Mat {
            (a.0 * b.0 + a.2 * b.1, a.1 * b.0 + a.3 * b.1,
             a.0 * b.2 + a.2 * b.3, a.1 * b.2 + a.3 * b.3,
             a.0 * b.4 + a.2 * b.5 + a.4, a.1 * b.4 + a.3 * b.5 + a.5)
        }
        let re = try! NSRegularExpression(pattern: "(\\w+)\\s*\\(([^)]*)\\)")
        let ns = s as NSString
        for mt in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: mt.range(at: 1))
            let args = numbers(ns.substring(with: mt.range(at: 2)))
            var t: Mat = (1, 0, 0, 1, 0, 0)
            switch name {
            case "translate": t.4 = args.first ?? 0; t.5 = args.count > 1 ? args[1] : 0
            case "scale": t.0 = args.first ?? 1; t.3 = args.count > 1 ? args[1] : t.0
            case "matrix" where args.count == 6: t = (args[0], args[1], args[2], args[3], args[4], args[5])
            case "rotate":
                let a = (args.first ?? 0) * .pi / 180
                t = (cos(a), sin(a), -sin(a), cos(a), 0, 0)
            default: break
            }
            m = mul(m, t)
        }
        return m
    }

    static func numbers(_ s: String) -> [Double] {
        let re = try! NSRegularExpression(pattern: "[-+]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?")
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { Double(ns.substring(with: $0.range)) }
    }

    static func flatten(_ d: String) -> [[V2]] {
        // Tokenise into commands and numbers.
        let re = try! NSRegularExpression(pattern: "[A-Za-z]|[-+]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?")
        let ns = d as NSString
        let tokens = re.matches(in: d, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        var i = 0
        var subs: [[V2]] = []
        var cur: [V2] = []
        var pos = V2(0, 0), start = V2(0, 0)
        var lastCtrl: V2? = nil, lastCmd: Character = " "
        var cmd: Character = " "

        func num() -> Double { defer { i += 1 }; return i < tokens.count ? (Double(tokens[i]) ?? 0) : 0 }
        func isCmd(_ t: String) -> Bool { t.count == 1 && t.first!.isLetter && !(t == "e" || t == "E") }

        func cubic(_ p0: V2, _ p1: V2, _ p2: V2, _ p3: V2) {
            let len = simd_length(p1 - p0) + simd_length(p2 - p1) + simd_length(p3 - p2)
            let n = max(4, min(40, Int(len / 0.6)))
            for k in 1...n {
                let t = Double(k) / Double(n), u = 1 - t
                cur.append(u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3)
            }
        }

        while i < tokens.count {
            if isCmd(tokens[i]) { cmd = tokens[i].first!; i += 1 }
            let rel = cmd.isLowercase
            switch cmd {
            case "M", "m":
                if cur.count > 1 { subs.append(cur) }
                let p = V2(num(), num())
                pos = rel ? pos + p : p
                start = pos; cur = [pos]
                cmd = rel ? "l" : "L"
            case "L", "l":
                let p = V2(num(), num()); pos = rel ? pos + p : p; cur.append(pos)
            case "H", "h":
                let x = num(); pos.x = rel ? pos.x + x : x; cur.append(pos)
            case "V", "v":
                let y = num(); pos.y = rel ? pos.y + y : y; cur.append(pos)
            case "C", "c":
                var p1 = V2(num(), num()), p2 = V2(num(), num()), p3 = V2(num(), num())
                if rel { p1 += pos; p2 += pos; p3 += pos }
                cubic(pos, p1, p2, p3); lastCtrl = p2; pos = p3
            case "S", "s":
                var p2 = V2(num(), num()), p3 = V2(num(), num())
                if rel { p2 += pos; p3 += pos }
                let p1 = ("CcSs".contains(lastCmd) ? lastCtrl.map { 2 * pos - $0 } : nil) ?? pos
                cubic(pos, p1, p2, p3); lastCtrl = p2; pos = p3
            case "Q", "q":
                var c = V2(num(), num()), p = V2(num(), num())
                if rel { c += pos; p += pos }
                cubic(pos, pos + 2.0 / 3 * (c - pos), p + 2.0 / 3 * (c - p), p); lastCtrl = c; pos = p
            case "T", "t":
                var p = V2(num(), num()); if rel { p += pos }
                let c = ("QqTt".contains(lastCmd) ? lastCtrl.map { 2 * pos - $0 } : nil) ?? pos
                cubic(pos, pos + 2.0 / 3 * (c - pos), p + 2.0 / 3 * (c - p), p); lastCtrl = c; pos = p
            case "Z", "z":
                if cur.count > 1 { subs.append(cur) }
                cur = []; pos = start
                if i < tokens.count && !isCmd(tokens[i]) { cur = [pos] }
            default:
                i += 1   // unsupported command (e.g. arcs): skip token
            }
            lastCmd = cmd
            if !"CcSsQqTt".contains(cmd) { lastCtrl = nil }
            if cmd == "Z" || cmd == "z" { cmd = " " }
        }
        if cur.count > 2 { subs.append(cur) }
        return subs
    }
}

public func signedArea(_ p: [V2]) -> Double {
    var a = 0.0
    for i in 0..<p.count { let j = (i + 1) % p.count; a += p[i].x * p[j].y - p[j].x * p[i].y }
    return a / 2
}

// MARK: - Outline operations

extension Outline {
    /// Remove (near) duplicate and collinear points.
    public func cleaned(minDist: Double = 0.02) -> Outline {
        var out: [V2] = []
        for p in points where out.isEmpty || simd_length(p - out.last!) > minDist { out.append(p) }
        while out.count > 1, simd_length(out.first! - out.last!) <= minDist { out.removeLast() }
        // drop collinear
        var changed = true
        while changed && out.count > 3 {
            changed = false
            var res: [V2] = []
            for i in 0..<out.count {
                let a = out[(i + out.count - 1) % out.count], b = out[i], c = out[(i + 1) % out.count]
                let cr = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
                if abs(cr) < 1e-9 { changed = true } else { res.append(b) }
            }
            out = res
        }
        return Outline(points: out)
    }

    /// Douglas-Peucker simplification of a closed outline.
    public func simplified(tolerance t: Double) -> Outline {
        let p = points
        guard p.count > 8 else { return self }
        var far = 0, best = 0.0
        for i in 1..<p.count { let d = simd_length(p[i] - p[0]); if d > best { best = d; far = i } }
        func dp(_ a: Int, _ b: Int, _ path: [V2]) -> [V2] {   // returns points in (a, b] of the open path
            var idx = -1, dmax = 0.0
            let pa = path[a], pb = path[b], ab = pb - pa
            let len = simd_length(ab)
            if b > a + 1 {
                for i in (a + 1)..<b {
                    let d = len < 1e-12 ? simd_length(path[i] - pa) : abs(ab.x * (path[i].y - pa.y) - ab.y * (path[i].x - pa.x)) / len
                    if d > dmax { dmax = d; idx = i }
                }
            }
            if dmax > t { return dp(a, idx, path) + dp(idx, b, path) }
            return [pb]
        }
        let first = Array(p[0...far]), second = Array(p[far...]) + [p[0]]
        let out = [p[0]] + dp(0, first.count - 1, first) + dp(0, second.count - 1, second).dropLast()
        return Outline(points: out)
    }

    public var bounds: (min: V2, max: V2) {
        var lo = V2(repeating: .infinity), hi = V2(repeating: -.infinity)
        for p in points { lo = simd.min(lo, p); hi = simd.max(hi, p) }
        return (lo, hi)
    }

    /// OpenSCAD `resize([0, h, 0], auto=[true,true,false])` on a profile whose bbox starts at the origin:
    /// uniform scale so the height equals h; the bbox minimum is moved to the origin first.
    public func normalized(height h: Double) -> Outline {
        let b = bounds
        let s = h / (b.max.y - b.min.y)
        return Outline(points: points.map { ($0 - b.min) * s })
    }

    /// Inward offset (erosion) by `d` using per-vertex miter normals. Equivalent to the
    /// Minkowski-with-circle thinning of the original at the scale of a few tenths of a millimetre.
    func eroded(by d: Double) -> Outline {
        guard d > 0 else { return self }
        let n = points.count
        var out: [V2] = []
        for i in 0..<n {
            let a = points[(i + n - 1) % n], b = points[i], c = points[(i + 1) % n]
            let e1 = simd_normalize(b - a), e2 = simd_normalize(c - b)
            // CCW polygon: inward normal is the left normal (-y, x)
            let n1 = V2(-e1.y, e1.x), n2 = V2(-e2.y, e2.x)
            var m = n1 + n2
            let ml = simd_length(m)
            if ml < 1e-9 { out.append(b + n1 * d); continue }
            m /= ml
            let k = max(simd_dot(m, n1), 0.35)
            out.append(b + m * (d / k))
        }
        return Outline(points: out).removingLoops()
    }

    /// Cut away small self-intersection loops produced by offsetting.
    func removingLoops() -> Outline {
        var p = points
        func inter(_ a: V2, _ b: V2, _ c: V2, _ d: V2) -> V2? {
            let r = b - a, s = d - c
            let den = r.x * s.y - r.y * s.x
            if abs(den) < 1e-14 { return nil }
            let t = ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / den
            let u = ((c.x - a.x) * r.y - (c.y - a.y) * r.x) / den
            return (t > 1e-9 && t < 1 - 1e-9 && u > 1e-9 && u < 1 - 1e-9) ? a + r * t : nil
        }
        var iter = 0
        outer: while iter < 2000 {
            iter += 1
            let n = p.count
            if n < 4 { break }
            for i in 0..<n {
                for j in stride(from: i + 2, to: n, by: 1) {
                    if i == 0 && j == n - 1 { continue }
                    guard let x = inter(p[i], p[(i + 1) % n], p[j], p[(j + 1) % n]) else { continue }
                    // loop A: vertices i+1...j ; loop B: the rest. Drop the shorter one.
                    let inner = j - i
                    if inner <= n - inner {
                        p = Array(p[0...i]) + [x] + Array(p[(j + 1)...])
                    } else {
                        p = Array(p[(i + 1)...j]) + [x]
                    }
                    continue outer
                }
            }
            break
        }
        return Outline(points: p)
    }
}

// MARK: - Triangulation (ear clipping, simple CCW polygon)

public func triangulate(_ pts: [V2]) -> [(Int, Int, Int)] {
    var idx = Array(0..<pts.count)
    var tris: [(Int, Int, Int)] = []
    func cross(_ a: V2, _ b: V2, _ c: V2) -> Double { (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) }
    func inside(_ p: V2, _ a: V2, _ b: V2, _ c: V2) -> Bool {
        cross(a, b, p) >= -1e-12 && cross(b, c, p) >= -1e-12 && cross(c, a, p) >= -1e-12
    }
    var guardCount = 0
    while idx.count > 3 && guardCount < 100000 {
        guardCount += 1
        var clipped = false
        for k in 0..<idx.count {
            let ia = idx[(k + idx.count - 1) % idx.count], ib = idx[k], ic = idx[(k + 1) % idx.count]
            let a = pts[ia], b = pts[ib], c = pts[ic]
            if cross(a, b, c) <= 1e-12 { continue }
            var ok = true
            for j in idx where j != ia && j != ib && j != ic {
                if inside(pts[j], a, b, c) { ok = false; break }
            }
            if ok { tris.append((ia, ib, ic)); idx.remove(at: k); clipped = true; break }
        }
        if !clipped {   // degenerate: drop the flattest vertex
            idx.remove(at: 0)
        }
    }
    if idx.count == 3 { tris.append((idx[0], idx[1], idx[2])) }
    return tris
}

/// Extrude a CCW outline along z from z0 to z1.
public func extrude(_ outline: Outline, z0: Double, z1: Double) -> Solid {
    let p = outline.points
    var polys: [Polygon] = []
    for i in 0..<p.count {
        let j = (i + 1) % p.count
        polys.append(Polygon([V3(p[i].x, p[i].y, z0), V3(p[j].x, p[j].y, z0), V3(p[j].x, p[j].y, z1), V3(p[i].x, p[i].y, z1)]))
    }
    for t in triangulate(p) {
        polys.append(Polygon([V3(p[t.0].x, p[t.0].y, z1), V3(p[t.1].x, p[t.1].y, z1), V3(p[t.2].x, p[t.2].y, z1)]))
        polys.append(Polygon([V3(p[t.2].x, p[t.2].y, z0), V3(p[t.1].x, p[t.1].y, z0), V3(p[t.0].x, p[t.0].y, z0)]))
    }
    return Solid(polygons: polys)
}
