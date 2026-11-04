import SwiftUI
import SceneKit
import AutoKeyCore
import UniformTypeIdentifiers

@main
struct AutoKey3DApp: App {
    var body: some Scene {
        WindowGroup("AutoKey3D") { RootView().frame(minWidth: 900, minHeight: 700) }
    }
}

@MainActor
final class Model: ObservableObject {
    @Published var catalog: Catalog? = Catalog.locate()
    @Published var savedKeys: [SavedKey] = SavedKeyStore.load()
    @Published var keyName = ""
    @Published var profileID = "AB-AB95"
    @Published var definitionID = "AB-E20"
    @Published var options = KeyOptions()
    @Published var toleranceText = ""
    @Published var solid: Solid?
    @Published var scene = SCNScene()
    @Published var busy = false
    @Published var status = "Bereit."

    var profiles: [Catalog.Item] { catalog?.profiles ?? [] }
    var definitions: [Catalog.Item] { catalog?.definitions.filter { catalog!.isSupported($0) } ?? [] }

    func generate() {
        guard let catalog, let p = profiles.first(where: { $0.id == profileID }),
              let d = definitions.first(where: { $0.id == definitionID }) else { status = "Profil/Definition nicht gefunden."; return }
        var opts = options
        opts.tolerance = Double(toleranceText.replacingOccurrences(of: ",", with: "."))
        busy = true; status = "Berechne …"
        // BSP recursion can be deep: run on a thread with a large stack.
        let t = Thread { [weak self] in
            let result = Result { try KeyGenerator(catalog: catalog).generate(profile: p, definition: d, options: opts) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                switch result {
                case .success(let s):
                    self.solid = s
                    self.scene = Self.makeScene(s)
                    self.status = String(format: "%d Dreiecke, Volumen %.0f mm³", s.triangles.count, s.volume)
                case .failure(let e): self.status = "Fehler: \(e.localizedDescription)"
                }
            }
        }
        t.stackSize = 512 << 20
        t.start()
    }

    func reloadCatalog() { if let c = catalog { catalog = Catalog(root: c.root) } }

    func saveCurrentKey() {
        let n = keyName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { status = "Bitte einen Namen für den Schlüssel eingeben."; return }
        let k = SavedKey(name: n, profile: profileID, definition: definitionID, mode: options.mode.rawValue,
                         combination: options.combination, tolerance: toleranceText,
                         thinHandle: options.thinHandle, matchHandle: options.matchHandleConnector)
        savedKeys.removeAll { $0.name == n }
        savedKeys.append(k); SavedKeyStore.save(savedKeys); status = "Gespeichert: \(n)"
    }

    func load(_ k: SavedKey) {
        profileID = k.profile; definitionID = k.definition
        options.mode = KeyMode(rawValue: k.mode) ?? .key
        options.combination = k.combination; toleranceText = k.tolerance
        options.thinHandle = k.thinHandle; options.matchHandleConnector = k.matchHandle
        keyName = k.name; generate()
    }

    func delete(_ k: SavedKey) { savedKeys.removeAll { $0.id == k.id }; SavedKeyStore.save(savedKeys) }

    func exportSTL() {
        guard let solid else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "stl") ?? .data]
        panel.nameFieldStringValue = "\(profileID)_\(definitionID)_\(options.mode.rawValue).stl"
        if panel.runModal() == .OK, let url = panel.url {
            do { try STL.binary(solid).write(to: url); status = "Exportiert: \(url.lastPathComponent)" }
            catch { status = "Export fehlgeschlagen: \(error.localizedDescription)" }
        }
    }

    static func makeScene(_ solid: Solid) -> SCNScene {
        let tris = solid.triangles
        var verts: [SCNVector3] = [], normals: [SCNVector3] = [], idx: [Int32] = []
        for (n, t) in tris.enumerated() {
            var nrm = simd_cross(t.1 - t.0, t.2 - t.0)
            let l = simd_length(nrm); nrm = l > 0 ? nrm / l : nrm
            for v in [t.0, t.1, t.2] {
                verts.append(SCNVector3(v.x, v.y, v.z)); normals.append(SCNVector3(nrm.x, nrm.y, nrm.z))
            }
            idx += [Int32(n * 3), Int32(n * 3 + 1), Int32(n * 3 + 2)]
        }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals)],
                              elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(calibratedRed: 0.86, green: 0.72, blue: 0.36, alpha: 1)
        mat.metalness.contents = 0.6; mat.roughness.contents = 0.35
        mat.lightingModel = .physicallyBased
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)
        let b = solid.bounds
        let c = (b.min + b.max) / 2
        node.pivot = SCNMatrix4MakeTranslation(CGFloat(c.x), CGFloat(c.y), CGFloat(c.z))
        let scene = SCNScene()
        scene.rootNode.addChildNode(node)
        let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera!.zFar = 1000
        cam.position = SCNVector3(0, 0, 130)
        scene.rootNode.addChildNode(cam)
        node.eulerAngles = SCNVector3(0.4, -0.7, 0)
        return scene
    }
}

