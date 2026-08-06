import AppKit
import Foundation

// MARK: - Colors (Matching tututodo Theme)
let kBg     = NSColor(red: 254/255.0, green: 249/255.0, blue: 195/255.0, alpha: 1.00) // #FEF9C3 Pastel Butter
let kText   = NSColor(red: 128/255.0, green: 0/255.0, blue: 32/255.0, alpha: 1.00)       // #800020 Rich Burgundy
let kAccent = NSColor(red: 128/255.0, green: 0/255.0, blue: 32/255.0, alpha: 1.00)       // #800020 Rich Burgundy
let kDim    = NSColor(red: 0.35, green: 0.35, blue: 0.25, alpha: 1.00)                 // Muted text
let kBorder = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.00)                 // Black outline

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

class ClockWindow: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

class ClockView: NSView {
    private let timeLabel = NSTextField()
    private let dateLabel = NSTextField()
    private let secLabel  = NSTextField()
    private var timer: Timer?

    private var dragStart: NSPoint = .zero
    private var dragActive = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        updateClock()
        startTimer()
        listenForThemeChanges()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor

        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 42, weight: .black)
        timeLabel.textColor = kText
        timeLabel.isEditable = false; timeLabel.isBordered = false; timeLabel.backgroundColor = .clear
        timeLabel.alignment = .center
        addSubview(timeLabel)

        secLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        secLabel.textColor = .white
        secLabel.isEditable = false; secLabel.isBordered = false; secLabel.backgroundColor = .clear
        secLabel.alignment = .center; secLabel.wantsLayer = true
        secLabel.layer?.cornerRadius = 0
        secLabel.layer?.backgroundColor = kAccent.cgColor
        secLabel.layer?.borderWidth = 1
        secLabel.layer?.borderColor = kBorder.cgColor
        addSubview(secLabel)

        dateLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        dateLabel.textColor = kDim
        dateLabel.isEditable = false; dateLabel.isBordered = false; dateLabel.backgroundColor = .clear
        dateLabel.alignment = .center
        addSubview(dateLabel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        timeLabel.frame = NSRect(x: 10, y: 40, width: w - 20, height: 50)
        secLabel.frame  = NSRect(x: w - 42, y: h - 26, width: 28, height: 18)
        dateLabel.frame = NSRect(x: 10, y: 16, width: w - 20, height: 20)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateClock()
        }
    }

    private func updateClock() {
        let now = Date()
        let tf = DateFormatter()
        tf.dateFormat = "h:mm a"
        timeLabel.stringValue = tf.string(from: now)

        let sf = DateFormatter()
        sf.dateFormat = "ss"
        secLabel.stringValue = sf.string(from: now)

        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d"
        dateLabel.stringValue = df.string(from: now).uppercased()
    }

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
        let rect = NSRect(x: 320, y: 930, width: 280, height: 110)
        window = ClockWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: -1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false
        window.contentView = ClockView(frame: rect)
        window.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
