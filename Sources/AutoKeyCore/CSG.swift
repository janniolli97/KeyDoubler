import Foundation
import simd

// BSP-tree CSG, a Swift port of the algorithm used by csg.js (MIT, Evan Wallace).
// Polygons must be convex.

struct Plane {
    var normal: V3
    var w: Double

    init(normal: V3, w: Double) { self.normal = normal; self.w = w }

    init?(points a: V3, _ b: V3, _ c: V3) {
        let n = simd_cross(b - a, c - a)
        let l = simd_length(n)
        if l < 1e-12 { return nil }
        normal = n / l
        w = simd_dot(normal, a)
    }

    func flipped() -> Plane { Plane(normal: -normal, w: -w) }

    func split(_ polygon: Polygon, _ coplanarFront: inout [Polygon], _ coplanarBack: inout [Polygon],
               _ front: inout [Polygon], _ back: inout [Polygon]) {
        var polygonType = 0
        var types: [Int] = []
        types.reserveCapacity(polygon.vertices.count)
        for v in polygon.vertices {
            let t = simd_dot(normal, v) - w
            let type = t < -eps ? 2 : (t > eps ? 1 : 0)   // 0 coplanar, 1 front, 2 back
            polygonType |= type
            types.append(type)
        }
        switch polygonType {
        case 0:
            if simd_dot(normal, polygon.plane.normal) > 0 { coplanarFront.append(polygon) } else { coplanarBack.append(polygon) }
        case 1: front.append(polygon)
        case 2: back.append(polygon)
        default:
            var f: [V3] = [], b: [V3] = []
            let count = polygon.vertices.count
            for i in 0..<count {
                let j = (i + 1) % count
                let ti = types[i], tj = types[j]
                let vi = polygon.vertices[i], vj = polygon.vertices[j]
                if ti != 2 { f.append(vi) }
                if ti != 1 { b.append(vi) }
                if (ti | tj) == 3 {
                    let t = (w - simd_dot(normal, vi)) / simd_dot(normal, vj - vi)
                    let v = vi + (vj - vi) * t
                    f.append(v); b.append(v)
                }
            }
            if f.count >= 3 { front.append(Polygon(f, plane: polygon.plane)) }
            if b.count >= 3 { back.append(Polygon(b, plane: polygon.plane)) }
        }
    }
}

public struct Polygon {
    public var vertices: [V3]
    var plane: Plane

    public init(_ vertices: [V3]) {
        self.vertices = vertices
        var p: Plane? = nil
        // robust normal: Newell's method
        var n = V3(0, 0, 0)
        for i in 0..<vertices.count {
            let a = vertices[i], b = vertices[(i + 1) % vertices.count]
            n.x += (a.y - b.y) * (a.z + b.z)
            n.y += (a.z - b.z) * (a.x + b.x)
            n.z += (a.x - b.x) * (a.y + b.y)
        }
        let l = simd_length(n)
        if l > 1e-14 { let nn = n / l; p = Plane(normal: nn, w: simd_dot(nn, vertices[0])) }
        self.plane = p ?? Plane(normal: V3(0, 0, 1), w: 0)
    }

    init(_ vertices: [V3], plane: Plane) { self.vertices = vertices; self.plane = plane }

    func flipped() -> Polygon { Polygon(vertices.reversed(), plane: plane.flipped()) }
}

public struct Solid {
    public var polygons: [Polygon]
    public init(polygons: [Polygon]) { self.polygons = polygons }

    public func subtracting(_ other: Solid) -> Solid {
        let a = BSPNode(polygons), b = BSPNode(other.polygons)
        a.invert(); a.clipTo(b); b.clipTo(a); b.invert(); b.clipTo(a); b.invert()
        a.build(b.allPolygons()); a.invert()
        return Solid(polygons: a.allPolygons())
    }

    public func union(_ other: Solid) -> Solid {
        let a = BSPNode(polygons), b = BSPNode(other.polygons)
        a.clipTo(b); b.clipTo(a); b.invert(); b.clipTo(a); b.invert()
        a.build(b.allPolygons())
        return Solid(polygons: a.allPolygons())
    }
}

final class BSPNode {
    var plane: Plane?
    var front: BSPNode?
    var back: BSPNode?
    var polygons: [Polygon] = []

    init(_ list: [Polygon]) { if !list.isEmpty { build(list) } }

    func invert() {
        // iterative to avoid deep recursion
        var stack: [BSPNode] = [self]
        while let n = stack.popLast() {
            n.polygons = n.polygons.map { $0.flipped() }
            n.plane = n.plane?.flipped()
            swap(&n.front, &n.back)
            if let f = n.front { stack.append(f) }
            if let b = n.back { stack.append(b) }
        }
    }

    func clipPolygons(_ list: [Polygon]) -> [Polygon] {
        guard let plane = plane else { return list }
        var f: [Polygon] = [], b: [Polygon] = []
        var cf: [Polygon] = [], cb: [Polygon] = []
        for p in list { plane.split(p, &cf, &cb, &f, &b) }
        f += cf; b += cb
        f = front?.clipPolygons(f) ?? f
        b = back?.clipPolygons(b) ?? []
        return f + b
    }

    func clipTo(_ bsp: BSPNode) {
        polygons = bsp.clipPolygons(polygons)
        front?.clipTo(bsp)
        back?.clipTo(bsp)
    }

    func allPolygons() -> [Polygon] {
        var out = polygons
        out += front?.allPolygons() ?? []
        out += back?.allPolygons() ?? []
        return out
    }

    func build(_ list: [Polygon]) {
        if list.isEmpty { return }
        if plane == nil {
            // Pick a middle polygon as splitter to keep the tree reasonably balanced.
            plane = list[list.count / 2].plane
        }
        var f: [Polygon] = [], b: [Polygon] = []
        var cf: [Polygon] = [], cb: [Polygon] = []
        for p in list { plane!.split(p, &cf, &cb, &f, &b) }
        polygons += cf; polygons += cb
        if !f.isEmpty {
            if front == nil { front = BSPNode([]) }
            front!.build(f)
        }
        if !b.isEmpty {
            if back == nil { back = BSPNode([]) }
            back!.build(b)
        }
    }
}