struct SceneContainer: NSViewRepresentable {
    let scene: SCNScene
    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        v.allowsCameraControl = true; v.autoenablesDefaultLighting = true
        v.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1)
        v.antialiasingMode = .multisampling4X
        return v
    }
    func updateNSView(_ v: SCNView, context: Context) { v.scene = scene }
}

struct RootView: View {
    @StateObject var m = Model()
    @State var expert = false
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $expert) { Text("Assistent").tag(false); Text("Experte").tag(true) }
                .pickerStyle(.segmented).labelsHidden().frame(width: 240).padding(8)
            Divider()
            if expert { ContentView(m: m) } else { WizardView(m: m) }
        }
    }
}

struct ContentView: View {
    @ObservedObject var m: Model
    @State var showCustom = false

    var body: some View {
        HStack(spacing: 0) {
            Form {
                if m.catalog == nil {
                    Text("Datenordner (profiles/definitions) nicht gefunden.").foregroundStyle(.red)
                }
                Picker("Profil", selection: $m.profileID) { ForEach(m.profiles) { Text($0.id).tag($0.id) } }
                Picker("System", selection: $m.definitionID) { ForEach(m.definitions) { Text($0.id).tag($0.id) } }
                Picker("Typ", selection: $m.options.mode) { ForEach(KeyMode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                if m.options.mode == .key {
                    TextField("Kombination", text: $m.options.combination, prompt: Text("1,2,3,4,5,6"))
                }
                TextField("Toleranz (mm, optional)", text: $m.toleranceText)
                Toggle("Dünner Griff", isOn: $m.options.thinHandle)
                Toggle("Griff = Verbinderdicke", isOn: $m.options.matchHandleConnector)
                HStack {
                    Button("Erzeugen") { m.generate() }.keyboardShortcut(.return).disabled(m.busy)
                    Button("STL exportieren …") { m.exportSTL() }.disabled(m.solid == nil)
                }
                if m.busy { ProgressView() }
                Section("Meine Schlüssel") {
                    HStack {
                        TextField("Name", text: $m.keyName)
                        Button("Speichern") { m.saveCurrentKey() }
                    }
                    ForEach(m.savedKeys) { k in
                        HStack {
                            Button(k.name) { m.load(k) }.buttonStyle(.link)
                            Spacer()
                            Text("\(k.profile) · \(k.combination)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            Button { m.delete(k) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                    }
                    Button("Eigenes Profil / System …") { showCustom = true }
                }
                Text(m.status).font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped).frame(width: 300)
            SceneContainer(scene: m.scene)
        }
        .onAppear { if m.solid == nil { m.generate() } }
        .sheet(isPresented: $showCustom) { CustomDataView(m: m) }
    }
}


struct CustomDataView: View {
    @ObservedObject var m: Model
    @Environment(\.dismiss) var dismiss
    @State var pName = ""
    @State var pHeight = ""
    @State var pTol = "0"
    @State var pConn = ""
    @State var pFile: URL?
    @State var sName = ""
    @State var sKL = ""
    @State var sAsp = ""
    @State var sPin = ""
    @State var sHcut = ""
    @State var sStep = ""
    @State var sAngle = "90"
    @State var sPlat = "0"
    @State var msg = ""
    @State var photo: PhotoTrace?
    @State var photoName = ""
    @State var threshold = 128.0
    @State var keyIsDark = true
    @State var previewImage: NSImage?
    @State var tracedOutline: Outline?

    func retrace() {
        guard let t = photo else { return }
        let m = t.mask(threshold: Int(threshold), keyIsDark: keyIsDark)
        tracedOutline = try? t.outline(threshold: Int(threshold), keyIsDark: keyIsDark)
        if let cg = t.preview(mask: m, outline: tracedOutline) { previewImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
        if tracedOutline == nil { msg = PhotoTrace.TraceError.noShape.errorDescription ?? "" }
    }

    func d(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 12) {
            Text("Profil aus iPhone-Foto").font(.headline)
            Text("Fotografiere die Stirnseite des Schlüssels (Spitze, von vorn) auf einfarbigem, kontrastreichem Untergrund und bringe das Bild per AirDrop oder Drag & Drop auf den Mac. Die Kontur wird erkannt; danach Höhe des Profils in mm eingeben (Messschieber).")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Foto wählen …") {
                    let p = NSOpenPanel(); p.allowedContentTypes = [.image]
                    if p.runModal() == .OK, let u = p.url {
                        do { let t = try PhotoTrace(url: u); photo = t; photoName = u.deletingPathExtension().lastPathComponent
                             threshold = Double(t.otsuThreshold()); keyIsDark = t.suggestedKeyIsDark(threshold: Int(threshold)); if pName.isEmpty { pName = photoName }; msg = ""; retrace() }
                        catch { msg = error.localizedDescription }
                    }
                }
                Toggle("Schlüssel ist dunkel", isOn: $keyIsDark).onChange(of: keyIsDark) { _ in retrace() }
            }
            if photo != nil {
                HStack { Text("Schwellwert"); Slider(value: $threshold, in: 1...254).onChange(of: threshold) { _ in retrace() } }
                if let img = previewImage { Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 260) }
                HStack {
                    TextField("Name", text: $pName); TextField("Höhe (mm)", text: $pHeight); TextField("Toleranz", text: $pTol)
                    Button("Foto-Profil speichern") {
                        guard let o = tracedOutline, let h = d(pHeight), let t = d(pTol) else { msg = "Kontur, Höhe und Toleranz nötig."; return }
                        do {
                            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).svg")
                            try PhotoTrace.svg(o).write(to: tmp, atomically: true, encoding: .utf8)
                            defer { try? FileManager.default.removeItem(at: tmp) }
                            try m.catalog?.addProfile(.init(name: pName, svg: tmp, height: h, tolerance: t, connectorWidth: nil))
                            m.reloadCatalog(); m.profileID = (try? Catalog.safeName(pName)) ?? m.profileID; msg = "Profil aus Foto gespeichert."
                        } catch { msg = error.localizedDescription }
                    }
                }
            }
            Divider()
            Text("Eigenes Profil importieren").font(.headline)
            Text("SVG-Kontur des Schlüsselprofils (Schwarz auf Weiß, z. B. aus einem Foto oder Scan nachgezeichnet). Höhe = Profilhöhe am Schloss in mm.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("SVG wählen …") {
                    let p = NSOpenPanel(); p.allowedContentTypes = [.svg]
                    if p.runModal() == .OK { pFile = p.url; if pName.isEmpty { pName = p.url!.deletingPathExtension().lastPathComponent } }
                }
                Text(pFile?.lastPathComponent ?? "keine Datei").foregroundStyle(.secondary)
            }
            HStack {
                TextField("Name", text: $pName); TextField("Höhe (mm)", text: $pHeight)
                TextField("Toleranz", text: $pTol); TextField("Verbinderbreite (opt.)", text: $pConn)
            }
            Button("Profil speichern") {
                guard let f = pFile, let h = d(pHeight), let t = d(pTol) else { msg = "Datei, Höhe und Toleranz angeben."; return }
                do { try m.catalog?.addProfile(.init(name: pName, svg: f, height: h, tolerance: t, connectorWidth: d(pConn)))
                     m.reloadCatalog(); m.profileID = (try? Catalog.safeName(pName)) ?? m.profileID; msg = "Profil gespeichert." }
                catch { msg = error.localizedDescription }
            }
            Divider()
            Text("Eigenes Schlosssystem anlegen").font(.headline)
            Text("Maße deines Schlüssels in mm. Tiefster Schnitt (hcut) wird von der Schnittseite gemessen.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { TextField("Name", text: $sName); TextField("Länge kl", text: $sKL); TextField("Schulter aspace", text: $sAsp); TextField("Stiftabstand", text: $sPin) }
            HStack { TextField("hcut", text: $sHcut); TextField("Stufe cutspace", text: $sStep); TextField("Winkel", text: $sAngle); TextField("Plateau", text: $sPlat) }
            Button("System speichern") {
                guard let kl = d(sKL) else { msg = "Länge angeben."; return }
                var s = Catalog.CustomSystem(name: sName, keyLength: kl)
                s.shoulder = d(sAsp) ?? 0; s.pinSpacing = d(sPin) ?? 0; s.deepestCut = d(sHcut) ?? 0
                s.cutStep = d(sStep) ?? 0; s.cutAngle = d(sAngle) ?? 90; s.plateau = d(sPlat) ?? 0
                do { try m.catalog?.addSystem(s); m.reloadCatalog(); m.definitionID = (try? Catalog.safeName(sName)) ?? m.definitionID; msg = "System gespeichert." }
                catch { msg = error.localizedDescription }
            }
            let custom = (m.catalog?.profiles.filter(\.isCustom) ?? []) + (m.catalog?.definitions.filter(\.isCustom) ?? [])
            if !custom.isEmpty {
                Divider(); Text("Gespeichert").font(.headline)
                ForEach(custom) { it in
                    HStack { Text(it.id); Spacer(); Button("Löschen") { m.catalog?.remove(it); m.reloadCatalog() } }
                }
            }
            HStack { Text(msg).font(.caption); Spacer(); Button("Fertig") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .textFieldStyle(.roundedBorder).padding(20) }.frame(width: 640, height: 560)
    }
}
