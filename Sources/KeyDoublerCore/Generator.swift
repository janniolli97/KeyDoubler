import Foundation
import simd

public enum KeyMode: String, CaseIterable, Identifiable {
    case blank = "Rohling", bumpkey = "Bump-Key", key = "Schlüssel"
    public var id: String { rawValue }
}

public struct KeyOptions {
    public var mode: KeyMode = .blank
    public var combination: String = ""
    public var tolerance: Double? = nil
    public var thinHandle = false
    public var matchHandleConnector = false
    public init() {}
}

public struct Catalog {
    public let root: URL
    public let userRoot: URL
    public struct Item: Identifiable, Hashable { public let id: String; public let url: URL; public var isCustom = false }
    public let profiles: [Item]
    public let definitions: [Item]

    public static var defaultUserRoot: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = base.appendingPathComponent("KeyDoubler")
        // Earlier versions were called AutoKey3D: keep their saved profiles, systems and keys.
        let old = base.appendingPathComponent("AutoKey3D")
        if !fm.fileExists(atPath: root.path), fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: root) }
        return root
    }

    public init(root: URL, userRoot: URL = Catalog.defaultUserRoot) {
        self.root = root
        self.userRoot = userRoot
        let fm = FileManager.default
        func list(_ base: URL, _ dir: String, needSVG: Bool, custom: Bool) -> [Item] {
            let d = base.appendingPathComponent(dir)
            let files = (try? fm.contentsOfDirectory(atPath: d.path)) ?? []
            return files.filter { $0.hasSuffix(".scad") }
                .filter { !needSVG || files.contains($0.replacingOccurrences(of: ".scad", with: ".svg")) }
                .sorted().map { Item(id: String($0.dropLast(5)), url: d.appendingPathComponent($0), isCustom: custom) }
        }
        profiles = list(root, "profiles", needSVG: true, custom: false) + list(userRoot, "profiles", needSVG: true, custom: true)
        definitions = list(root, "definitions", needSVG: false, custom: false) + list(userRoot, "definitions", needSVG: false, custom: true)
    }

    /// Locate the data directory: KEYDOUBLER_DATA env, app bundle Resources/data, or the repo checkout.
    public static func locate() -> Catalog? {
        var candidates: [URL] = []
        if let env = ProcessInfo.processInfo.environment["KEYDOUBLER_DATA"] { candidates.append(URL(fileURLWithPath: env)) }
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("data")) }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("../data"))
        for c in candidates where FileManager.default.fileExists(atPath: c.appendingPathComponent("profiles").path) {
            return Catalog(root: c.standardizedFileURL)
        }
        return nil
    }

    // MARK: custom data

    public struct CustomProfile {
        public var name: String; public var svg: URL
        public var height: Double; public var tolerance: Double
        public var connectorWidth: Double?
        public init(name: String, svg: URL, height: Double, tolerance: Double, connectorWidth: Double? = nil) {
            self.name = name; self.svg = svg; self.height = height; self.tolerance = tolerance; self.connectorWidth = connectorWidth
        }
    }
    public struct CustomSystem {
        public var name: String
        public var keyLength: Double
        public var shoulder = 0.0, pinSpacing = 0.0, deepestCut = 0.0, cutStep = 0.0, cutAngle = 90.0, plateau = 0.0
        /// Height of the finished blade. Replaces the height of the chosen profile, whose shape is scaled to fit.
        public var bladeHeight: Double?
        /// Thickness of the finished blade. Stretches the profile in that direction only.
        public var bladeThickness: Double?
        public init(name: String, keyLength: Double) { self.name = name; self.keyLength = keyLength }
    }

    public static func safeName(_ s: String) throws -> String {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-")
        guard !t.isEmpty, t.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil, !t.hasPrefix(".") else {
            throw GenError.msg("Name darf nur Buchstaben, Ziffern, - und _ enthalten.")
        }
        return t
    }

    public func addProfile(_ p: CustomProfile) throws {
        let name = try Catalog.safeName(p.name)
        _ = try SVGProfile.load(url: p.svg)   // validate before storing
        let dir = userRoot.appendingPathComponent("profiles")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let svgDest = dir.appendingPathComponent("\(name).svg")
        try? FileManager.default.removeItem(at: svgDest)
        try FileManager.default.copyItem(at: p.svg, to: svgDest)
        var scad = "tol = \(p.tolerance);\nph = \(p.height);\n"
        if let c = p.connectorWidth { scad += "khcx = \(c);\n" }
        try scad.write(to: dir.appendingPathComponent("\(name).scad"), atomically: true, encoding: .utf8)
    }

    public func addSystem(_ s: CustomSystem) throws {
        let name = try Catalog.safeName(s.name)
        let dir = userRoot.appendingPathComponent("definitions")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let scad = """
        kl = \(s.keyLength);
        aspace = \(s.shoulder);
        pinspace = \(s.pinSpacing);
        hcut = \(s.deepestCut);
        cutspace = \(s.cutStep);
        cutangle = \(s.cutAngle);
        platspace = \(s.plateau);

        """ + (s.bladeHeight.map { "ph = \($0) + 2*tol;\n" } ?? "")
            + (s.bladeThickness.map { "blade_thickness = \($0);\n" } ?? "")
        try scad.write(to: dir.appendingPathComponent("\(name).scad"), atomically: true, encoding: .utf8)
    }

    public func remove(_ item: Item) {
        guard item.isCustom else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: item.url)
        try? fm.removeItem(at: item.url.deletingPathExtension().appendingPathExtension("svg"))
    }

    public func isSupported(_ def: Item) -> Bool {
        guard let t = try? String(contentsOf: def.url, encoding: .utf8) else { return false }
        return !t.contains("dimplecut")
    }
}

