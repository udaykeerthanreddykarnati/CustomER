import AppKit

let folderPath = NSHomeDirectory() + "/Desktop/CustomER"

// Create folder if needed
try? FileManager.default.createDirectory(atPath: folderPath, withIntermediateDirectories: true)

// Draw custom folder icon
let size = NSSize(width: 512, height: 512)
let img = NSImage(size: size)
img.lockFocus()

let ctx = NSGraphicsContext.current!.cgContext

// ── Folder body (classic macOS shape) ──────────────────────────────
let yellow = NSColor(red: 213/255.0, green: 211/255.0, blue: 113/255.0, alpha: 1.0)  // #e0df7dff
let shadow = NSColor(red: 0.75, green: 0.73, blue: 0.0, alpha: 1.0)  // darker shade

// Tab (top-left bump)
let tab = NSBezierPath()
tab.move(to: NSPoint(x: 60, y: 390))
tab.line(to: NSPoint(x: 60, y: 420))
tab.curve(to: NSPoint(x: 80, y: 440),
          controlPoint1: NSPoint(x: 60, y: 432),
          controlPoint2: NSPoint(x: 69, y: 440))
tab.line(to: NSPoint(x: 210, y: 440))
tab.curve(to: NSPoint(x: 235, y: 418),
          controlPoint1: NSPoint(x: 224, y: 440),
          controlPoint2: NSPoint(x: 235, y: 430))
tab.line(to: NSPoint(x: 235, y: 390))
tab.close()
yellow.setFill()
tab.fill()

// Main body
let body = NSBezierPath(roundedRect: NSRect(x: 55, y: 100, width: 402, height: 300), xRadius: 22, yRadius: 22)
yellow.setFill()
body.fill()

// Bottom shadow strip
let bottomShadow = NSBezierPath(roundedRect: NSRect(x: 55, y: 100, width: 402, height: 40), xRadius: 22, yRadius: 22)
shadow.setFill()
bottomShadow.fill()

// ── Label text ──────────────────────────────────────────────────────
let text = "CustomER"
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 68, weight: .black),
    .foregroundColor: NSColor(red: 0.12, green: 0.11, blue: 0.0, alpha: 1.0)
]
let attrStr = NSAttributedString(string: text, attributes: attrs)
let tSize = attrStr.size()
let tOrigin = NSPoint(x: (512 - tSize.width) / 2, y: (512 - tSize.height) / 2 - 14)
attrStr.draw(at: tOrigin)

img.unlockFocus()

NSWorkspace.shared.setIcon(img, forFile: folderPath, options: [])
print("Done: \(folderPath)")
