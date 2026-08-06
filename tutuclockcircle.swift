import AppKit
import Foundation

// MARK: - Colors (Matching Theme)
let kBg          = NSColor(red: 254/255.0, green: 249/255.0, blue: 195/255.0, alpha: 1.00) // #FEF9C3
let kText        = NSColor(red: 128/255.0, green: 0/255.0, blue: 32/255.0, alpha: 1.00)       // #800020 Rich Burgundy
let kAccent      = NSColor(red: 128/255.0, green: 0/255.0, blue: 32/255.0, alpha: 1.00)       // #800020 Rich Burgundy
let kDim         = NSColor(red: 0.35, green: 0.35, blue: 0.25, alpha: 1.00)                 // Muted text
let kBorder      = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.00)                 // Black outline
let kOuterBorder = NSColor(red: 128/255.0, green: 0/255.0, blue: 32/255.0, alpha: 1.00) // #800020 Rich Burgundy

extension NSColor {
    convenience init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6, let val = UInt64(str, radix: 16) else { return nil }
        let r = CGFloat((val & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((val & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(val & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

class ThemeManager {
    static let shared = ThemeManager()
    static let notifName = NSNotification.Name("com.user.CustomER.themeChanged")
    private let themeFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CustomER", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("theme.json")
    }()
    var currentBgColor: NSColor {
        if let data = try? Data(contentsOf: themeFileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let hex = json["bgHex"],
           let color = NSColor(hex: hex) {
            return color
        }
        return kBg
    }
}

class CircleClockWindow: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

class CircleClockView: NSView {
    private var timer: Timer?
    private var dragStart: NSPoint = .zero
    private var dragActive = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        startTimer()
        listenForThemeChanges()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = bounds.width / 2.0
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2.0 - 10.0

        // Draw 12 Hour Ticks
        for hour in 0..<12 {
            let angle = CGFloat(hour) * (CGFloat.pi / 6.0)
            let isMain = (hour % 3 == 0)
            let tickLength: CGFloat = isMain ? 12.0 : 7.0

            let innerPt = CGPoint(
                x: center.x + (radius - tickLength) * sin(angle),
                y: center.y + (radius - tickLength) * cos(angle)
            )
            let outerPt = CGPoint(
                x: center.x + radius * sin(angle),
                y: center.y + radius * cos(angle)
            )

            ctx.setStrokeColor(kText.cgColor)
            ctx.setLineWidth(isMain ? 3.0 : 1.5)
            ctx.move(to: innerPt)
            ctx.addLine(to: outerPt)
            ctx.strokePath()
        }

        // Get Time
        let cal = Calendar.current
        let now = Date()
        let comp = cal.dateComponents([.hour, .minute, .second], from: now)
        let h = CGFloat(comp.hour ?? 0)
        let m = CGFloat(comp.minute ?? 0)
        let s = CGFloat(comp.second ?? 0)

        // Hour Hand
        let hourAngle = (h + m / 60.0) * (CGFloat.pi / 6.0)
        let hourLength = radius * 0.5
        let hourPt = CGPoint(
            x: center.x + hourLength * sin(hourAngle),
            y: center.y + hourLength * cos(hourAngle)
        )
        ctx.setStrokeColor(kText.cgColor)
        ctx.setLineWidth(4.5)
        ctx.setLineCap(.round)
        ctx.move(to: center)
        ctx.addLine(to: hourPt)
        ctx.strokePath()

        // Minute Hand
        let minAngle = (m + s / 60.0) * (CGFloat.pi / 30.0)
        let minLength = radius * 0.72
        let minPt = CGPoint(
            x: center.x + minLength * sin(minAngle),
            y: center.y + minLength * cos(minAngle)
        )
        ctx.setStrokeColor(kText.cgColor)
        ctx.setLineWidth(3.0)
        ctx.setLineCap(.round)
        ctx.move(to: center)
        ctx.addLine(to: minPt)
        ctx.strokePath()

        // Second Hand
        let secAngle = s * (CGFloat.pi / 30.0)
        let secLength = radius * 0.82
        let secPt = CGPoint(
            x: center.x + secLength * sin(secAngle),
            y: center.y + secLength * cos(secAngle)
        )
        ctx.setStrokeColor(kAccent.cgColor)
        ctx.setLineWidth(2.0)
        ctx.move(to: center)
        ctx.addLine(to: secPt)
        ctx.strokePath()

        // Center Coral Dot
        ctx.setFillColor(kAccent.cgColor)
        ctx.addEllipse(in: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
        ctx.fillPath()
        ctx.setStrokeColor(kBorder.cgColor)
        ctx.setLineWidth(1.0)
        ctx.addEllipse(in: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
        ctx.strokePath()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    // Dragging
    private func listenForThemeChanges() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(onThemeChanged),
            name: ThemeManager.notifName,
            object: nil
        )
    }

    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow; dragActive = true; window?.makeKey()
        super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { super.mouseDragged(with: event); return }
        let c = event.locationInWindow
        w.setFrameOrigin(NSPoint(x: w.frame.origin.x + c.x - dragStart.x,
                                  y: w.frame.origin.y + c.y - dragStart.y))
    }
    override func mouseUp(with event: NSEvent) { dragActive = false; super.mouseUp(with: event) }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 350, y: 590, width: 220, height: 220)
        window = CircleClockWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: -1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false
        window.contentView = CircleClockView(frame: rect)
        window.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
