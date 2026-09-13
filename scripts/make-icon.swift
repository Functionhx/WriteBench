import AppKit
import Foundation

// Reproducible original artwork. All dimensions are in a 1024-unit master grid.
// Export every physical resolution independently; 16/32 px receive optical compensation.
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "WriteBench/Assets.xcassets/AppIcon.appiconset"
let exportFolder = "Design/Icon/Exports"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
try FileManager.default.createDirectory(atPath: exportFolder, withIntermediateDirectories: true)
func color(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: alpha)
}
let strokes: [(CGFloat, CGFloat, UInt32, UInt32)] = [
    (308, 23, 0x6866EE, 0x426BF1),
    (444, -23, 0x3E79F9, 0x95BAFF),
    (580, 23, 0x2760EE, 0x5489FF),
    (716, -23, 0xA2B5FF, 0x548CF9)
]
func platePath() -> NSBezierPath {
    // Softly continuous corners with longer tangent transitions than a circular fillet.
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 330, y: 96)); p.line(to: NSPoint(x: 694, y: 96))
    p.curve(to: NSPoint(x: 928, y: 330), controlPoint1: NSPoint(x: 866, y: 96), controlPoint2: NSPoint(x: 928, y: 158))
    p.line(to: NSPoint(x: 928, y: 694))
    p.curve(to: NSPoint(x: 694, y: 928), controlPoint1: NSPoint(x: 928, y: 866), controlPoint2: NSPoint(x: 866, y: 928))
    p.line(to: NSPoint(x: 330, y: 928))
    p.curve(to: NSPoint(x: 96, y: 694), controlPoint1: NSPoint(x: 158, y: 928), controlPoint2: NSPoint(x: 96, y: 866))
    p.line(to: NSPoint(x: 96, y: 330))
    p.curve(to: NSPoint(x: 330, y: 96), controlPoint1: NSPoint(x: 96, y: 158), controlPoint2: NSPoint(x: 158, y: 96)); p.close()
    return p
}
func render(_ size: Int, dark: Bool = false, markOnly: Bool = false) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    cg.setAllowsAntialiasing(true); cg.setShouldAntialias(true)
    let small = size <= 32
    if !markOnly {
        let plate = platePath()
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -14), blur: 22, color: color(0x1D3264, dark ? 0.3 : 0.19).cgColor)
        color(dark ? 0x192642 : 0xFAFCFF).setFill(); plate.fill(); cg.restoreGState()
        NSGradient(starting: color(dark ? 0x293753 : 0xFFFFFF), ending: color(dark ? 0x172139 : 0xEAF0FB))!.draw(in: plate, angle: -90)
        // A quiet edge highlight; omit at tiny sizes to avoid a fuzzy white halo.
        if !small { color(dark ? 0x5A6A8C : 0xFFFFFF, dark ? 0.35 : 0.95).setStroke(); plate.lineWidth = 2.5; plate.stroke() }
    }
    for (x, angle, top, bottom) in strokes {
        cg.saveGState(); cg.translateBy(x: x, y: 520); cg.rotate(by: angle * .pi / 180)
        let width: CGFloat = small ? 123 : 114
        let shape = NSBezierPath(roundedRect: NSRect(x: -width / 2, y: -198, width: width, height: 396), xRadius: width / 2, yRadius: width / 2)
        if !small {
            cg.saveGState(); cg.setShadow(offset: CGSize(width: 0, height: -7), blur: 10, color: color(0x26489C, dark ? 0.24 : 0.15).cgColor)
            color(bottom).setFill(); shape.fill(); cg.restoreGState()
        }
        NSGradient(starting: color(top), ending: color(bottom))!.draw(in: shape, angle: -90)
        if !small { color(0xFFFFFF, 0.22).setStroke(); shape.lineWidth = 1.8; shape.stroke() }
        cg.restoreGState()
    }
    NSGraphicsContext.restoreGraphicsState()
    let srgb = bitmap.converting(to: .sRGB, renderingIntent: .perceptual) ?? bitmap
    return srgb.representation(using: .png, properties: [:])!
}
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try render(size).write(to: URL(fileURLWithPath: output).appendingPathComponent("icon_\(size).png"))
}
try render(1024).write(to: URL(fileURLWithPath: exportFolder + "/WriteBench-1024.png"))
try render(1024, dark: true).write(to: URL(fileURLWithPath: exportFolder + "/WriteBench-dark-1024.png"))
try render(1024, markOnly: true).write(to: URL(fileURLWithPath: exportFolder + "/WriteBench-mark.png"))

// An editable SVG master preserves individual W strokes and the background shape.
func hex(_ value: UInt32) -> String { String(format: "#%06X", value) }
let gradients = strokes.enumerated().map { i, stroke in
    "<linearGradient id=\"stroke\(i)\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop stop-color=\"\(hex(stroke.2))\"/><stop offset=\"1\" stop-color=\"\(hex(stroke.3))\"/></linearGradient>"
}.joined(separator: "\n")
let vectors = strokes.enumerated().map { i, stroke in
    "<g id=\"W-stroke-\(i+1)\" transform=\"translate(\(stroke.0) 504) rotate(\(-stroke.1))\"><rect x=\"-57\" y=\"-198\" width=\"114\" height=\"396\" rx=\"57\" fill=\"url(#stroke\(i))\" stroke=\"#FFFFFF\" stroke-opacity=\".22\" stroke-width=\"1.8\"/></g>"
}.joined(separator: "\n")
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<title>WriteBench — four-stroke W</title>
<defs>
<linearGradient id="porcelain" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#FFFFFF"/><stop offset="1" stop-color="#EAF0FB"/></linearGradient>
\(gradients)
<filter id="plate-shadow" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="14" stdDeviation="11" flood-color="#1D3264" flood-opacity=".19"/></filter>
<filter id="mark-shadow" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="7" stdDeviation="5" flood-color="#26489C" flood-opacity=".15"/></filter>
</defs>
<path id="porcelain-base" d="M330 96 H694 C866 96 928 158 928 330 V694 C928 866 866 928 694 928 H330 C158 928 96 866 96 694 V330 C96 158 158 96 330 96Z" fill="url(#porcelain)" stroke="white" stroke-width="2.5" filter="url(#plate-shadow)"/>
<g id="WriteBench-W" filter="url(#mark-shadow)">\(vectors)</g>
</svg>
"""
try svg.write(toFile: "Design/Icon/WriteBench.svg", atomically: true, encoding: .utf8)
print("Generated sRGB app icons (16–1024 px), exports, and editable SVG master.")
