import AppKit
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440, pixelsHigh: 780, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(srgbRed: 0.95, green: 0.96, blue: 0.98, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1440, height: 780).fill()
func text(_ value: String, _ rect: NSRect, _ size: CGFloat, bold: Bool = false) {
    (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: NSColor(srgbRed: 0.12, green: 0.17, blue: 0.28, alpha: 1)])
}
text("WriteBench", NSRect(x: 64, y: 694, width: 900, height: 46), 32, bold: true)
text("Four strokes. One quiet workspace.", NSRect(x: 65, y: 659, width: 900, height: 28), 17)
for (path,x,label) in [("Design/Icon/Previous/icon_512.png",CGFloat(65),"Original"),("Design/Icon/Exports/WriteBench-1024.png",CGFloat(523),"Refined · application icon"),("Design/Icon/Exports/WriteBench-dark-1024.png",CGFloat(981),"Dark · brand asset")] {
    NSImage(contentsOfFile: path)!.draw(in: NSRect(x: x, y: 265, width: 360, height: 360))
    text(label, NSRect(x: x + 22, y: 239, width: 380, height: 27), 16)
}
text("Small-size checks · native pixels", NSRect(x: 87, y: 159, width: 600, height: 28), 17, bold: true)
var x: CGFloat = 88
for size in [16,32,64,128] {
    NSImage(contentsOfFile: "WriteBench/Assets.xcassets/AppIcon.appiconset/icon_\(size).png")!.draw(in: NSRect(x: x, y: 32, width: CGFloat(size), height: CGFloat(size)))
    text("\(size) px", NSRect(x: x + CGFloat(size) + 10, y: 45, width: 70, height: 22), 12)
    x += CGFloat(size) + 120
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Design/Icon/WriteBench-icon-preview.png"))
