import SwiftUI
import SceneKit
import simd
import AutoKeyCore
import UniformTypeIdentifiers

// MARK: - Illustration helpers

struct OutlineShape: Shape {
    let pts: [V2]
    func path(in r: CGRect) -> Path {
        guard pts.count > 2 else { return Path(roundedRect: r.insetBy(dx: r.width * 0.3, dy: 0), cornerRadius: 4) }
        var lo = V2(repeating: .infinity), hi = V2(repeating: -.infinity)
        for p in pts { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        let s = min(r.width / (hi.x - lo.x), r.height / (hi.y - lo.y))
        let w = (hi.x - lo.x) * s, h = (hi.y - lo.y) * s
        let ox = r.midX - w / 2, oy = r.midY + h / 2
        var path = Path()
        for (i, p) in pts.enumerated() {
            let pt = CGPoint(x: ox + (p.x - lo.x) * s, y: oy - (p.y - lo.y) * s)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath(); return path
    }
}

func dimension(_ ctx: GraphicsContext, from a: CGPoint, to b: CGPoint, label: String, color: Color = .orange, textOffset: CGPoint = CGPoint(x: 0, y: -10)) {
    var p = Path(); p.move(to: a); p.addLine(to: b)
    ctx.stroke(p, with: .color(color), lineWidth: 1.5)
    let dx = b.x - a.x, dy = b.y - a.y, l = max(1, hypot(dx, dy))
    let n = CGPoint(x: -dy / l * 5, y: dx / l * 5)
    for q in [a, b] {
        var t = Path(); t.move(to: CGPoint(x: q.x - n.x, y: q.y - n.y)); t.addLine(to: CGPoint(x: q.x + n.x, y: q.y + n.y))
        ctx.stroke(t, with: .color(color), lineWidth: 1.5)
    }
    ctx.draw(Text(label).font(.caption2.bold()).foregroundColor(color),
             at: CGPoint(x: (a.x + b.x) / 2 + textOffset.x, y: (a.y + b.y) / 2 + textOffset.y))
}

struct CaptureIllustration: View {
    let outline: [V2]?
    var body: some View {
        HStack(spacing: 14) {
            Canvas { ctx, size in
                // phone
                let phone = CGRect(x: 14, y: size.height / 2 - 42, width: 34, height: 84)
                ctx.fill(Path(roundedRect: phone, cornerRadius: 6), with: .color(.gray.opacity(0.5)))
                ctx.fill(Path(ellipseIn: CGRect(x: phone.midX - 5, y: phone.minY + 8, width: 10, height: 10)), with: .color(.black))
                // sight line
                var line = Path(); line.move(to: CGPoint(x: phone.maxX, y: phone.minY + 13)); line.addLine(to: CGPoint(x: size.width - 40, y: size.height / 2))
                ctx.stroke(line, with: .color(.yellow), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                // key seen from the side with tip pointing at the phone
                let key = CGRect(x: size.width - 100, y: size.height / 2 - 14, width: 60, height: 28)
                ctx.fill(Path(roundedRect: key, cornerRadius: 3), with: .color(.orange))
                ctx.fill(Path(roundedRect: CGRect(x: key.maxX - 4, y: key.minY - 6, width: 22, height: 40), cornerRadius: 5), with: .color(.orange.opacity(0.7)))
                dimension(ctx, from: CGPoint(x: phone.maxX + 4, y: size.height - 20), to: CGPoint(x: key.minX, y: size.height - 20), label: "15–20 cm", textOffset: CGPoint(x: 0, y: -9))
            }
            .frame(width: 230, height: 120).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            card(good: true)
            card(good: false)
        }
    }
    func card(good: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(good ? Color.white : Color(white: 0.55))
                if !good {
                    Canvas { ctx, size in
                        for i in stride(from: -size.height, to: size.width, by: 14) {
                            var p = Path(); p.move(to: CGPoint(x: i, y: size.height)); p.addLine(to: CGPoint(x: i + size.height, y: 0))
                            ctx.stroke(p, with: .color(.black.opacity(0.18)), lineWidth: 5)
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 8))
                }
                OutlineShape(pts: outline ?? []).fill(good ? Color.black : Color(white: 0.3)).frame(width: 40, height: 70)
                    .shadow(color: .black.opacity(good ? 0 : 0.5), radius: good ? 0 : 6, x: 6, y: 6)
            }
            .frame(width: 100, height: 100)
            Label(good ? "Einfarbig, Schlüssel dunkel" : "Muster, Schatten", systemImage: good ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2).foregroundStyle(good ? .green : .red)
        }
    }
}

struct CaliperIllustration: View {
    let outline: [V2]?
    var body: some View {
        Canvas { ctx, size in
            let shape = CGRect(x: size.width / 2 - 25, y: 12, width: 50, height: size.height - 24)
            ctx.fill(OutlineShape(pts: outline ?? []).path(in: shape), with: .color(.orange.opacity(0.85)))
            dimension(ctx, from: CGPoint(x: shape.minX - 34, y: shape.minY), to: CGPoint(x: shape.minX - 34, y: shape.maxY), label: "Höhe", textOffset: CGPoint(x: -22, y: 0))
            var j1 = Path(); j1.move(to: CGPoint(x: shape.minX - 60, y: shape.minY)); j1.addLine(to: CGPoint(x: shape.maxX + 20, y: shape.minY))
            var j2 = Path(); j2.move(to: CGPoint(x: shape.minX - 60, y: shape.maxY)); j2.addLine(to: CGPoint(x: shape.maxX + 20, y: shape.maxY))
            ctx.stroke(j1, with: .color(.gray), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ctx.stroke(j2, with: .color(.gray), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .frame(width: 210, height: 170).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct KeySideIllustration: View {
    var kl: Double, aspace: Double, pinspace: Double, ph: Double, cutspace: Double
    var hcut: Double = 0
    var levels: [Int]
    var showDims = true
    var body: some View {
        Canvas { ctx, size in
            let handleW = 54.0, left = 14.0 + handleW
            let s = (size.width - left - 20) / max(kl, 1)
            let h = min(size.height * 0.42, ph * s * 1.4)
            let top = size.height * 0.34, bottom = top + h
            ctx.fill(Path(roundedRect: CGRect(x: 14, y: top - 14, width: handleW, height: h + 28), cornerRadius: 10), with: .color(.orange.opacity(0.6)))
            // blade with notches (depth exaggerated)
            var blade = Path(); blade.move(to: CGPoint(x: left, y: top)); blade.addLine(to: CGPoint(x: left, y: bottom))
            let tip = left + kl * s
            var pts: [(Double, Double)] = []   // x, notch depth
            for (i, lv) in levels.enumerated() {
                let cx = left + (aspace + Double(i) * pinspace) * s
                let depthMM = hcut > 0 ? max(0.3, hcut - Double(lv) * cutspace) : 2.0 - Double(lv) * cutspace
                pts.append((cx, min(h * 0.9, depthMM * s * 1.6)))
            }
            var cur = left
            for (cx, depth) in pts {
                let w = max(pinspace * s * 0.3, 4)
                let flank = min(depth * 0.6, max(0, pinspace * s / 2 - w))   // neighbouring cuts must not cross
                blade.addLine(to: CGPoint(x: cx - w - flank, y: bottom))
                blade.addLine(to: CGPoint(x: cx - w, y: bottom - depth))
                blade.addLine(to: CGPoint(x: cx + w, y: bottom - depth))
                blade.addLine(to: CGPoint(x: cx + w + flank, y: bottom))
                cur = cx
            }
            _ = cur
            blade.addLine(to: CGPoint(x: tip - 8, y: bottom)); blade.addLine(to: CGPoint(x: tip, y: bottom - h * 0.45))
            blade.addLine(to: CGPoint(x: tip, y: top)); blade.closeSubpath()
            ctx.fill(blade, with: .color(.orange)); ctx.stroke(blade, with: .color(.primary.opacity(0.6)), lineWidth: 1)
            guard showDims else { return }
            dimension(ctx, from: CGPoint(x: left, y: top - 22), to: CGPoint(x: tip, y: top - 22), label: String(format: "Länge %.1f mm", kl))
            if aspace > 0 {
                dimension(ctx, from: CGPoint(x: left, y: bottom + 22), to: CGPoint(x: left + aspace * s, y: bottom + 22), label: String(format: "Schulter %.2f", aspace), textOffset: CGPoint(x: 0, y: 10))
            }
            if pinspace > 0, levels.count > 1 {
                dimension(ctx, from: CGPoint(x: left + aspace * s, y: bottom + 48), to: CGPoint(x: left + (aspace + pinspace) * s, y: bottom + 48), label: String(format: "Abstand %.2f", pinspace), textOffset: CGPoint(x: 0, y: 10))
            }
            for (i, p) in pts.enumerated() {
                ctx.draw(Text("\(levels[i])").font(.caption.bold()), at: CGPoint(x: p.0, y: bottom - h * 0.5))
            }
        }
        .frame(height: 170).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PrintIllustration: View {
    var body: some View {
        Canvas { ctx, size in
            let bed = CGRect(x: 20, y: size.height - 34, width: size.width - 40, height: 8)
            ctx.fill(Path(bed), with: .color(.gray))
            ctx.draw(Text("Druckbett").font(.caption2), at: CGPoint(x: bed.midX, y: bed.maxY + 10))
            // key lying on its broad side
            let blade = CGRect(x: 60, y: bed.minY - 12, width: 150, height: 12)
            ctx.fill(Path(roundedRect: blade, cornerRadius: 2), with: .color(.orange))
            ctx.fill(Path(roundedRect: CGRect(x: 30, y: bed.minY - 26, width: 34, height: 26), cornerRadius: 4), with: .color(.orange.opacity(0.7)))
            var a = Path(); a.move(to: CGPoint(x: 135, y: 20)); a.addLine(to: CGPoint(x: 135, y: blade.minY - 8))
            ctx.stroke(a, with: .color(.green), lineWidth: 2)
            ctx.draw(Text("Schichtlinien längs zum Blatt").font(.caption2).foregroundColor(.green), at: CGPoint(x: 135, y: 12))
            for i in 0..<3 {
                var l = Path(); l.move(to: CGPoint(x: 62, y: blade.minY + 3 + Double(i) * 4)); l.addLine(to: CGPoint(x: 208, y: blade.minY + 3 + Double(i) * 4))
                ctx.stroke(l, with: .color(.black.opacity(0.25)), lineWidth: 0.7)
            }
        }
        .frame(width: 260, height: 100).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Wizard

enum WizardStep: Int, CaseIterable {
    case start, photo, profile, system, combination, preview, print
    var title: String {
        ["Start", "Foto", "Profil messen", "Schlüsselmaße", "Kombination", "Vorschau", "Drucken"][rawValue]
    }
}

struct WizardView: View {
    @ObservedObject var m: Model
    @State var step: WizardStep = .start
    // photo
    @State var photo: PhotoTrace?
    @State var threshold = 128.0
    @State var keyIsDark = true
    @State var previewImage: NSImage?
    @State var traced: Outline?
    @State var useExisting = false
    @State var flatPhoto = false
    @State var autoDetect = true
    @State var subject: [Bool]?
    // profile
    @State var pName = ""
    @State var pHeight = ""
    @State var pTol = "0"
    @State var profileSaved = false
    // system
    @State var customSystem = false
    @State var sName = ""
    @State var sKL = "27"
    @State var sAsp = "4.6"
    @State var sPin = "3.1"
    @State var sHcut = "2"
    @State var sStep = "0.5"
    @State var sAngle = "90"
    @State var sPlat = "0.2"
    @State var sHeight = ""
    // combination
    @State var pins = 6
    @State var levels: [Int] = Array(repeating: 0, count: 6)
    @State var msg = ""
    @State var showScan = false
    @State var showMeasure = false

    func d(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
    var profileItem: Catalog.Item? { m.profiles.first { $0.id == m.profileID } }
    var definitionItem: Catalog.Item? { m.definitions.first { $0.id == m.definitionID } }
    var outline: [V2]? { profileItem.flatMap { m.catalog?.outlinePreview($0) } }
    var params: [String: Double] { m.catalog?.parameters(profile: profileItem, definition: definitionItem) ?? [:] }

    var body: some View {
        VStack(spacing: 0) {
            progress
            Divider()
            ScrollView { VStack(alignment: .leading, spacing: 14) { content }.padding(24).frame(maxWidth: .infinity, alignment: .leading) }
            Divider()
            HStack {
                Text(msg).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Zurück") { go(-1) }.disabled(step == .start)
                Button(step == .print ? "Neuer Schlüssel" : "Weiter") { step == .print ? restart() : go(1) }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.padding(12)
        }
        .sheet(isPresented: $showScan) { scanSheet }
    }

    var scanSheet: some View {
        KeyScanView(params: params, pins: pins) { lv in
            pins = lv.count; levels = lv; showScan = false
        } onClose: { showScan = false }
    }

    var progress: some View {
        HStack(spacing: 6) {
            ForEach(WizardStep.allCases, id: \.rawValue) { s in
                HStack(spacing: 5) {
                    Image(systemName: s.rawValue < step.rawValue ? "checkmark.circle.fill" : (s == step ? "\(s.rawValue + 1).circle.fill" : "\(s.rawValue + 1).circle"))
                    Text(s.title).font(.caption).fontWeight(s == step ? .bold : .regular)
                }
                .foregroundStyle(s == step ? Color.accentColor : .secondary)
                if s != .print { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
            }
        }.padding(10).frame(maxWidth: .infinity)
    }

    func go(_ delta: Int) {
        msg = ""
        if delta > 0 && !validate() { return }
        step = WizardStep(rawValue: max(0, min(WizardStep.allCases.count - 1, step.rawValue + delta))) ?? step
        if step == .preview { applyCombination(); m.generate() }
    }

    func restart() { step = .start; photo = nil; previewImage = nil; traced = nil; profileSaved = false; m.keyName = ""; m.solid = nil }

    func validate() -> Bool {
        switch step {
        case .photo:
            if !useExisting && traced == nil { msg = "Bitte ein Foto laden und die Kontur prüfen – oder 'Vorhandenes Profil' wählen."; return false }
        case .profile:
            if !useExisting && !profileSaved { if !saveProfile() { return false } }
        case .system:
            if customSystem && !saveSystem() { return false }
        case .combination:
            if m.options.mode == .key, let def = definitionItem, m.catalog?.usesRotatedCuts(def) == true,
               m.options.combination.trimmingCharacters(in: .whitespaces).isEmpty { msg = "Bitte die Kombination eintragen."; return false }
        default: break
        }
        return true
    }

    func saveProfile() -> Bool {
        guard let o = traced, let h = d(pHeight), h > 1, let t = d(pTol) else { msg = "Bitte Profilhöhe (mm) und Toleranz eintragen."; return false }
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).svg")
            try PhotoTrace.svg(o).write(to: tmp, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let name = pName.isEmpty ? "Mein-Profil" : pName
            try m.catalog?.addProfile(.init(name: name, svg: tmp, height: h, tolerance: t))
            m.reloadCatalog(); m.profileID = try Catalog.safeName(name); profileSaved = true; return true
        } catch { msg = error.localizedDescription; return false }
    }

    func saveSystem() -> Bool {
        guard let kl = d(sKL) else { msg = "Schlüssellänge fehlt."; return false }
        var s = Catalog.CustomSystem(name: sName.isEmpty ? "Mein-System" : sName, keyLength: kl)
        s.shoulder = d(sAsp) ?? 0; s.pinSpacing = d(sPin) ?? 0; s.deepestCut = d(sHcut) ?? 0
        s.cutStep = d(sStep) ?? 0; s.cutAngle = d(sAngle) ?? 90; s.plateau = d(sPlat) ?? 0; s.bladeHeight = d(sHeight)
        do { try m.catalog?.addSystem(s); m.reloadCatalog(); m.definitionID = try Catalog.safeName(s.name); customSystem = false; return true }
        catch { msg = error.localizedDescription; return false }
    }

    func applyMeasurement(_ r: KeyMeasurement) {
        customSystem = true
        func text(_ v: Double) -> String { String(format: "%.2f", v) }
        sKL = text(r.keyLength); sHeight = text(r.profileHeight); sAsp = text(r.shoulder); sPin = text(r.pinSpacing); sHcut = text(r.deepestCut)
        sStep = text(r.cutStep); sAngle = String(format: "%.0f", r.cutAngle); sPlat = text(r.plateau)
        if sName.isEmpty { sName = "Mein-Schluessel" }
        pins = r.levels.count; levels = r.levels
        m.options.mode = .key
        msg = "Maße übernommen."
    }

    func applyCombination() {
        if let def = definitionItem, m.catalog?.usesRotatedCuts(def) == true { return }
        if m.options.mode == .key { m.options.combination = levels.map(String.init).joined(separator: ",") }
    }

    func retrace() {
        guard let t = photo else { return }
        let auto = autoDetect ? subject.map { t.keyShape(in: $0) } : nil
        let mask = auto ?? t.mask(threshold: Int(threshold), keyIsDark: keyIsDark)
        traced = try? t.outline(mask: mask)
        if let cg = t.preview(mask: mask, outline: traced) { previewImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
        msg = traced == nil ? (PhotoTrace.TraceError.noShape.errorDescription ?? "") : ""
        flatPhoto = (try? KeyScan(trace: t, mask: mask))?.looksLikeFlatKey ?? false
    }

    func loadPhoto(_ u: URL) {
        do { let t = try PhotoTrace(url: u); photo = t; threshold = Double(t.otsuThreshold()); keyIsDark = t.suggestedKeyIsDark(threshold: Int(threshold))
             subject = t.subjectMask()
             if pName.isEmpty { pName = u.deletingPathExtension().lastPathComponent.replacingOccurrences(of: " ", with: "-") }
             profileSaved = false; retrace() }
        catch { msg = error.localizedDescription }
    }

    // MARK: step content

    @ViewBuilder var content: some View {
        switch step {
        case .start: startView
        case .photo: photoView
        case .profile: profileView
        case .system: systemView
        case .combination: combinationView
        case .preview: previewView
        case .print: printView
        }
    }

    func heading(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(t).font(.title2.bold()); Text(sub).foregroundStyle(.secondary) }
    }

    var startView: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Schlüssel nachdrucken", "Der Assistent führt dich in sieben Schritten von deinem echten Schlüssel zur druckfertigen STL-Datei.")
            Label("1  Foto der Schlüsselspitze → Profil", systemImage: "camera")
            Label("2  Profilhöhe mit dem Messschieber messen", systemImage: "ruler")
            Label("3  Länge, Schulter und Stiftabstand", systemImage: "arrow.left.and.right")
            Label("4  Schnitttiefen pro Stift", systemImage: "chart.bar")
            Label("5–7  Vorschau, STL-Export, Druckhinweise", systemImage: "cube")
            Text("Nur für eigene Schlüssel verwenden, die du nachbauen darfst. Die Software steht unter CC BY-NC-SA 4.0 (nicht kommerziell).")
                .font(.caption).foregroundStyle(.secondary)
            if !m.savedKeys.isEmpty {
                Divider()
                Text("Gespeicherte Schlüssel").font(.headline)
                ForEach(m.savedKeys) { k in
                    HStack {
                        Button { m.load(k); useExisting = true; step = .preview } label: { Label(k.name, systemImage: "key") }
                        Spacer()
                        Text("\(k.profile) · \(k.combination)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    var photoView: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Foto der Schlüsselspitze", "Die Kontur der Stirnseite wird zum Profil deines Schlüssels.")
            Picker("", selection: $useExisting) {
                Text("Foto vom iPhone").tag(false); Text("Vorhandenes Profil wählen").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 380)
            if useExisting {
                Picker("Profil", selection: $m.profileID) { ForEach(m.profiles) { Text($0.id).tag($0.id) } }.frame(maxWidth: 320)
                CaliperIllustration(outline: outline)
            } else {
                CaptureIllustration(outline: outline)
                VStack(alignment: .leading, spacing: 3) {
                    Text("1. Schlüssel aufrecht hinstellen, Spitze zur Kamera – oder in Knetmasse stecken.")
                    Text("2. Ein einfarbiges Blatt Papier dahinter, gleichmäßiges Licht, keine Schatten.")
                    Text("3. iPhone genau senkrecht von vorn halten. Über „Vom iPhone aufnehmen …“ direkt fotografieren, per AirDrop an den Mac senden oder hier hineinziehen.")
                }.font(.callout)
                HStack {
                    Button("Foto wählen …") {
                        let p = NSOpenPanel(); p.allowedContentTypes = [.image]
                        if p.runModal() == .OK, let u = p.url { loadPhoto(u) }
                    }
                    ContinuityImportButton { loadPhoto($0) }.fixedSize()
                    if subject != nil { Toggle("Automatisch erkennen", isOn: $autoDetect).onChange(of: autoDetect) { _ in retrace() } }
                }
                dropZone
                if photo != nil, !(autoDetect && subject != nil) {
                    Toggle("Schlüssel ist dunkel", isOn: $keyIsDark).onChange(of: keyIsDark) { _ in retrace() }
                    HStack { Text("Schwellwert"); Slider(value: $threshold, in: 1...254).onChange(of: threshold) { _ in retrace() } }.frame(maxWidth: 420)
                }
                if flatPhoto {
                    Label("Das sieht nach einem flach liegenden Schlüssel aus. Hier brauchst du ein Foto der Stirnseite (von vorn auf die Spitze), sonst wird das Profil falsch. Das flache Foto gehört in Schritt 5 zu „Schlüssel scannen“. Ohne Stirnseiten-Foto: oben „Vorhandenes Profil wählen“.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if let img = previewImage {
                    Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 280)
                    Text("Rot = erkannter Schlüssel, grün = Kontur. Bei Fehlern Schwellwert ändern oder 'dunkel' umschalten.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    var dropZone: some View {
        RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundStyle(.secondary)
            .frame(height: 60).overlay(Label("Bild hierher ziehen (JPG, PNG, HEIC)", systemImage: "square.and.arrow.down").foregroundStyle(.secondary))
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                providers.first?.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data, let u = URL(dataRepresentation: data, relativeTo: nil) { DispatchQueue.main.async { loadPhoto(u) } }
                }
                return true
            }
    }

    var profileView: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Profilhöhe messen", "Damit die Kontur den richtigen Maßstab bekommt.")
            HStack(alignment: .top, spacing: 20) {
                if useExisting {
                    CaliperIllustration(outline: outline)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Profil \(m.profileID)").font(.headline)
                        if let ph = params["ph"], let tol = params["tol"] { Text(String(format: "Höhe %.2f mm, Toleranz %.2f mm (aus den Profildaten)", ph, tol)) }
                    }
                } else {
                    CaliperIllustration(outline: traced.map { $0.normalized(height: 1).points })
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Miss mit dem Messschieber die Höhe des Schlüsselprofils (an der breitesten Stelle quer zum Schlüssel, in Millimetern).")
                        TextField("Höhe in mm, z. B. 8.75", text: $pHeight).frame(maxWidth: 200)
                        Text("Toleranz: Material, das rundum abgezogen wird. 0.2 passt für Konturen aus einem Schlossfoto (Schlüsselkanal), 0 für den Schlüssel selbst.")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("Toleranz in mm", text: $pTol).frame(maxWidth: 200)
                        TextField("Profilname", text: $pName).frame(maxWidth: 200)
                    }
                }
            }
        }.textFieldStyle(.roundedBorder)
    }

    var systemView: some View {
        let p = params
        return VStack(alignment: .leading, spacing: 14) {
            heading("Schlüsselmaße", "Länge, Schulter und Stiftabstand bestimmen, wo die Schnitte sitzen.")
            Button { showMeasure = true } label: { Label("Maße aus Foto messen (Schlüssel mit Münze) …", systemImage: "camera.metering.center.weighted") }
                .sheet(isPresented: $showMeasure) {
                    KeyMeasureView { result in applyMeasurement(result); showMeasure = false } onClose: { showMeasure = false }
                }
            Picker("", selection: $customSystem) { Text("Vorhandenes System").tag(false); Text("Eigene Maße").tag(true) }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 380)
            if customSystem {
                KeySideIllustration(kl: d(sKL) ?? 27, aspace: d(sAsp) ?? 0, pinspace: d(sPin) ?? 0, ph: params["ph"] ?? 8.75, cutspace: d(sStep) ?? 0.5, hcut: d(sHcut) ?? 0, levels: levels)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow { Text("Länge (Schulter bis Spitze)"); TextField("27", text: $sKL) }
                    GridRow { Text("Schlüsselhöhe (quer übers Blatt)"); TextField("leer = wie Profil", text: $sHeight) }
                    GridRow { Text("Schulter → erster Stift"); TextField("4.6", text: $sAsp) }
                    GridRow { Text("Abstand zwischen Stiften"); TextField("3.1", text: $sPin) }
                    GridRow { Text("Tiefster/erster Schnitt (hcut)"); TextField("2", text: $sHcut) }
                    GridRow { Text("Stufe zwischen Schnitttiefen"); TextField("0.5", text: $sStep) }
                    GridRow { Text("Schnittwinkel (°)"); TextField("90", text: $sAngle) }
                    GridRow { Text("Plateau zwischen Flanken"); TextField("0.2", text: $sPlat) }
                    GridRow { Text("Name"); TextField("Mein-System", text: $sName) }
                }.frame(maxWidth: 440)
                Text("Alle Maße in Millimetern, mit dem Messschieber vom Schlüssel abnehmen.").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("System", selection: $m.definitionID) { ForEach(m.definitions) { Text($0.id).tag($0.id) } }.frame(maxWidth: 320)
                KeySideIllustration(kl: p["kl"] ?? 27, aspace: p["aspace"] ?? 0, pinspace: p["pinspace"] ?? 0, ph: p["ph"] ?? 8.75, cutspace: p["cutspace"] ?? 0.5, hcut: p["hcut"] ?? 0, levels: Array(repeating: 0, count: 6))
                Text("Passt das System nicht zu deinem Schlüssel, wähle oben 'Eigene Maße'.").font(.caption).foregroundStyle(.secondary)
            }
        }.textFieldStyle(.roundedBorder)
    }

    var combinationView: some View {
        let p = params
        let rotated = definitionItem.flatMap { m.catalog?.usesRotatedCuts($0) } ?? false
        return VStack(alignment: .leading, spacing: 14) {
            heading("Kombination", "Welche Art von Schlüssel soll entstehen?")
            Picker("", selection: $m.options.mode) { ForEach(KeyMode.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 380)
            switch m.options.mode {
            case .blank: Text("Rohling: Profil und Länge ohne Schnitte – zum Selbstfeilen oder Prüfen.").foregroundStyle(.secondary)
            case .bumpkey: Text("Bump-Key: sechs maximale Schnitte mit den Bump-Zusatzwerten des Systems.").foregroundStyle(.secondary)
            case .key:
                if rotated {
                    Text("Dieses System braucht Paare aus Tiefe und Drehbuchstabe, z. B. 1,K,2,B,3,Q:").font(.callout)
                    TextField("1,K,2,B,3,Q", text: $m.options.combination).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                } else {
                    Stepper("Anzahl Stifte: \(pins)", value: $pins, in: 1...10).frame(maxWidth: 240)
                        .onChange(of: pins) { n in levels = Array((levels + Array(repeating: 0, count: 10)).prefix(n)) }
                    KeySideIllustration(kl: p["kl"] ?? 27, aspace: p["aspace"] ?? 0, pinspace: p["pinspace"] ?? 0, ph: p["ph"] ?? 8.75, cutspace: p["cutspace"] ?? 0.5, hcut: p["hcut"] ?? 0, levels: levels)
                    Button { showScan = true } label: { Label("Schlüssel scannen (Foto/Scan von oben) …", systemImage: "doc.viewfinder") }
                    Text("Stufe pro Stift, von der Schulter zur Spitze (Tiefe wird in der Skizze überhöht dargestellt):").font(.callout)
                    HStack(spacing: 10) {
                        ForEach(0..<pins, id: \.self) { i in
                            VStack(spacing: 2) {
                                Text("Stift \(i + 1)").font(.caption2)
                                Stepper(value: Binding(get: { levels[i] }, set: { levels[i] = $0 }), in: 0...9) { Text("\(levels[i])").font(.title3.monospacedDigit()) }
                            }
                        }
                    }
                    Text("Nummerierung wie im Originalwerkzeug: Stufe 0 ist der tiefste Schnitt, jede weitere Stufe ist um die 'Stufe zwischen Schnitttiefen' flacher. Bitte mit den Maßen deines Schlüssels vergleichen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    var previewView: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Vorschau", "Drehe das Modell mit der Maus und prüfe Länge, Schnitte und Griff.")
            ZStack { SceneContainer(scene: m.scene).clipShape(RoundedRectangle(cornerRadius: 10)); if m.busy { ProgressView() } }.frame(height: 340)
            Text(m.status).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Name zum Speichern", text: $m.keyName).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                Button("Schlüssel speichern") { m.saveCurrentKey() }
                Button("Neu berechnen") { applyCombination(); m.generate() }
            }
            HStack {
                Toggle("Dünner Griff", isOn: $m.options.thinHandle)
                Toggle("Griff = Verbinderdicke", isOn: $m.options.matchHandleConnector)
            }
        }
    }

    var printView: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Drucken", "STL exportieren und im Slicer öffnen.")
            Button { m.exportSTL() } label: { Label("STL exportieren …", systemImage: "square.and.arrow.up") }.controlSize(.large)
            PrintIllustration()
            VStack(alignment: .leading, spacing: 6) {
                Text("• Im Slicer so drehen, dass die breite Seite des Blatts flach auf dem Druckbett liegt.")
                Text("• Feine Schichthöhe (0.1–0.15 mm) und kleine Düse (0.4 mm oder kleiner), langsam drucken.")
                Text("• Erst einen Probedruck machen; bei Bedarf Toleranz im Profilschritt anpassen und neu exportieren.")
                Text("• Die Maße und Schnitte sind nur so genau wie deine Messung – nach dem Druck am Schloss prüfen.")
            }.font(.callout)
            Text("Hinweis: Das ist eine Neuimplementierung; die eingeprägte Beschriftung am Griff und Dimple-Systeme fehlen.").font(.caption).foregroundStyle(.secondary)
        }
    }
}


struct KeyScanView: View {
    let params: [String: Double]
    let pins: Int
    var onApply: ([Int]) -> Void
    var onClose: () -> Void

    @State var photo: PhotoTrace?
    @State var threshold = 128.0
    @State var keyIsDark = true
    @State var autoDetect = true
    @State var subject: [Bool]?
    @State var scan: KeyScan?
    @State var shoulder = 0.0
    @State var pinCount = 6
    @State var result: KeyScan.Result?
    @State var image: NSImage?
    @State var msg = ""

    func load(_ u: URL) {
        do { let t = try PhotoTrace(url: u, maxDimension: KeyScan.scanDimension); photo = t; threshold = Double(t.otsuThreshold()); keyIsDark = t.suggestedKeyIsDark(threshold: Int(threshold)); subject = t.subjectMask(); rescan(resetShoulder: true) }
        catch { msg = error.localizedDescription }
    }

    func rescan(resetShoulder: Bool = false) {
        guard let t = photo else { return }
        do {
            let auto = autoDetect ? subject.map { t.keyShape(in: $0, bridgeGaps: false) } : nil
            let s = try auto.map { try KeyScan(trace: t, mask: $0) } ?? KeyScan(trace: t, threshold: Int(threshold), keyIsDark: keyIsDark)
            scan = s
            if resetShoulder { shoulder = s.detectedShoulder }
            analyze()
        } catch { scan = nil; result = nil; image = nil; msg = error.localizedDescription }
    }

    func analyze() {
        guard let s = scan else { return }
        do {
            let r = try s.analyze(kl: params["kl"] ?? 27, aspace: params["aspace"] ?? 0, pinspace: params["pinspace"] ?? 3,
                                  pins: pinCount, hcut: params["hcut"] ?? 3, cutspace: params["cutspace"] ?? 0.5, shoulderBin: shoulder)
            result = r; msg = ""
            if let cg = s.preview(r) { image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
        } catch { result = nil; msg = error.localizedDescription }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Schlüssel scannen").font(.title2.bold())
                Text("Lege den Schlüssel flach auf einfarbiges Papier (oder in einen Flachbettscanner), die gezahnte Kante frei. Fotografiere genau von oben, der ganze Schlüssel muss im Bild sein. Mit dem iPhone: „Vom iPhone aufnehmen …“ und dort „Dokumente scannen“ wählen, oder einen Scan aus der Notizen-App per AirDrop senden. Die Länge von Schulter bis Spitze wird mit der Länge des gewählten Systems (\(String(format: "%.1f", params["kl"] ?? 27)) mm) skaliert.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Foto/Scan wählen …") {
                        let p = NSOpenPanel(); p.allowedContentTypes = [.image]
                        if p.runModal() == .OK, let u = p.url { load(u) }
                    }
                    ContinuityImportButton { load($0) }.fixedSize()
                    if subject != nil { Toggle("Automatisch erkennen", isOn: $autoDetect).onChange(of: autoDetect) { _ in rescan(resetShoulder: true) } }
                    Stepper("Stifte: \(pinCount)", value: $pinCount, in: 1...10).onChange(of: pinCount) { _ in analyze() }.frame(width: 140)
                }
                if photo != nil {
                    if !(autoDetect && subject != nil) {
                        Toggle("Schlüssel ist dunkel", isOn: $keyIsDark).onChange(of: keyIsDark) { _ in rescan(resetShoulder: true) }
                        HStack { Text("Schwellwert"); Slider(value: $threshold, in: 1...254).onChange(of: threshold) { _ in rescan(resetShoulder: true) } }
                    }
                    if let s = scan {
                        HStack { Text("Schulter"); Slider(value: $shoulder, in: 0...Double(max(1, s.bins - 40))).onChange(of: shoulder) { _ in analyze() } }
                    }
                }
                if let img = image { Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 300) }
                if let r = result {
                    Text("Blau = Schulter, grün = Stiftpositionen. Stimmen die grünen Linien nicht mit den Zähnen überein, Schulter verschieben.").font(.caption).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                        GridRow { Text("Stift").bold(); Text("Tiefe (mm)").bold(); Text("Stufe").bold(); Text("Sicherheit").bold() }
                        ForEach(0..<r.levels.count, id: \.self) { i in
                            GridRow {
                                Text("\(i + 1)"); Text(String(format: "%.2f", r.depthsMM[i])); Text("\(r.levels[i])")
                                Text(r.residuals[i] < 0.25 ? "gut" : (r.residuals[i] < 0.4 ? "mittel" : "unsicher"))
                                    .foregroundStyle(r.residuals[i] < 0.25 ? .green : (r.residuals[i] < 0.4 ? .orange : .red))
                            }
                        }
                    }
                    Text(String(format: "Maßstab: %.3f mm pro Pixel. Prüfe die Werte mit dem Messschieber, bevor du druckst.", r.mmPerPixel)).font(.caption).foregroundStyle(.secondary)
                }
                Text(msg).font(.caption).foregroundStyle(.red)
                HStack {
                    Spacer()
                    Button("Abbrechen") { onClose() }
                    Button("Übernehmen") { if let r = result { onApply(r.levels) } }.disabled(result == nil).keyboardShortcut(.defaultAction)
                }
            }.padding(20)
        }.frame(width: 640, height: 640).onAppear { pinCount = pins }
    }
}
