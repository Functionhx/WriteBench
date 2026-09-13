import AppKit
import Foundation
let output = CommandLine.arguments[1]
let pages = [
"Dear Alex,\n\nI am writing to invite you to a lecture on Chinese culture at our university. It will take place in the main library at 3 p.m. this Friday. Professor Wang will introduce the history of Chinese tea.",
"Since you enjoy learning about local traditions, I think you will find the talk interesting. There will also be a short tea tasting after the lecture.\n\nPlease let me know if you can come. I look forward to hear from you.\n\nYours,\nLi Ming"
]
for (index, text) in pages.enumerated() {
    let image = NSImage(size: NSSize(width: 1000, height: 1000)); image.lockFocus()
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1000, height: 1000).fill()
    let style = NSMutableParagraphStyle(); style.lineSpacing = 16
    (text as NSString).draw(in: NSRect(x: 70, y: 90, width: 860, height: 800), withAttributes: [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black, .paragraphStyle: style])
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("ocr-sample-\(index + 1).png"))
}