public enum GenError: LocalizedError {
    case msg(String)
    public var errorDescription: String? { if case .msg(let m) = self { return m }; return nil }
}

public struct KeyGenerator {
    let catalog: Catalog
    public init(catalog: Catalog) { self.catalog = catalog }

    public func generate(profile: Catalog.Item, definition: Catalog.Item, options o: KeyOptions) throws -> Solid {
        let read = { (u: URL) throws -> String in try String(contentsOf: u, encoding: .utf8) }
        let baseText = try read(catalog.root.appendingPathComponent("base-settings.scad"))
        let profText = try read(profile.url)
        let defText = try read(definition.url)
        if defText.contains("dimplecut") { throw GenError.msg("Diese Definition (Dimple-Schlüssel) wird noch nicht unterstützt.") }

        // Layering: base defaults < flags < profile < definition (all lazily evaluated)
        let env = ScadEnv()
        env.load(baseText)
        let hasProfKhc = ["khcx", "khcz", "khcxoff"].filter { profText.contains("\($0)=") || profText.contains("\($0) =") }
        _ = hasProfKhc
        env.set("thin_handle", o.thinHandle ? "true" : "false")
        env.set("match_handle", o.matchHandleConnector ? "true" : "false")
        env.set("bumpkey", o.mode == .bumpkey ? "true" : "false")
        env.set("blank", o.mode == .blank ? "true" : "false")
        env.load(profText)
        env.load(defText)
        if let t = o.tolerance { env.set("tol", String(t)) }

        func n(_ name: String, _ def: Double? = nil) throws -> Double {
            if let v = env.number(name) { return v }
            if let d = def { return d }
            throw GenError.msg("Parameter '\(name)' fehlt oder ist nicht berechenbar.")
        }
        let tol = try n("tol"), ph = try n("ph"), kl = try n("kl")
        let bump = o.mode == .bumpkey
        let csz = try n("csz")
        _ = csz

        // Combination
        var comb: [Double] = [], combTokens: [String] = []
        if bump { comb = Array(repeating: 0, count: 6); combTokens = comb.map { _ in "0" } }
        else if o.mode == .key {
            combTokens = o.combination.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard !combTokens.isEmpty else { throw GenError.msg("Bitte eine Kombination angeben, z. B. 1,2,3,4,5,6.") }
        }

        // Body
        let svgURL = profile.url.deletingPathExtension().appendingPathExtension("svg")
        let outline = try SVGProfile.load(url: svgURL).cleaned(minDist: 0.01).normalized(height: ph).simplified(tolerance: 0.01).cleaned(minDist: 0.05)
        var shaped = outline
        if let thickness = env.number("blade_thickness"), thickness > 0 {
            let b = outline.bounds
            let stretch = (thickness + 2 * tol) / (b.max.x - b.min.x)   // thinning removes tol on both sides
            shaped.points = outline.points.map { V2(b.min.x + ($0.x - b.min.x) * stretch, $0.y) }
        }
        let thinned = tol > 0 ? shaped.eroded(by: tol) : shaped
        let dbg = ProcessInfo.processInfo.environment["AK_DEBUG"] != nil
        if dbg { print("outline pts \(thinned.points.count) area \(signedArea(thinned.points)) bounds \(thinned.bounds)") }
        if dbg { let t0 = triangulate(outline.points); print("raw outline pts \(outline.points.count) area \(signedArea(outline.points)) tris \(t0.count)") }
        if dbg { let t = triangulate(thinned.points); var a = 0.0; for x in t { let p = thinned.points; a += ((p[x.1]-p[x.0]).x*(p[x.2]-p[x.0]).y - (p[x.1]-p[x.0]).y*(p[x.2]-p[x.0]).x)/2 }; print("tris \(t.count) of \(thinned.points.count-2), tri area \(a)") }
        var body = extrude(thinned, z0: -kl / 2, z1: kl / 2).transformed(Xf.translate(-tol, 0, 0))

        // Tip cuts (default implementation)
        func tipCut(_ gamma: Double, _ negrot: Bool, _ yfactor: Double) -> Solid {
            let bsx = 10.0, bs = 20.0
            let rsq = (2 * (bs / 2) * (bs / 2)).squareRoot()
            let hyp = (2 * rsq * rsq * (1 - cos(gamma * .pi / 180))).squareRoot()
            let alpha = 180 - 45 - 90 + gamma / 2
            let beta = 90 - alpha
            let a = hyp * sin(alpha * .pi / 180)
            let b = (negrot ? -1.0 : 1.0) * hyp * sin(beta * .pi / 180)
            let m = Xf.translate(-bsx / 4 + bsx / 2, -bs / 4 + bs / 2 * yfactor + b, -kl / 2 - bs + bs / 2 + a)
                * Xf.rotate(negrot ? 360 - gamma : gamma, 0, 0)
            return boxSolid(V3(bsx, bs, bs), center: true, m)
        }
        let cutangle = env.number("cutangle") ?? 90
        if dbg { print("extruded vol", body.volume) }
        body = body.subtracting(tipCut(40, false, 2.1))
        if dbg { print("after cut1", body.volume) }
        body = body.subtracting(tipCut(cutangle / 2, true, 0))

        // Combination cuts
        if o.mode != .blank {
            let cutspace = try n("cutspace"), pinspace = try n("pinspace"), hcut = try n("hcut")
            let platspace = try n("platspace", 0)
            let addaspace = bump ? (env.number("bump_addaspace") ?? 0) : 0
            let addplat = bump ? (env.number("bump_addplatspace") ?? 0) : 0
            let addcut = bump ? (env.number("bump_addcutdepth") ?? 0) : 0
            let oddCorr = env.number("odd_cutspace_corr") ?? 0

            func cut(num: Int, level: Double, aspace: Double, rot: Double, xcorr: Double) -> Solid {
                let cutdim = 10.0, d = cutdim / 2.0.squareRoot()
                let cutcorr = Int(level) % 2 > 0 ? oddCorr : 0
                let r1 = cutangle / 2, r2 = -r1
                func rd(_ x: Double) -> Double { x * .pi / 180 }
                let ycorrect = d * sin(rd(r2)) / cos(rd(r2 / 2)) * sin(rd(45 + r2 / 2))
                let zcorrect = d * sin(rd(-r2)) / cos(rd(-r2 / 2)) * sin(rd(45 - r2 / 2))
                let base = Xf.translate(0, addcut + hcut - (level * cutspace + cutcorr), 0)
                    * Xf.translate(0, 0, -(aspace + addaspace + Double(num) * pinspace))
                    * Xf.translate(0, -cutdim / 2 + tol, -cutdim / 2 + kl / 2)
                    * Xf.translate(xcorr, 0, 0) * Xf.rotate(0, rot, 0)
                    * Xf.translate(0, 0, platspace / 2)
                let size = V3(cutdim, cutdim, cutdim)
                let a = Xf.translate(0, ycorrect, zcorrect) * Xf.rotate(-r1, 0, 0)
                let b = Xf.translate(0, ycorrect, -zcorrect + cutdim) * Xf.translate(0, 0, -platspace - addplat) * Xf.rotate(r1, 0, 0)
                let pts = (cubePoints(size, center: true).map { apply(base * a, $0) }
                           + cubePoints(size, center: true).map { apply(base * b, $0) })
                return hullSolid(pts)
            }

            let aspace = env.number("aspace") ?? 0
            if defText.contains("rotval") {
                // Rotated cuts (Mul-T-Lock style): pairs of "level, letter"
                let re = try NSRegularExpression(pattern: "rotval\\s*==\\s*\"(\\w)\"\\s*\\)\\s*\\{\\s*keycombcut\\(i/2,\\s*keycomb\\[i\\],\\s*([^,]+),[^,]*,[^,]*,[^,]*,\\s*([^,]+),\\s*([^)]+)\\)")
                let stripped = Scad.stripComments(defText)
                var table: [String: (String, String, String)] = [:]
                for m in re.matches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) {
                    func g(_ k: Int) -> String { String(stripped[Range(m.range(at: k), in: stripped)!]).trimmingCharacters(in: .whitespaces) }
                    table[g(1)] = (g(2), g(3), g(4))
                }
                guard combTokens.count % 2 == 0, !combTokens.isEmpty else {
                    throw GenError.msg("Diese Definition erwartet Paare aus Tiefe und Drehung, z. B. 3,K,2,B,… (Buchstaben: \(table.keys.sorted().joined(separator: "/"))).")
                }
                let ev = { (e: String) -> Double? in env.evalNumber(e) }
                for k in stride(from: 0, to: combTokens.count, by: 2) {
                    guard let lvl = Double(combTokens[k]), let t = table[combTokens[k + 1]],
                          let asp = ev(t.0), let rot = ev(t.1), let xc = ev(t.2) else {
                        throw GenError.msg("Ungültige Kombination an Position \(k / 2 + 1).")
                    }
                    body = body.subtracting(cut(num: k / 2, level: lvl, aspace: asp, rot: rot, xcorr: xc))
                }
            } else {
                if o.mode == .key {
                    comb = try combTokens.map { guard let v = Double($0) else { throw GenError.msg("Ungültiger Wert '\($0)'.") }; return v }
                }
                for (i, lvl) in comb.enumerated() {
                    body = body.subtracting(cut(num: i, level: lvl, aspace: aspace, rot: 0, xcorr: 0))
                }
            }
        }

