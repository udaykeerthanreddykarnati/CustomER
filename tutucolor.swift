import AppKit
import Foundation

// MARK: - Color Extension Helpers
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

    func toHex() -> String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FEF9C3" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Theme Manager
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
        get {
            if let data = try? Data(contentsOf: themeFileURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let hex = json["bgHex"],
               let color = NSColor(hex: hex) {
                return color
            }
            return NSColor(red: 254/255.0, green: 249/255.0, blue: 195/255.0, alpha: 1.00) // Default #FEF9C3
        }
        set {
            let hex = newValue.toHex()
            let dict = ["bgHex": hex]
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                try? data.write(to: themeFileURL)
            }
            DistributedNotificationCenter.default().postNotificationName(
                ThemeManager.notifName,
                object: nil,
                userInfo: ["bgHex": hex],
                deliverImmediately: true
            )
        }
    }
}

// MARK: - Constants
let kText   = NSColor(red: 128/255.0, green: 0/255.0, blue: 32/255.0, alpha: 1.00) // #800020 Rich Burgundy
let kBorder = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.00)

class ColorPickerWindow: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

class ColorPickerView: NSView {
    private let swatchesContainer = NSView()
    private let pickerBtn = NSButton()

    private var dragStart: NSPoint = .zero
    private var dragActive = false

    private let presetHexes = ["#FEF9C3", "#FFE4E6", "#DCFCE7", "#E0F2FE", "#F3E8FF", "#F5EBE0"]

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        listenForThemeChanges()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 0

        swatchesContainer.wantsLayer = true
        addSubview(swatchesContainer)

        renderSwatches()

        pickerBtn.title = "WihhL"
        pickerBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        pickerBtn.isBordered = false
        pickerBtn.wantsLayer = true
        pickerBtn.layer?.cornerRadius = 0
        pickerBtn.layer?.backgroundColor = kText.cgColor
        pickerBtn.layer?.borderWidth = 1
        pickerBtn.layer?.borderColor = kBorder.cgColor
        pickerBtn.contentTintColor = .white
        pickerBtn.target = self
        pickerBtn.action = #selector(openSystemColorPicker)
        addSubview(pickerBtn)
    }

    private func renderSwatches() {
        for sub in swatchesContainer.subviews { sub.removeFromSuperview() }

        let count = presetHexes.count
        let itemW: CGFloat = 28
        let itemH: CGFloat = 28
        let gap: CGFloat = 8
        let totalW = CGFloat(count) * itemW + CGFloat(count - 1) * gap
        let startX = (280 - totalW) / 2.0

        for (i, hex) in presetHexes.enumerated() {
            let x = startX + CGFloat(i) * (itemW + gap)
            let btn = NSButton(frame: NSRect(x: x, y: 0, width: itemW, height: itemH))
            btn.title = ""
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 0
            if let color = NSColor(hex: hex) {
                btn.layer?.backgroundColor = color.cgColor
            }
            btn.layer?.borderWidth = 1.5
            btn.layer?.borderColor = kBorder.cgColor
            btn.tag = i
            btn.target = self
            btn.action = #selector(swatchTapped(_:))
            swatchesContainer.addSubview(btn)
        }
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        swatchesContainer.frame = NSRect(x: 0, y: h - 42, width: w, height: 30)
        pickerBtn.frame = NSRect(x: (w - 100)/2, y: 10, width: 100, height: 22)
    }

    @objc private func swatchTapped(_ sender: NSButton) {
        let hex = presetHexes[sender.tag]
        if let color = NSColor(hex: hex) {
            ThemeManager.shared.currentBgColor = color
        }
    }

    @objc private func openSystemColorPicker() {
        let panel = NSColorPanel.shared
        panel.color = ThemeManager.shared.currentBgColor
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.isContinuous = true
        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        ThemeManager.shared.currentBgColor = sender.color
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
        let rect = NSRect(x: 320, y: 830, width: 280, height: 80)
        window = ColorPickerWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: -1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false
        window.contentView = ColorPickerView(frame: rect)
        window.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
