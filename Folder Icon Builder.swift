import AppKit
import Foundation

func drawMacOSFolder(folderColor: NSColor, titleText: String? = nil, isResume: Bool = false) -> NSImage {
    let size = NSSize(width: 512, height: 512)
    let image = NSImage(size: size)
    
    image.lockFocus()
    
    // 1. Draw Folder Back Tab
    let tabPath = NSBezierPath()
    tabPath.move(to: NSPoint(x: 40, y: 350))
    tabPath.line(to: NSPoint(x: 40, y: 430))
    tabPath.appendArc(withCenter: NSPoint(x: 60, y: 435), radius: 15, startAngle: 180, endAngle: 90, clockwise: true)
    tabPath.line(to: NSPoint(x: 210, y: 450))
    tabPath.appendArc(withCenter: NSPoint(x: 225, y: 435), radius: 15, startAngle: 90, endAngle: 0, clockwise: true)
    tabPath.line(to: NSPoint(x: 260, y: 350))
    tabPath.close()
    
    if folderColor == NSColor.black {
        NSColor(white: 0.25, alpha: 1.0).set()
    } else {
        folderColor.blended(withFraction: 0.25, of: .black)?.set()
    }
    tabPath.fill()
    
    NSColor(white: 0.55, alpha: 0.9).set()
    tabPath.lineWidth = 4
    tabPath.stroke()
    
    // 2. Draw Main Folder Front Body/Flap
    let bodyRect = NSRect(x: 30, y: 40, width: 452, height: 345)
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 28, yRadius: 28)
    
    folderColor.set()
    bodyPath.fill()
    
    if folderColor == NSColor.black {
        NSColor(white: 0.5, alpha: 1.0).set()
    } else {
        NSColor(white: 1.0, alpha: 0.4).set()
    }
    bodyPath.lineWidth = 4
    bodyPath.stroke()
    
    // 3. Draw Content inside Folder
    if isResume {
        // Draw White Resume Paper inside Folder Body
        let paperRect = NSRect(x: 60, y: 70, width: 392, height: 345)
        let paperPath = NSBezierPath(roundedRect: paperRect, xRadius: 16, yRadius: 16)
        NSColor.white.set()
        paperPath.fill()
        
        NSColor(white: 0.85, alpha: 1.0).set()
        paperPath.lineWidth = 3
        paperPath.stroke()
        
        // "RESUME" Header fitted perfectly
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 52),
            .foregroundColor: NSColor(red: 0.08, green: 0.40, blue: 0.92, alpha: 1.0)
        ]
        NSAttributedString(string: "RESUME", attributes: titleAttrs).draw(at: NSPoint(x: 150, y: 350))
        
        // Divider line
        let div = NSBezierPath()
        div.move(to: NSPoint(x: 80, y: 340))
        div.line(to: NSPoint(x: 432, y: 340))
        NSColor(red: 0.08, green: 0.40, blue: 0.92, alpha: 0.6).set()
        div.lineWidth = 4
        div.stroke()
        
        // Mock text bars
        var lineY: CGFloat = 300
        let linesPattern: [(CGFloat, CGFloat)] = [
            (80, 180), (80, 350), (80, 310),
            (80, 160), (80, 340), (80, 280),
            (80, 170), (80, 330), (80, 260)
        ]
        for (startX, lineW) in linesPattern {
            let lp = NSBezierPath(roundedRect: NSRect(x: startX, y: lineY, width: lineW, height: 14), xRadius: 7, yRadius: 7)
            NSColor(white: 0.55, alpha: 1.0).set()
            lp.fill()
            lineY -= 24
        }
    } else if let title = titleText {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        if title.contains("\n") {
            paragraphStyle.lineSpacing = -8
        }
        
        // Safe bounding box with generous padding inside the folder flap
        let targetRect = NSRect(x: 50, y: 60, width: 412, height: 305)
        
        // Dynamic Auto-Scaling to prevent any clipping
        var fontSize: CGFloat = 130
        var bestAttrs: [NSAttributedString.Key: Any] = [:]
        var bestSize = NSSize.zero
        
        while fontSize >= 20 {
            let font = NSFont.boldSystemFont(ofSize: fontSize)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle
            ]
            let size = NSAttributedString(string: title, attributes: attrs).size()
            
            if size.width <= targetRect.width && size.height <= targetRect.height {
                bestAttrs = attrs
                bestSize = size
                break
            }
            fontSize -= 2
        }
        
        let drawY = targetRect.origin.y + (targetRect.height - bestSize.height) / 2
        let drawRect = NSRect(x: targetRect.origin.x, y: drawY, width: targetRect.width, height: bestSize.height)
        
        NSAttributedString(string: title, attributes: bestAttrs).draw(in: drawRect)
        print("Fitted '\(title.replacingOccurrences(of: "\n", with: " "))' at \(fontSize)pt (size: \(Int(bestSize.width))x\(Int(bestSize.height)))")
    }
    
    image.unlockFocus()
    return image
}

let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

// 1. CCBD folder
let ccbdFolder = desktop.appendingPathComponent("CCBD")
let ccbdImg = drawMacOSFolder(folderColor: NSColor.black, titleText: "CCBD")
NSWorkspace.shared.setIcon(ccbdImg, forFile: ccbdFolder.path, options: [])

// 2. sideShit folder
let sideFolder = desktop.appendingPathComponent("sideShit")
let sideColor = NSColor(red: 1.0, green: 0.502, blue: 0.333, alpha: 1.0)
let sideImg = drawMacOSFolder(folderColor: sideColor, titleText: "side\nShit")
NSWorkspace.shared.setIcon(sideImg, forFile: sideFolder.path, options: [])

// 3. college projects folder
let collegeFolder = desktop.appendingPathComponent("college projects")
let collegeColor = NSColor(red: 0.08, green: 0.60, blue: 0.42, alpha: 1.0)
let collegeImg = drawMacOSFolder(folderColor: collegeColor, titleText: "clg\nproj")
NSWorkspace.shared.setIcon(collegeImg, forFile: collegeFolder.path, options: [])

// 4. resume folder
let resumeFolder = desktop.appendingPathComponent("resume")
let blueFolderColor = NSColor(red: 0.12, green: 0.53, blue: 0.90, alpha: 1.0)
let resumeImg = drawMacOSFolder(folderColor: blueFolderColor, isResume: true)
NSWorkspace.shared.setIcon(resumeImg, forFile: resumeFolder.path, options: [])