        if dbg { print("after cuts", body.volume) }
        // Handle
        let khcy = env.number("khcy") ?? ph + 1
        let khcx = try n("khcx"), khcz = try n("khcz"), khcxoff = try n("khcxoff")
        let khx = try n("khx"), khy = try n("khy"), khz = try n("khz")
        let khcyo = -(khcy - ph) / 2
        let khyo = khcyo - (khy - khcy) / 2
        let connector = boxSolid(V3(khcx, khcy, khcz), center: false, Xf.translate(khcxoff, khcyo, kl / 2))
        let handle = boxSolid(V3(khx, khy, khz), center: false, Xf.translate(khcxoff, khyo, kl / 2 + khcz))
        let result = body.union(connector.union(handle))

        // Final orientation, equal to OpenSCAD rotate([270,180,0])
        return result.transformed(Xf.rotate(270, 180, 0))
    }
}

public enum STL {
    public static func binary(_ solid: Solid) -> Data {
        let tris = solid.triangles
        var d = Data(count: 80)
        var count = UInt32(tris.count)
        d.append(Data(bytes: &count, count: 4))
        func put(_ f: Float) { var x = f; d.append(Data(bytes: &x, count: 4)) }
        for t in tris {
            var n = simd_cross(t.1 - t.0, t.2 - t.0)
            let l = simd_length(n); n = l > 0 ? n / l : n
            [n, t.0, t.1, t.2].forEach { put(Float($0.x)); put(Float($0.y)); put(Float($0.z)) }
            d.append(contentsOf: [0, 0])
        }
        return d
    }
}

