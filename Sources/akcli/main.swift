import Foundation
import AutoKeyCore

// usage: akcli <profile> <definition> <blank|bump|key> [combination] -o out.stl
let a = CommandLine.arguments
if a.count > 3, a[1] == "photocheck" { do { try photoCheck(a[2], outPrefix: a[3]) } catch { print(error) }; exit(0) }
if a.count > 2, a[1] == "flatcheck" { do { try flatCheck(a[2]) } catch { print(error) }; exit(0) }
if a.count > 1, a[1] == "measure" { do { try measureTest() } catch { print(error) }; exit(0) }
if a.count > 4, a[1] == "measurereal" { do { try measureRealPhoto(a[2], coinPixels: Double(a[3]) ?? 150, outPrefix: a[4]) } catch { print(error) }; exit(0) }
if a.count > 1, a[1] == "scancases" { do { try scanCases() } catch { print(error) }; exit(0) }
if a.count > 1, a[1] == "scan" { do { try scantest() } catch { print(error) }; exit(0) }
if a.count > 1, a[1] == "photo" { do { try phototest(a[2]) } catch { print(error) }; exit(0) }
if a.count > 1, a[1] == "selftest" { selftest(); selftest2(); exit(0) }
guard a.count >= 4, let cat = Catalog.locate() else { print("usage: akcli PROFILE DEFINITION blank|bump|key [COMB] [-o out.stl]"); exit(2) }
guard let p = cat.profiles.first(where: { $0.id == a[1] }), let d = cat.definitions.first(where: { $0.id == a[2] }) else { print("unknown profile/definition"); exit(2) }
var o = KeyOptions()
o.mode = a[3] == "bump" ? .bumpkey : (a[3] == "key" ? .key : .blank)
if o.mode == .key, a.count > 4 { o.combination = a[4] }
let t0 = Date()
do {
    let s = try KeyGenerator(catalog: cat).generate(profile: p, definition: d, options: o)
    let b = s.bounds
    print("polys \(s.polygons.count) volume \(String(format: "%.1f", s.volume)) mm3 bbox \(b.min) .. \(b.max) in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
    if let i = a.firstIndex(of: "-o"), i + 1 < a.count { try STL.binary(s).write(to: URL(fileURLWithPath: a[i + 1])) }
} catch { print("ERROR: \(error.localizedDescription)"); exit(1) }
