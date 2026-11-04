import SwiftUI
import KeyDoublerCore

struct CoinIllustration: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let y = size.height / 2
            ctx.fill(Path(roundedRect: CGRect(x: 16, y: y - 26, width: 48, height: 52), cornerRadius: 6), with: .color(.gray))
            var blade = Path()
            blade.move(to: CGPoint(x: 64, y: y - 11))
            blade.addLine(to: CGPoint(x: 180, y: y - 11))
            blade.addLine(to: CGPoint(x: 188, y: y + 2))
            blade.addLine(to: CGPoint(x: 180, y: y + 11))
            for x in stride(from: 168.0, to: 76, by: -20) {
                blade.addLine(to: CGPoint(x: x + 6, y: y + 11)); blade.addLine(to: CGPoint(x: x, y: y + 3)); blade.addLine(to: CGPoint(x: x - 6, y: y + 11))
            }
            blade.addLine(to: CGPoint(x: 64, y: y + 11)); blade.closeSubpath()
            ctx.fill(blade, with: .color(.gray))
            let coin = CGRect(x: 212, y: y - 24, width: 48, height: 48)
            ctx.fill(Path(ellipseIn: coin), with: .color(.orange))
            ctx.draw(Text("1 €").font(.caption.bold()).foregroundColor(.white), at: CGPoint(x: coin.midX, y: coin.midY))
        }
        .frame(width: 276, height: 84).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Measures the system values and the cut depths of a key from one photo.
struct KeyMeasureView: View {
    var onApply: (KeyMeasurement) -> Void
    var onClose: () -> Void

    @State private var trace: PhotoTrace?
    @State private var scan: KeyScan?
    @State private var coinPixels: Double?
    @State private var coin = ReferenceCoin.all[0]
    @State private var heightText = ""
    @State private var shoulder = 0.0
    @State private var result: KeyMeasurement?
    @State private var image: NSImage?
    @State private var message = ""

    private func load(_ url: URL) {
        result = nil; image = nil; scan = nil; coinPixels = nil; message = ""
        do {
            let t = try PhotoTrace(url: url, maxDimension: KeyScan.scanDimension)
            trace = t
            let shape: [Bool]
            if let subject = t.subjectMask() {
                let (keyPart, inSubject) = t.splitCoin(from: subject)
                shape = t.keyShape(in: keyPart, bridgeGaps: false)
                coinPixels = inSubject ?? t.findCoin(besideKey: shape)
            } else {
                let threshold = t.otsuThreshold()
                shape = t.mask(threshold: threshold, keyIsDark: t.suggestedKeyIsDark(threshold: threshold), bridgeGaps: false)
                coinPixels = t.findCoin(besideKey: shape)
            }
            let s = try KeyScan(trace: t, mask: shape)
            scan = s
            shoulder = s.detectedShoulder
            update()
        } catch { message = error.localizedDescription }
    }

    private var mmPerPixel: Double? {
        if let coinPixels { return coin.diameterMM / coinPixels }
        guard let scan, let h = Double(heightText.replacingOccurrences(of: ",", with: ".")), h > 0 else { return nil }
        return h / scan.bladeHeightPixels
    }

    private func update() {
        guard let scan else { return }
        if let cg = scan.preview(nil as KeyScan.Result?) { image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
        guard let mm = mmPerPixel else { result = nil; return }
        do {
            let m = try scan.measure(mmPerPixel: mm, shoulderBin: shoulder)
            result = m; message = ""
            if let cg = scan.preview(m) { image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
        } catch { result = nil; message = error.localizedDescription }
    }

    private func row(_ title: String, _ value: Double, _ unit: String = "mm") -> some View {
        GridRow { Text(title); Text(String(format: unit == "°" ? "%.0f %@" : "%.2f %@", value, unit)).monospacedDigit() }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Maße aus Foto messen").font(.title2.bold())
                HStack(alignment: .top, spacing: 14) {
                    CoinIllustration()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("1. Schlüssel flach hinlegen, die Zahnkante frei.")
                        Text("2. Münze flach daneben legen, ohne den Schlüssel zu berühren.")
                        Text("3. Genau von oben fotografieren, beides ganz im Bild.")
                    }.font(.callout)
                }
                HStack {
                    Button("Foto wählen …") {
                        let p = NSOpenPanel(); p.allowedContentTypes = [.image]
                        if p.runModal() == .OK, let u = p.url { load(u) }
                    }
                    ContinuityImportButton { load($0) }.fixedSize()
                    Picker("Münze", selection: $coin) { ForEach(ReferenceCoin.all) { Text($0.name).tag($0) } }
                        .frame(width: 170).onChange(of: coin) { _ in update() }
                }
                if let scan {
                    if coinPixels != nil {
                        Label("Münze erkannt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Keine Münze gefunden. Lege eine dazu und fotografiere neu, oder trage die mit dem Messschieber gemessene Schlüsselhöhe ein:", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        TextField("Schlüsselhöhe in mm", text: $heightText).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                            .onChange(of: heightText) { _ in update() }
                    }
                    HStack {
                        Text("Schulter")
                        Slider(value: $shoulder, in: 0...Double(max(1, scan.bins - 40))).onChange(of: shoulder) { _ in update() }
                    }
                }
                if let image { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 280) }
                if let m = result {
                    Text("Blau = Schulter, grün = Stifte. Liegen sie nicht auf Anschlag und Einschnitten, Schulter verschieben.")
                        .font(.caption).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 3) {
                        row("Länge Schulter bis Spitze", m.keyLength)
                        row("Schlüsselhöhe", m.profileHeight)
                        row("Schulter bis erster Stift", m.shoulder)
                        row("Abstand der Stifte", m.pinSpacing)
                        row("Tiefster Schnitt", m.deepestCut)
                        row("Stufe (geschätzt)", m.cutStep)
                        row("Schnittwinkel (geschätzt)", m.cutAngle, "°")
                        row("Plateau (geschätzt)", m.plateau)
                        GridRow { Text("Stufen pro Stift"); Text(m.levels.map(String.init).joined(separator: ", ")) }
                    }
                    Text("Das sind Messwerte aus einem Foto. Prüfe Länge und Höhe mit dem Messschieber, bevor du druckst.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(message).font(.caption).foregroundStyle(.red)
                HStack {
                    Spacer()
                    Button("Abbrechen") { onClose() }
                    Button("Übernehmen") { if let result { onApply(result) } }.disabled(result == nil).keyboardShortcut(.defaultAction)
                }
            }.padding(20)
        }.frame(width: 660, height: 640)
    }
}
