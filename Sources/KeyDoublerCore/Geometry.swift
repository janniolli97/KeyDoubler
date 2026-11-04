import Foundation
import simd

public typealias V3 = SIMD3<Double>
public typealias V2 = SIMD2<Double>

let eps = 1e-5

// MARK: - Transforms (matrix chain order matches OpenSCAD nesting: outer * inner)

public enum Xf {
    public static func translate(_ x: Double, _ y: Double, _ z: Double) -> simd_double4x4 {
        var m = matrix_identity_double4x4
        m.columns.3 = SIMD4(x, y, z, 1)
        return m
    }
    public static func rotate(_ ax: Double, _ ay: Double, _ az: Double) -> simd_double4x4 {
        func rad(_ d: Double) -> Double { d * .pi / 180 }
        let (cx, sx) = (cos(rad(ax)), sin(rad(ax)))
        let (cy, sy) = (cos(rad(ay)), sin(rad(ay)))
        let (cz, sz) = (cos(rad(az)), sin(rad(az)))
        let rx = simd_double4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, cx, sx, 0), SIMD4(0, -sx, cx, 0), SIMD4(0, 0, 0, 1)))
        let ry = simd_double4x4(columns: (SIMD4(cy, 0, -sy, 0), SIMD4(0, 1, 0, 0), SIMD4(sy, 0, cy, 0), SIMD4(0, 0, 0, 1)))
        let rz = simd_double4x4(columns: (SIMD4(cz, sz, 0, 0), SIMD4(-sz, cz, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
        return rz * ry * rx   // OpenSCAD: rotate([a,b,c]) = Rz(c) * Ry(b) * Rx(a)
    }
}

func apply(_ m: simd_double4x4, _ p: V3) -> V3 {
    let r = m * SIMD4(p.x, p.y, p.z, 1)
    return V3(r.x, r.y, r.z)
}

// MARK: - Primitives

/// Corner points of a cube.
public func cubePoints(_ size: V3, center: Bool) -> [V3] {
    let lo = center ? -size / 2 : V3(0, 0, 0)
    let hi = lo + size
    var pts: [V3] = []
    for x in [lo.x, hi.x] { for y in [lo.y, hi.y] { for z in [lo.z, hi.z] { pts.append(V3(x, y, z)) } } }
    return pts
}

/// Brute-force convex hull for small point sets. Returns outward-facing CCW polygons.
public func convexHullFaces(_ input: [V3]) -> [[V3]] {
    var pts: [V3] = []
    for p in input where !pts.contains(where: { simd_length($0 - p) < 1e-9 }) { pts.append(p) }
    guard pts.count >= 4 else { return [] }
    let c = pts.reduce(V3(0, 0, 0), +) / Double(pts.count)
    var planes: [(n: V3, d: Double)] = []
    var faces: [[V3]] = []
    let n = pts.count
    for i in 0..<n { for j in (i + 1)..<n { for k in (j + 1)..<n {
        var nrm = simd_cross(pts[j] - pts[i], pts[k] - pts[i])
        let len = simd_length(nrm)
        if len < 1e-9 { continue }
        nrm /= len
        var d = simd_dot(nrm, pts[i])
        var pos = false, neg = false
        for p in pts {
            let s = simd_dot(nrm, p) - d
            if s > 1e-7 { pos = true } else if s < -1e-7 { neg = true }
            if pos && neg { break }
        }
        if pos && neg { continue }
        if simd_dot(nrm, c) - d > 0 { nrm = -nrm; d = -d }
        if planes.contains(where: { simd_length($0.n - nrm) < 1e-7 && abs($0.d - d) < 1e-7 }) { continue }
        planes.append((nrm, d))
        let on = pts.filter { abs(simd_dot(nrm, $0) - d) < 1e-7 }
        let fc = on.reduce(V3(0, 0, 0), +) / Double(on.count)
        let ref = abs(nrm.x) < 0.9 ? V3(1, 0, 0) : V3(0, 1, 0)
        let u = simd_normalize(simd_cross(nrm, ref))
        let v = simd_cross(nrm, u)
        let sorted = on.sorted {
            atan2(simd_dot($0 - fc, v), simd_dot($0 - fc, u)) < atan2(simd_dot($1 - fc, v), simd_dot($1 - fc, u))
        }
        faces.append(sorted)
    } } }
    return faces
}

public func hullSolid(_ pts: [V3]) -> Solid {
    Solid(polygons: convexHullFaces(pts).map { Polygon($0) })
}

public func boxSolid(_ size: V3, center: Bool, _ m: simd_double4x4 = matrix_identity_double4x4) -> Solid {
    hullSolid(cubePoints(size, center: center).map { apply(m, $0) })
}

// MARK: - Mesh volume / export helpers

public extension Solid {
    var triangles: [(V3, V3, V3)] {
        var out: [(V3, V3, V3)] = []
        for p in polygons where p.vertices.count >= 3 {
            for i in 1..<(p.vertices.count - 1) { out.append((p.vertices[0], p.vertices[i], p.vertices[i + 1])) }
        }
        return out
    }
    var volume: Double {
        triangles.reduce(0) { $0 + simd_dot($1.0, simd_cross($1.1, $1.2)) / 6 }
    }
    func transformed(_ m: simd_double4x4) -> Solid {
        Solid(polygons: polygons.map { Polygon($0.vertices.map { apply(m, $0) }) })
    }
    var bounds: (min: V3, max: V3) {
        var lo = V3(repeating: .infinity), hi = V3(repeating: -.infinity)
        for p in polygons { for v in p.vertices { lo = simd.min(lo, v); hi = simd.max(hi, v) } }
        return (lo, hi)
    }
}
