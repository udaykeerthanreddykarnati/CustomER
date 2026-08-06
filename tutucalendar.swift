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

class CalendarWindow: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

class CalendarView: NSView {
    private let monthLabel = NSTextField()
    private let gridContainer = NSView()
    private var dragStart: NSPoint = .zero
    private var dragActive = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        renderCalendar()
        listenForThemeChanges()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor

        monthLabel.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        monthLabel.textColor = kText
        monthLabel.isEditable = false; monthLabel.isBordered = false; monthLabel.backgroundColor = .clear
        monthLabel.alignment = .center
        addSubview(monthLabel)

        addSubview(gridContainer)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        monthLabel.frame = NSRect(x: 12, y: h - 38, width: w - 24, height: 24)
        gridContainer.frame = NSRect(x: 12, y: 12, width: w - 24, height: h - 54)
        renderCalendar()
    }

    private func renderCalendar() {
        for sub in gridContainer.subviews { sub.removeFromSuperview() }

        let cal = Calendar.current
        let now = Date()
        let comp = cal.dateComponents([.year, .month, .day], from: now)
        let today = comp.day ?? 1

        let mf = DateFormatter()
        mf.dateFormat = "MMMM yyyy"
        monthLabel.stringValue = mf.string(from: now).uppercased()

        var startComp = comp
        startComp.day = 1
        guard let firstDay = cal.date(from: startComp),
              let range = cal.range(of: .day, in: .month, for: now) else { return }

        let weekday = cal.component(.weekday, from: firstDay) - 1
        let totalDays = range.count

        let gridW = gridContainer.frame.width
        let gridH = gridContainer.frame.height
        let cols = 7
        let cellW = gridW / CGFloat(cols)
        let cellH: CGFloat = 24

        // Weekday Headers
        let days = ["S", "M", "T", "W", "T", "F", "S"]
        for (i, d) in days.enumerated() {
            let label = NSTextField(labelWithString: d)
            label.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            label.textColor = kDim
            label.alignment = .center
            label.isBordered = false; label.backgroundColor = .clear
            label.frame = NSRect(x: CGFloat(i) * cellW, y: gridH - cellH, width: cellW, height: cellH)
            gridContainer.addSubview(label)
        }

        // Render Days Grid
        var dayNum = 1
        var row = 1
        while dayNum <= totalDays {
            for col in 0..<7 {
                if (row == 1 && col < weekday) || dayNum > totalDays {
                    continue
                }

                let y = gridH - cellH - CGFloat(row) * cellH
                let cellView = NSView(frame: NSRect(x: CGFloat(col) * cellW + 1, y: y, width: cellW - 2, height: cellH - 2))
                cellView.wantsLayer = true

                let isToday = (dayNum == today)
                if isToday {
                    cellView.layer?.backgroundColor = kAccent.cgColor
                    cellView.layer?.borderWidth = 1.5
                    cellView.layer?.borderColor = kBorder.cgColor
                }

                let label = NSTextField(labelWithString: "\(dayNum)")
                label.font = NSFont.systemFont(ofSize: 12, weight: isToday ? .bold : .semibold)
                label.textColor = isToday ? NSColor.white : kText
                label.alignment = .center
                label.isBordered = false; label.backgroundColor = .clear
                label.frame = NSRect(x: 0, y: (cellView.bounds.height - 18) / 2, width: cellView.bounds.width, height: 18)
                cellView.addSubview(label)

                gridContainer.addSubview(cellView)
                dayNum += 1
            }
            row += 1
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
        let rect = NSRect(x: 24, y: 350, width: 280, height: 230)
        window = CalendarWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: -1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false
        window.contentView = CalendarView(frame: rect)
        window.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
