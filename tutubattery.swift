import AppKit
import Foundation

// MARK: - Colors (Matching tututodo Theme)
let kBg          = NSColor(red: 254/255.0, green: 249/255.0, blue: 195/255.0, alpha: 1.00) // #FEF9C3
let kText        = NSColor(red: 128/255.0, green: 0/255.0, blue: 32/255.0, alpha: 1.00)       // #800020 Rich Burgundy
let kAccent      = NSColor(red: 128/255.0, green: 0/255.0, blue: 32/255.0, alpha: 1.00)       // #800020 Rich Burgundy
let kDim         = NSColor(red: 0.35, green: 0.35, blue: 0.25, alpha: 1.00)                 // Muted text
let kBorder      = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.00)                 // Black outline
let kOuterBorder = NSColor(red: 128/255.0, green: 0/255.0, blue: 32/255.0, alpha: 1.00) // #800020 Rich Burgundy
let kCard        = NSColor(red: 254/255.0, green: 252/255.0, blue: 232/255.0, alpha: 1.00) // #FEFCE8 Cream card

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

// MARK: - Custom Centered Text Field Cell
class CenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var newRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        let deltaY = rect.height - textSize.height
        if deltaY > 0 {
            newRect.origin.y += deltaY / 2.0
            newRect.size.height -= deltaY
        }
        return newRect
    }
}

class BatteryWindow: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

class BatteryView: NSView {
    private let macCard = NSView()
    private let macPctLabel = NSTextField()
    private let macStatusLabel = NSTextField()
    private let macProgressBar = NSView()
    private let macProgressFill = NSView()

    private let btHeaderLabel = NSTextField()
    private let btListContainer = NSView()

    private var timer: Timer?
    private var isFetching = false
    private var lastDevices: [(name: String, battery: Int?)] = []

    private var dragStart: NSPoint = .zero
    private var dragActive = false

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
        layer?.borderColor = NSColor.clear.cgColor

        // Mac Battery Card
        macCard.wantsLayer = true
        macCard.layer?.cornerRadius = 0
        macCard.layer?.backgroundColor = kCard.cgColor
        macCard.layer?.borderWidth = 1.5
        macCard.layer?.borderColor = kBorder.cgColor
        addSubview(macCard)

        macPctLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 32, weight: .black)
        macPctLabel.textColor = kText
        macPctLabel.isEditable = false; macPctLabel.isBordered = false; macPctLabel.backgroundColor = .clear
        macCard.addSubview(macPctLabel)

        let statusCell = CenteredTextFieldCell(textCell: "")
        statusCell.alignment = .center
        statusCell.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        statusCell.textColor = .white
        macStatusLabel.cell = statusCell
        macStatusLabel.isEditable = false; macStatusLabel.isBordered = false
        macStatusLabel.wantsLayer = true
        macStatusLabel.layer?.cornerRadius = 0
        macStatusLabel.layer?.backgroundColor = kAccent.cgColor
        macStatusLabel.layer?.borderWidth = 1.5
        macStatusLabel.layer?.borderColor = kBorder.cgColor
        macCard.addSubview(macStatusLabel)

        macProgressBar.wantsLayer = true
        macProgressBar.layer?.cornerRadius = 0
        macProgressBar.layer?.backgroundColor = NSColor.white.cgColor
        macProgressBar.layer?.borderWidth = 1.5
        macProgressBar.layer?.borderColor = kBorder.cgColor
        macCard.addSubview(macProgressBar)

        macProgressFill.wantsLayer = true
        macProgressFill.layer?.backgroundColor = kAccent.cgColor
        macProgressBar.addSubview(macProgressFill)

        // Bluetooth Header
        btHeaderLabel.stringValue = "BLUETOOTH DEVICES"
        btHeaderLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        btHeaderLabel.textColor = kDim
        btHeaderLabel.isEditable = false; btHeaderLabel.isBordered = false; btHeaderLabel.backgroundColor = .clear
        addSubview(btHeaderLabel)

        addSubview(btListContainer)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height

        macCard.frame = NSRect(x: 12, y: h - 100, width: w - 24, height: 88)
        macPctLabel.frame = NSRect(x: 12, y: 40, width: 120, height: 38)
        macStatusLabel.frame = NSRect(x: w - 136, y: 46, width: 98, height: 26)
        macProgressBar.frame = NSRect(x: 12, y: 14, width: w - 48, height: 18)

        btHeaderLabel.frame = NSRect(x: 14, y: h - 124, width: w - 28, height: 16)
        btListContainer.frame = NSRect(x: 12, y: 12, width: w - 24, height: h - 142)

        updateBattery()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.updateBattery()
            }
        }
    }

    private func updateBattery() {
        let (pct, charging) = getMacBatteryInfo()

        macPctLabel.stringValue = "\(pct)%"
        if charging {
            macStatusLabel.isHidden = false
            macStatusLabel.stringValue = "⚡ CHARGING"
        } else {
            macStatusLabel.isHidden = true
        }

        let fillW = (macProgressBar.bounds.width) * (CGFloat(pct) / 100.0)
        macProgressFill.frame = NSRect(x: 0, y: 0, width: fillW, height: macProgressBar.bounds.height)

        fetchBTDevicesAsync()
    }

    private func getMacBatteryInfo() -> (percent: Int, isCharging: Bool) {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        proc.arguments = ["-g", "batt"]
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let str = String(data: data, encoding: .utf8) ?? ""

        var pct = 100
        var charging = false

        if let range = str.range(of: "(\\d+)%", options: .regularExpression) {
            let numStr = str[range].replacingOccurrences(of: "%", with: "")
            pct = Int(numStr) ?? 100
        }
        if str.contains("AC Power") || (str.contains("charging") && !str.contains("discharging")) {
            charging = true
        }
        return (pct, charging)
    }

    private func fetchBTDevicesAsync() {
        guard !isFetching else { return }
        isFetching = true

        DispatchQueue.global(qos: .background).async { [weak self] in
            let devices = self?.getBTDevicesBackground() ?? []
            DispatchQueue.main.async {
                self?.isFetching = false
                self?.renderBTDevices(devices)
            }
        }
    }

    private func getBTDevicesBackground() -> [(name: String, battery: Int?)] {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        proc.arguments = ["SPBluetoothDataType"]
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let str = String(data: data, encoding: .utf8) ?? ""

        var list: [(name: String, battery: Int?)] = []

        if let connRange = str.range(of: "Connected:") {
            let sub = str[connRange.upperBound...]
            let connSection: String
            if let notConnRange = sub.range(of: "Not Connected:") {
                connSection = String(sub[..<notConnRange.lowerBound])
            } else {
                connSection = String(sub)
            }

            let lines = connSection.components(separatedBy: .newlines)
            var currentName: String?

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("          ") && !line.hasPrefix("              ") {
                    let name = trimmed.replacingOccurrences(of: ":", with: "")
                    if !name.isEmpty { currentName = name }
                } else if line.contains("Battery Level:"), let name = currentName {
                    if let range = line.range(of: "(\\d+)%", options: .regularExpression) {
                        let numStr = line[range].replacingOccurrences(of: "%", with: "")
                        let pct = Int(numStr)
                        list.append((name: name, battery: pct))
                        currentName = nil
                    }
                }
            }
            if let name = currentName, !list.contains(where: { $0.name == name }) {
                list.append((name: name, battery: nil))
            }
        }
        return list
    }

    private func renderBTDevices(_ devices: [(name: String, battery: Int?)]) {
        let changed = devices.map { "\($0.name):\($0.battery ?? -1)" } != lastDevices.map { "\($0.name):\($0.battery ?? -1)" }
        guard changed || btListContainer.subviews.isEmpty else { return }
        lastDevices = devices

        for sub in btListContainer.subviews { sub.removeFromSuperview() }

        if devices.isEmpty {
            let noDevLabel = NSTextField(labelWithString: "No Bluetooth devices connected")
            noDevLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            noDevLabel.textColor = kDim
            noDevLabel.alignment = .center
            noDevLabel.frame = NSRect(x: 0, y: (btListContainer.bounds.height - 20)/2, width: btListContainer.bounds.width, height: 20)
            btListContainer.addSubview(noDevLabel)
            return
        }

        let containerW = btListContainer.bounds.width
        let itemH: CGFloat = 40
        let gap: CGFloat = 6

        for (i, dev) in devices.enumerated() {
            let y = btListContainer.bounds.height - CGFloat(i + 1) * (itemH + gap)
            let devCard = NSView(frame: NSRect(x: 0, y: y, width: containerW, height: itemH))
            devCard.wantsLayer = true
            devCard.layer?.cornerRadius = 0
            devCard.layer?.backgroundColor = kCard.cgColor
            devCard.layer?.borderWidth = 1.5
            devCard.layer?.borderColor = kBorder.cgColor

            // Name Label (Centered)
            let nameTF = NSTextField()
            let nameCell = CenteredTextFieldCell(textCell: "🎧 " + dev.name)
            nameCell.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            nameCell.textColor = kText
            nameCell.lineBreakMode = .byTruncatingTail
            nameTF.cell = nameCell
            nameTF.stringValue = "🎧 " + dev.name
            nameTF.isEditable = false; nameTF.isBordered = false; nameTF.backgroundColor = .clear
            nameTF.frame = NSRect(x: 10, y: 8, width: containerW - 74, height: 24)
            devCard.addSubview(nameTF)

            // Battery tag (Centered)
            let batVal = dev.battery ?? 100
            let badgeTF = NSTextField()
            let badgeCell = CenteredTextFieldCell(textCell: "\(batVal)%")
            badgeCell.alignment = .center
            badgeCell.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            badgeCell.textColor = .white
            badgeTF.cell = badgeCell
            badgeTF.stringValue = "\(batVal)%"
            badgeTF.isEditable = false; badgeTF.isBordered = false
            badgeTF.wantsLayer = true
            badgeTF.layer?.cornerRadius = 0
            badgeTF.layer?.backgroundColor = kAccent.cgColor
            badgeTF.layer?.borderWidth = 1.5
            badgeTF.layer?.borderColor = kBorder.cgColor
            badgeTF.frame = NSRect(x: containerW - 60, y: 8, width: 48, height: 24)
            devCard.addSubview(badgeTF)

            btListContainer.addSubview(devCard)
        }
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

    // Dragging
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
        let rect = NSRect(x: 24, y: 50, width: 280, height: 280)
        window = BatteryWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: -1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false
        window.contentView = BatteryView(frame: rect)
        window.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
