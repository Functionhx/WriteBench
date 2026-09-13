import AppKit
import Foundation

let output = CommandLine.arguments[1]
let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let scale = CGFloat(size) / 1024
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let cg = context.cgContext; cg.scaleBy(x: scale, y: scale)
    let base = NSBezierPath(roundedRect: NSRect(x: 55, y: 55, width: 914, height: 914), xRadius: 209, yRadius: 209)
    cg.saveGState(); cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: NSColor(calibratedRed: 0.17, green: 0.32, blue: 0.62, alpha: 0.17).cgColor)
    NSColor.white.setFill(); base.fill(); cg.restoreGState()
    NSGradient(starting: .white, ending: NSColor(calibratedRed: 0.90, green: 0.94, blue: 1, alpha: 1))!.draw(in: base, angle: -65)
    NSColor.white.withAlphaComponent(0.95).setStroke(); base.lineWidth = 4; base.stroke()
    let strokes: [(CGFloat, CGFloat, NSColor, NSColor)] = [
        (275, 23, NSColor(calibratedRed: 0.35, green: 0.29, blue: 1, alpha: 1), NSColor(calibratedRed: 0.42, green: 0.59, blue: 1, alpha: 1)),
        (430, -23, NSColor(calibratedRed: 0.25, green: 0.47, blue: 1, alpha: 1), NSColor(calibratedRed: 0.65, green: 0.79, blue: 1, alpha: 1)),
        (585, 23, NSColor(calibratedRed: 0.15, green: 0.39, blue: 1, alpha: 1), NSColor(calibratedRed: 0.47, green: 0.62, blue: 1, alpha: 1)),
        (740, -23, NSColor(calibratedRed: 0.66, green: 0.70, blue: 1, alpha: 1), NSColor(calibratedRed: 0.34, green: 0.57, blue: 1, alpha: 1))
    ]
    for (x, angle, top, bottom) in strokes {
        cg.saveGState(); cg.translateBy(x: x, y: 512); cg.rotate(by: angle * .pi / 180)
        let stroke = NSBezierPath(roundedRect: NSRect(x: -61, y: -215, width: 122, height: 430), xRadius: 61, yRadius: 61)
        NSGradient(starting: top, ending: bottom)!.draw(in: stroke, angle: -90)
        cg.restoreGState()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("icon_\(size).png"))
}