public extension Catalog {
    /// Numeric system/profile parameters (as used by the generator) for display and illustrations.
    func parameters(profile: Item?, definition: Item?) -> [String: Double] {
        let env = ScadEnv()
        if let b = try? String(contentsOf: root.appendingPathComponent("base-settings.scad"), encoding: .utf8) { env.load(b) }
        env.set("thin_handle", "false"); env.set("match_handle", "false"); env.set("bumpkey", "false"); env.set("blank", "false")
        if let p = profile, let t = try? String(contentsOf: p.url, encoding: .utf8) { env.load(t) }
        if let d = definition, let t = try? String(contentsOf: d.url, encoding: .utf8) { env.load(t) }
        var out: [String: Double] = [:]
        for k in ["kl", "aspace", "pinspace", "hcut", "cutspace", "cutangle", "platspace", "ph", "tol"] {
            if let v = env.number(k) { out[k] = v }
        }
        return out
    }

    func usesRotatedCuts(_ def: Item) -> Bool {
        ((try? String(contentsOf: def.url, encoding: .utf8)) ?? "").contains("rotval")
    }

    func outlinePreview(_ profile: Item) -> [V2]? {
        let svg = profile.url.deletingPathExtension().appendingPathExtension("svg")
        guard let o = try? SVGProfile.load(url: svg).cleaned(minDist: 0.01).normalized(height: 1).simplified(tolerance: 0.004) else { return nil }
        return o.points
    }
}

