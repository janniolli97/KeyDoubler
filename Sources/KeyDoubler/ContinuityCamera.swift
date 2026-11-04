import SwiftUI
import AppKit

/// Button that opens the system "Import from iPhone" menu (Continuity Camera).
/// macOS only offers that menu when an AppKit responder registers for image return types,
/// which is why this is an NSView and not a SwiftUI modifier.
final class ContinuityImportNSView: NSView, NSServicesMenuRequestor {
    var onImport: ((URL) -> Void)?

    private static let imageTypes = NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        NSApp.registerServicesMenuSendTypes([], returnTypes: Self.imageTypes)
        let button = NSButton(title: "Vom iPhone aufnehmen …", target: self, action: #selector(showMenu(_:)))
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor), button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor), button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }

    @objc private func showMenu(_ sender: NSButton) {
        window?.makeFirstResponder(self)   // the menu is built for the current first responder
        guard let event = NSApp.currentEvent else { return }
        // macOS adds its "Insert from iPhone or iPad" entry only to real context menus.
        let menu = NSMenu()
        let header = NSMenuItem(title: "Aufnahme mit dem iPhone", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        if sendType == nil, let returnType, Self.imageTypes.contains(returnType) { return self }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func readSelection(from pboard: NSPasteboard) -> Bool {
        guard let data = Self.imageData(from: pboard) else { return false }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("iphone-\(UUID().uuidString).img")
        guard (try? data.write(to: url)) != nil else { return false }
        onImport?(url)
        return true
    }

    /// Document scans arrive as PDF and are rendered to PNG; photos keep their original data (and EXIF orientation).
    private static func imageData(from pboard: NSPasteboard) -> Data? {
        if let pdf = pboard.data(forType: .pdf) { return renderedPDF(pdf) }
        if let type = pboard.types?.first(where: { imageTypes.contains($0) }) { return pboard.data(forType: type) }
        return nil
    }

    private static func renderedPDF(_ data: Data) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider), let page = doc.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        let scale = 3000 / max(box.width, box.height)
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale); ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

struct ContinuityImportButton: NSViewRepresentable {
    var onImport: (URL) -> Void
    func makeNSView(context: Context) -> ContinuityImportNSView { ContinuityImportNSView(frame: .zero) }
    func updateNSView(_ view: ContinuityImportNSView, context: Context) { view.onImport = onImport }
}
