// Generates Resources/AppIcon.icns: a key whose bow is an apple.  Usage: swift tools/make_icon.swift
import CoreGraphics
import ImageIO
import Foundation

let S = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
func gradient(_ cols: [CGColor]) -> CGGradient { CGGradient(colorsSpace: cs, colors: cols as CFArray, locations: nil)! }

// Background: macOS-style rounded square
let bg = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState(); ctx.addPath(bg); ctx.clip()
ctx.drawLinearGradient(gradient([color(0.10, 0.20, 0.38), color(0.12, 0.55, 0.62)]), start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
ctx.restoreGState()

// Key (local frame: apple at top, blade pointing down), then rotated
ctx.saveGState()
ctx.addPath(bg); ctx.clip()
ctx.translateBy(x: 512, y: 512); ctx.rotate(by: 40 * .pi / 180); ctx.scaleBy(x: 1.0, y: 1.0); ctx.translateBy(x: 0, y: 140)

// drop shadow
ctx.setShadow(offset: CGSize(width: 14, height: -22), blur: 30, color: color(0, 0, 0, 0.45))

// blade
let blade = CGMutablePath()
blade.move(to: CGPoint(x: -38, y: -100))
blade.addLine(to: CGPoint(x: -38, y: -470)); blade.addQuadCurve(to: CGPoint(x: -20, y: -515), control: CGPoint(x: -38, y: -515))
blade.addLine(to: CGPoint(x: 20, y: -515)); blade.addLine(to: CGPoint(x: 38, y: -470))
// teeth on the right side
var y = -470.0
for (i, depth) in [34.0, 20, 40, 26].enumerated() {
    blade.addLine(to: CGPoint(x: 38, y: y)); y += 52
    blade.addLine(to: CGPoint(x: 38 - depth, y: y - 8 - Double(i)))
    blade.addLine(to: CGPoint(x: 38 - depth, y: y + 12))
    y += 12
}
blade.addLine(to: CGPoint(x: 38, y: -100)); blade.closeSubpath()
ctx.saveGState(); ctx.addPath(blade); ctx.clip()
ctx.drawLinearGradient(gradient([color(0.82, 0.66, 0.22), color(1.0, 0.92, 0.55), color(0.78, 0.60, 0.18)]), start: CGPoint(x: -40, y: 0), end: CGPoint(x: 40, y: 0), options: [])
ctx.restoreGState()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.addPath(blade); ctx.setStrokeColor(color(0.55, 0.40, 0.08, 0.8)); ctx.setLineWidth(3); ctx.strokePath()
// groove
ctx.setStrokeColor(color(0.6, 0.45, 0.1, 0.5)); ctx.setLineWidth(5)
ctx.move(to: CGPoint(x: -12, y: -130)); ctx.addLine(to: CGPoint(x: -12, y: -480)); ctx.strokePath()

// apple body
let apple = CGMutablePath()
apple.move(to: CGPoint(x: 0, y: 105))
apple.addCurve(to: CGPoint(x: 160, y: -20), control1: CGPoint(x: 60, y: 185), control2: CGPoint(x: 170, y: 120))
apple.addCurve(to: CGPoint(x: 0, y: -135), control1: CGPoint(x: 150, y: -110), control2: CGPoint(x: 75, y: -150))
apple.addCurve(to: CGPoint(x: -160, y: -20), control1: CGPoint(x: -75, y: -150), control2: CGPoint(x: -150, y: -110))
apple.addCurve(to: CGPoint(x: 0, y: 105), control1: CGPoint(x: -170, y: 120), control2: CGPoint(x: -60, y: 185))
apple.closeSubpath()
ctx.setShadow(offset: CGSize(width: 10, height: -16), blur: 24, color: color(0, 0, 0, 0.4))
ctx.saveGState(); ctx.addPath(apple); ctx.clip()
ctx.drawRadialGradient(gradient([color(1.0, 0.35, 0.30), color(0.80, 0.08, 0.12), color(0.55, 0.02, 0.08)]),
                       startCenter: CGPoint(x: -50, y: 50), startRadius: 10, endCenter: CGPoint(x: 0, y: -20), endRadius: 230, options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
ctx.restoreGState()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
// key hole in the apple
ctx.setFillColor(color(0.35, 0.02, 0.05, 0.9))
ctx.fillEllipse(in: CGRect(x: -26, y: -40, width: 52, height: 52))
ctx.fill(CGRect(x: -11, y: -100, width: 22, height: 70))
// highlight
ctx.saveGState(); ctx.addPath(apple); ctx.clip()
ctx.setFillColor(color(1, 1, 1, 0.28))
ctx.fillEllipse(in: CGRect(x: -120, y: 40, width: 80, height: 50))
ctx.restoreGState()
// stem and leaf
ctx.setStrokeColor(color(0.35, 0.2, 0.08)); ctx.setLineWidth(16); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 0, y: 100)); ctx.addQuadCurve(to: CGPoint(x: 18, y: 180), control: CGPoint(x: 2, y: 150)); ctx.strokePath()
let leaf = CGMutablePath()
leaf.move(to: CGPoint(x: 18, y: 160))
leaf.addCurve(to: CGPoint(x: 130, y: 215), control1: CGPoint(x: 40, y: 220), control2: CGPoint(x: 95, y: 235))
leaf.addCurve(to: CGPoint(x: 18, y: 160), control1: CGPoint(x: 120, y: 150), control2: CGPoint(x: 60, y: 135))
ctx.addPath(leaf); ctx.clip()
ctx.drawLinearGradient(gradient([color(0.55, 0.85, 0.25), color(0.15, 0.55, 0.20)]), start: CGPoint(x: 20, y: 230), end: CGPoint(x: 130, y: 150), options: [])
ctx.restoreGState()

let img = ctx.makeImage()!
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
print("wrote", out)
