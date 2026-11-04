import AutoKeyCore
import simd
func selftest() {
    let b = boxSolid(V3(2, 3, 4), center: false)
    print("box vol (24):", b.volume, "polys", b.polygons.count)
    let c = boxSolid(V3(2, 3, 4), center: false, Xf.translate(1, 1, 1))
    print("sub vol (24-1*2*3... =", b.subtracting(c).volume, ") expect", 24 - 1 * 2 * 3)
    print("union vol expect", 48 - 6, b.union(c).volume)
    let r = boxSolid(V3(10, 10, 10), center: true, Xf.rotate(40, 0, 0))
    print("rotated cube vol 1000:", r.volume)
}
func selftest2() {
    let sq = Outline(points: [V2(0,0), V2(2,0), V2(2,8), V2(0,8)])
    let e = extrude(sq, z0: -13, z1: 13)
    print("prism vol expect", 2*8*26, e.volume)
    let cut = boxSolid(V3(10, 20, 20), center: true, Xf.translate(0, 0, -13 - 10 + 3) * Xf.rotate(40, 0, 0))
    print("cutter vol 4000:", cut.volume, cut.bounds)
    let r = e.subtracting(cut)
    print("after cut", r.volume, "removed", e.volume - r.volume)
    let ci = Outline(points: (0..<64).map { V2(1 + 1*cos(Double($0)/64*2 * .pi), 4 + 4*sin(Double($0)/64*2 * .pi)) })
    let e2 = extrude(ci, z0: -13, z1: 13)
    print("ellipse prism vol", e2.volume, "tri count", triangulate(ci.points).count)
    print("after cut", e2.subtracting(cut).volume)
}
import CoreGraphics
import ImageIO
import Foundation
func phototest(_ catalogRoot: String) throws {
    // Render the AB-AB95 outline as a dark shape on white, 600px tall, slightly rotated colours (simulated photo)
    let o = try SVGProfile.load(url: URL(fileURLWithPath: catalogRoot + "/profiles/AB-AB95.svg"))
    let b = o.bounds, s = 600 / (b.max.y - b.min.y)
    let w = Int((b.max.x - b.min.x) * s) + 200, h = 800
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    ctx.setFillColor(gray: 0.85, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(gray: 0.15, alpha: 1)
    let pts = o.points.map { CGPoint(x: ($0.x - b.min.x) * s + 100, y: ($0.y - b.min.y) * s + 100) }
    ctx.move(to: pts[0]); pts.dropFirst().forEach { ctx.addLine(to: $0) }; ctx.fillPath()
    let img = ctx.makeImage()!
    let url = URL(fileURLWithPath: "/tmp/claude-501/photo.png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
    let t = try PhotoTrace(url: url)
    let thr = t.otsuThreshold()
    let tr = try t.outline(threshold: thr, keyIsDark: true)
    let ref = abs(signedAreaPublic(o.points)) * s * s
    print("otsu", thr, "traced pts", tr.points.count, "area ratio traced/reference", abs(signedAreaPublic(tr.points)) / ref)
    let svg = PhotoTrace.svg(tr)
    try svg.write(to: URL(fileURLWithPath: "/tmp/claude-501/traced.svg"), atomically: true, encoding: .utf8)
    let back = try SVGProfile.parse(svg)
    print("reparsed pts", back.points.count)
}
func signedAreaPublic(_ p: [V2]) -> Double { var a = 0.0; for i in 0..<p.count { let j = (i+1)%p.count; a += p[i].x*p[j].y - p[j].x*p[i].y }; return a/2 }
func scantest() throws {
    // synthetic flat key, tip pointing left, rotated 12 degrees, 20 px/mm
    let px = 20.0, kl = 27.0, aspace = 4.62, pinspace = 3.1, hcut = 3.69, cs = 0.54, phk = 8.35
    let truth = [0, 2, 1, 3, 0, 2]
    let W = 1400, H = 700
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    ctx.setFillColor(gray: 0.9, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    ctx.translateBy(x: 700, y: 350); ctx.rotate(by: 12 * .pi / 180)
    ctx.setFillColor(gray: 0.2, alpha: 1)
    // local frame: x to the right = handle side, tip at x = -kl*px/2 ... shoulder at +kl/2
    let x0 = -kl * px / 2, x1 = kl * px / 2          // tip .. shoulder
    let top = -phk * px / 2
    // handle bow
    ctx.fill(CGRect(x: x1, y: top - 40, width: 170, height: phk * px + 80))
    var path = CGMutablePath()
    path.move(to: CGPoint(x: x0, y: top)); path.addLine(to: CGPoint(x: x1, y: top)); path.addLine(to: CGPoint(x: x1, y: -top))
    // cut edge = bottom (y = -top); walk from shoulder to tip
    for (i, lv) in truth.enumerated() {
        let c = x1 - (aspace + Double(i) * pinspace) * px, d = (hcut - Double(lv) * cs) * px, w = 0.5 * px
        path.addLine(to: CGPoint(x: c + w + 0.8 * px, y: -top)); path.addLine(to: CGPoint(x: c + w, y: -top - d))
        path.addLine(to: CGPoint(x: c - w, y: -top - d)); path.addLine(to: CGPoint(x: c - w - 0.8 * px, y: -top))
    }
    path.addLine(to: CGPoint(x: x0, y: -top)); path.closeSubpath()
    ctx.addPath(path); ctx.fillPath()
    let url = URL(fileURLWithPath: "/tmp/claude-501/keyflat.png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
    let t = try PhotoTrace(url: url)
    let s = try KeyScan(trace: t, threshold: t.otsuThreshold(), keyIsDark: true)
    let r = try s.analyze(kl: kl, aspace: aspace, pinspace: pinspace, pins: 6, hcut: hcut, cutspace: cs)
    print("truth ", truth); print("levels", r.levels); print("depths", r.depthsMM.map { String(format: "%.2f", $0) }, "res", r.residuals.map { String(format: "%.2f", $0) })
    print("mm/px", r.mmPerPixel, "(expected ~", 1 / px, "* image scale)")
}

// Realistic photo conditions for the key scan. Each case renders a known key and compares the read levels.
func scanCases() throws {
    let px = 20.0, kl = 27.0, aspace = 4.62, pinspace = 3.1, hcut = 3.69, cs = 0.54, phk = 8.35
    let truth = [0, 2, 1, 3, 0, 2]
    func keyPath() -> (CGPath, CGRect) {
        let x0 = -kl * px / 2, x1 = kl * px / 2, top = -phk * px / 2
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x0, y: top)); p.addLine(to: CGPoint(x: x1, y: top)); p.addLine(to: CGPoint(x: x1, y: -top))
        for (i, lv) in truth.enumerated() {
            let c = x1 - (aspace + Double(i) * pinspace) * px, d = (hcut - Double(lv) * cs) * px, w = 0.5 * px
            p.addLine(to: CGPoint(x: c + w + 0.8 * px, y: -top)); p.addLine(to: CGPoint(x: c + w, y: -top - d))
            p.addLine(to: CGPoint(x: c - w, y: -top - d)); p.addLine(to: CGPoint(x: c - w - 0.8 * px, y: -top))
        }
        p.addLine(to: CGPoint(x: x0, y: -top)); p.closeSubpath()
        p.addRect(CGRect(x: x1, y: top - 40, width: 170, height: phk * px + 80))
        return (p, CGRect(x: x0, y: top - 40, width: x1 + 170 - x0, height: phk * px + 80))
    }
    struct Case { let name: String; let W: Int; let H: Int; let dark: Bool; let draw: (CGContext, CGPath, CGRect) -> Void }
    let cases: [Case] = [
        Case(name: "sauber", W: 1400, H: 700, dark: true) { c, p, _ in
            c.setFillColor(gray: 0.2, alpha: 1); c.addPath(p); c.fillPath()
        },
        Case(name: "Papier auf dunklem Tisch", W: 1600, H: 1000, dark: true) { c, p, _ in
            c.setFillColor(gray: 0.2, alpha: 1); c.addPath(p); c.fillPath()
        },
        Case(name: "Schatten am Schlüssel", W: 1400, H: 700, dark: true) { c, p, _ in
            c.saveGState(); c.setShadow(offset: CGSize(width: 10, height: -14), blur: 14, color: CGColor(gray: 0, alpha: 0.65))
            c.setFillColor(gray: 0.2, alpha: 1); c.addPath(p); c.fillPath(); c.restoreGState()
        },
        Case(name: "Metall mit Spiegelungen", W: 1400, H: 700, dark: true) { c, p, r in
            c.saveGState(); c.addPath(p); c.clip()
            c.setFillColor(gray: 0.45, alpha: 1); c.fill(r)
            c.setFillColor(gray: 0.86, alpha: 1)
            for x in stride(from: r.minX + 40, to: r.maxX, by: 130) { c.fill(CGRect(x: x, y: r.minY, width: 14, height: r.height)) }
            c.restoreGState()
        },
        Case(name: "kleiner Schlüssel im Großfoto", W: 4000, H: 3000, dark: true) { c, p, _ in
            c.setFillColor(gray: 0.2, alpha: 1); c.addPath(p); c.fillPath()
        },
    ]
    for k in cases {
        let ctx = CGContext(data: nil, width: k.W, height: k.H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
        if k.name.hasPrefix("Papier") {
            ctx.setFillColor(gray: 0.08, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: k.W, height: k.H))
            ctx.setFillColor(gray: 0.9, alpha: 1); ctx.fill(CGRect(x: 180, y: 120, width: k.W - 360, height: k.H - 240))
        } else {
            ctx.setFillColor(gray: 0.9, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: k.W, height: k.H))
        }
        ctx.translateBy(x: Double(k.W) / 2, y: Double(k.H) / 2); ctx.rotate(by: 12 * .pi / 180)
        let (path, rect) = keyPath()
        k.draw(ctx, path, rect)
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "akcase.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
        do {
            let t0 = Date()
            let t = try PhotoTrace(url: url, maxDimension: KeyScan.scanDimension)
            let s = try KeyScan(trace: t, threshold: t.otsuThreshold(), keyIsDark: k.dark)
            let r = try s.analyze(kl: kl, aspace: aspace, pinspace: pinspace, pins: 6, hcut: hcut, cutspace: cs)
            let soll = 0.05 * Double(max(k.W, k.H)) / Double(max(t.width, t.height))
            print(r.levels == truth ? "OK    " : "FALSCH", k.name, r.levels, String(format: "%.3f mm/px (soll ca. %.3f), %.2fs", r.mmPerPixel, soll, Date().timeIntervalSince(t0)))
            let t1 = Date()
            if let v = t.subjectMask() {
                let av = try KeyScan(trace: t, mask: t.keyShape(in: v)).analyze(kl: kl, aspace: aspace, pinspace: pinspace, pins: 6, hcut: hcut, cutspace: cs)
                print(av.levels == truth ? "  auto OK    " : "  auto FALSCH", av.levels, String(format: "%.2fs", Date().timeIntervalSince(t1)))
            } else { print("  auto: kein Motiv gefunden") }
        } catch { print("FEHLER", k.name, error.localizedDescription) }
    }
}

/// Runs detection on a real photo and writes preview images next to `outPrefix`.
func photoCheck(_ path: String, outPrefix: String) throws {
    func save(_ img: CGImage?, _ name: String) {
        guard let img else { return }
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPrefix + name) as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
    }
    let t = try PhotoTrace(url: URL(fileURLWithPath: path), maxDimension: KeyScan.scanDimension)
    if let v = t.subjectMask() {
        let shape = t.keyShape(in: v)
        print("vision maskFraction", Double(shape.filter { $0 }.count) / Double(shape.count))
        save(t.preview(mask: shape, outline: try? t.outline(mask: shape)), "-vision.png")
        let s = try KeyScan(trace: t, mask: shape)
        print("auto looksLikeFlatKey", s.looksLikeFlatKey, "bins", s.bins, "shoulder", s.detectedShoulder)
        let r = try s.analyze(kl: 27, aspace: 4.62, pinspace: 3.1, pins: 6, hcut: 3.69, cutspace: 0.54)
        print("auto levels", r.levels, "depths", r.depthsMM.map { String(format: "%.2f", $0) }, String(format: "%.3f mm/px", r.mmPerPixel))
        save(s.preview(r), "-autoscan.png")
    } else { print("vision: kein Motiv") }
    let thr = t.otsuThreshold(), dark = t.suggestedKeyIsDark(threshold: thr)
    let m = t.mask(threshold: thr, keyIsDark: dark)
    print("size \(t.width)x\(t.height) otsu \(thr) keyIsDark \(dark) maskFraction", Double(m.filter { $0 }.count) / Double(m.count))
    save(t.preview(mask: m, outline: try? t.outline(threshold: thr, keyIsDark: dark)), "-mask.png")
    let s = try KeyScan(trace: t, threshold: thr, keyIsDark: dark)
    print("looksLikeFlatKey", s.looksLikeFlatKey, "bins", s.bins, "shoulder", s.detectedShoulder)
    let r = try s.analyze(kl: 27, aspace: 4.62, pinspace: 3.1, pins: 6, hcut: 3.69, cutspace: 0.54)
    print("levels", r.levels, "depths", r.depthsMM.map { String(format: "%.2f", $0) })
    save(s.preview(r), "-scan.png")
}

/// The bundled key profiles are cross-sections and must not be taken for flat keys.
func flatCheck(_ root: String) throws {
    let dir = root + "/profiles"
    for f in try FileManager.default.contentsOfDirectory(atPath: dir).sorted() where f.hasSuffix(".svg") {
        let o = try SVGProfile.load(url: URL(fileURLWithPath: dir + "/" + f)).normalized(height: 600)
        let ctx = CGContext(data: nil, width: 900, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
        ctx.setFillColor(gray: 0.9, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 800))
        ctx.setFillColor(gray: 0.15, alpha: 1)
        let pts = o.points.map { CGPoint(x: $0.x + 300, y: $0.y + 100) }
        ctx.move(to: pts[0]); pts.dropFirst().forEach { ctx.addLine(to: $0) }; ctx.fillPath()
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "akflat.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
        let t = try PhotoTrace(url: url)
        let s = try KeyScan(trace: t, threshold: t.otsuThreshold(), keyIsDark: true)
        print(s.looksLikeFlatKey ? "FLACH " : "ok    ", f)
    }
}
