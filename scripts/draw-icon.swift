// Draws the 1024×1024 Trawl app icon. Usage: swift scripts/draw-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Body: macOS icon grid, 824 pt rounded square centred on the canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x1E3A8A))
ctx.fillPath()
ctx.restoreGState()

// Ocean gradient, teal at the top to deep navy at the bottom.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let ocean = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [color(0x22C1C3), color(0x0E7490), color(0x172554)] as CFArray,
                       locations: [0, 0.55, 1])!
ctx.drawLinearGradient(ocean, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// Two soft wave bands across the lower half.
for (offset, alpha) in [(CGFloat(300), CGFloat(0.05)), (CGFloat(220), CGFloat(0.07))] {
    let wave = CGMutablePath()
    wave.move(to: CGPoint(x: 100, y: offset))
    wave.addCurve(to: CGPoint(x: 924, y: offset), control1: CGPoint(x: 380, y: offset + 70),
                  control2: CGPoint(x: 640, y: offset - 70))
    wave.addLine(to: CGPoint(x: 924, y: 100))
    wave.addLine(to: CGPoint(x: 100, y: 100))
    wave.closeSubpath()
    ctx.addPath(wave)
    ctx.setFillColor(color(0xFFFFFF, alpha))
    ctx.fillPath()
}
ctx.restoreGState()

// Document, tilted slightly, with text lines.
ctx.saveGState()
ctx.translateBy(x: 440, y: 560)
ctx.rotate(by: 0.10)
let doc = CGRect(x: -170, y: -215, width: 340, height: 430)
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.30))
ctx.addPath(CGPath(roundedRect: doc, cornerWidth: 34, cornerHeight: 34, transform: nil))
ctx.setFillColor(color(0xF8FAFC))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
for (i, width) in [CGFloat(230), 250, 200, 250, 170].enumerated() {
    let line = CGRect(x: -125, y: 140 - CGFloat(i) * 62, width: width, height: 26)
    ctx.addPath(CGPath(roundedRect: line, cornerWidth: 13, cornerHeight: 13, transform: nil))
    ctx.setFillColor(color(i == 0 ? 0x0E7490 : 0x94A3B8))
    ctx.fillPath()
}
ctx.restoreGState()

// Magnifying glass over the lower right of the document.
let center = CGPoint(x: 590, y: 450)
let radius: CGFloat = 150
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 26, color: color(0x000000, 0.40))
ctx.setLineCap(.round)
ctx.setStrokeColor(color(0xF59E0B))
ctx.setLineWidth(70)
ctx.move(to: CGPoint(x: center.x + radius * 0.75, y: center.y - radius * 0.75))
ctx.addLine(to: CGPoint(x: center.x + radius * 1.5, y: center.y - radius * 1.5))
ctx.strokePath()
ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
ctx.setFillColor(color(0xBAE6FD, 0.35))
ctx.fillPath()
ctx.restoreGState()
ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
ctx.setStrokeColor(color(0xFFFFFF))
ctx.setLineWidth(44)
ctx.strokePath()
// Glint on the lens.
ctx.setStrokeColor(color(0xFFFFFF, 0.8))
ctx.setLineWidth(18)
ctx.addArc(center: center, radius: radius * 0.62, startAngle: .pi * 0.62, endAngle: .pi * 0.92, clockwise: false)
ctx.strokePath()

NSGraphicsContext.current = nil
let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "icon.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