public struct KeyTypeMatch: Identifiable {
    public let system: Catalog.Item
    public let profile: Catalog.Item?
    public var id: String { system.id }
}

public extension Catalog {
    /// Systems whose matching profile has another name (see data/profiles/README.md).
    private static let profileOfSystem = [
        "AB-E20": "AB-AB95", "AB-C83": "AB-AB1", "BK-PZ88": "BK-BK1", "CE-810": "CE-CE41",
        "BK-Serie-2000-6Stift": "BK-Serie-2000-Kaskade-Unbekannt",
    ]

    /// Finds key types by what is stamped on a key or cylinder, such as "A93" or "E20".
    /// Serial and key numbers are not in here: only the manufacturer can resolve those.
    func findKeyType(_ query: String) -> [KeyTypeMatch] {
        func plain(_ s: String) -> String { s.uppercased().filter { $0.isLetter || $0.isNumber } }
        let q = plain(query)
        guard q.count >= 2 else { return [] }
        return definitions.filter { isSupported($0) }.compactMap { system in
            let profileID = Catalog.profileOfSystem[system.id] ?? system.id
            let profile = profiles.first { $0.id == profileID }
            // Match at the start of a name part, so that "E20" does not find "Serie-2000".
            func matches(_ name: String) -> Bool {
                let parts = name.split(separator: "-").map { plain(String($0)) }
                return parts.indices.contains { parts[$0...].joined().hasPrefix(q) }
            }
            guard matches(system.id) || profile.map({ matches($0.id) }) == true else { return nil }
            return KeyTypeMatch(system: system, profile: profile)
        }
    }
}
