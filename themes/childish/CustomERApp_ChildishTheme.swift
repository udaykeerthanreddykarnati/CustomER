import AppKit
import Foundation
import IOKit.pwr_mgt
import IOKit.ps

// MARK: - Global Theme Colors (Bubbly Childish Theme)
var kBg          = NSColor(red: 255/255.0, green: 227/255.0, blue: 241/255.0, alpha: 1.00) // #FFE3F1 Cotton Candy Pink
let kText        = NSColor(red: 255/255.0, green: 79/255.0,  blue: 160/255.0, alpha: 1.00) // #FF4FA0 Bubblegum Pop
let kBlue        = NSColor(red: 255/255.0, green: 79/255.0,  blue: 160/255.0, alpha: 1.00) // #FF4FA0 Bubblegum Pop
let kAccent      = NSColor(red: 255/255.0, green: 79/255.0,  blue: 160/255.0, alpha: 1.00) // #FF4FA0 Bubblegum Pop
let kAddBg       = NSColor(red: 255/255.0, green: 79/255.0,  blue: 160/255.0, alpha: 1.00) // #FF4FA0 Bubblegum Pop
let kDim         = NSColor(red: 140/255.0, green: 107/255.0, blue: 158/255.0, alpha: 1.00) // #8C6B9E Dusty Lavender
let kSurface     = NSColor(red: 255/255.0, green: 246/255.0, blue: 250/255.0, alpha: 1.00) // #FFF6FA Marshmallow Cream
let kBorder      = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.00)            // Solid Black Cartoon Border
let kRadius: CGFloat = 16.0 // Bubbly rounded corners
let kBorderWidth: CGFloat = 2.0 // Thick 2px cartoon outline

func dynamicFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let descriptor = base.fontDescriptor.withDesign(.rounded) {
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
    return base
}

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
        guard let rgb = usingColorSpace(.sRGB) else { return "#FFE3F1" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension NSImage {
    static func downsampledImage(at url: URL, targetSize: NSSize) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let maxDimension = max(targetSize.width, targetSize.height) * 2.0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: targetSize)
    }
}

class ThemeManager {
    static let shared = ThemeManager()
    static let notifName = NSNotification.Name("com.user.CustomER.themeChanged")
    private var iconWorkItem: DispatchWorkItem?

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
            return kBg
        }
        set {
            let hex = newValue.toHex()
            let dict = ["bgHex": hex]
            if let data = try? JSONSerialization.data(withJSONObject: dict) {
                try? data.write(to: themeFileURL)
            }
            DistributedNotificationCenter.default().postNotificationName(
                ThemeManager.notifName, object: nil, userInfo: ["bgHex": hex], deliverImmediately: true
            )
            iconWorkItem?.cancel()
            let item = DispatchWorkItem {
                FolderIconManager.updateDesktopFolderIcons(bgColor: newValue)
            }
            iconWorkItem = item
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: item)
        }
    }
}

class FolderIconManager {
    static func updateDesktopFolderIcons(bgColor: NSColor) {
        DispatchQueue.global(qos: .userInitiated).async {
            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            guard let files = try? FileManager.default.contentsOfDirectory(at: desktop, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            
            for url in files {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue, url.pathExtension != "app" {
                    let icon = generateFolderIcon(folderName: url.lastPathComponent, bgColor: bgColor, accentColor: kAccent)
                    NSWorkspace.shared.setIcon(icon, forFile: url.path, options: [])
                }
            }
        }
    }

    private static func generateFolderIcon(folderName: String, bgColor: NSColor, accentColor: NSColor) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let img = NSImage(size: size)
        img.lockFocus()
        
        let tabPath = NSBezierPath(roundedRect: NSRect(x: 72, y: 310, width: 180, height: 90), xRadius: 18, yRadius: 18)
        bgColor.setFill(); tabPath.fill()
        NSColor.black.setStroke(); tabPath.lineWidth = 10; tabPath.stroke()
        
        let bodyPath = NSBezierPath(roundedRect: NSRect(x: 56, y: 96, width: 400, height: 260), xRadius: 28, yRadius: 28)
        bgColor.setFill(); bodyPath.fill()
        NSColor.black.setStroke(); bodyPath.lineWidth = 10; bodyPath.stroke()
        
        let bannerPath = NSBezierPath(roundedRect: NSRect(x: 56, y: 300, width: 400, height: 56), xRadius: 14, yRadius: 14)
        accentColor.setFill(); bannerPath.fill()
        NSColor.black.setStroke(); bannerPath.lineWidth = 8; bannerPath.stroke()
        
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42, weight: .black),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let textRect = NSRect(x: 72, y: 180, width: 368, height: 60)
        folderName.draw(in: textRect, withAttributes: attrs)
        
        img.unlockFocus()
        return img
    }
}

class PositionManager {
    static let shared = PositionManager()
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("tututodoWidget")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("positions.json")
    }()
    private var posDict: [String: [CGFloat]] = [:]
    private init() { load() }
    func load() {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: [CGFloat]].self, from: data) else { return }
        posDict = dict
    }
    func savePosition(key: String, origin: NSPoint) {
        posDict[key] = [origin.x, origin.y]
        if let data = try? JSONEncoder().encode(posDict) { try? data.write(to: url) }
    }
    func getPosition(key: String, defaultOrigin: NSPoint) -> NSPoint {
        if let arr = posDict[key], arr.count == 2 { return NSPoint(x: arr[0], y: arr[1]) }
        return defaultOrigin
    }
}

class CenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let newRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        let heightDelta = newRect.height - textSize.height
        if heightDelta > 0 {
            return NSRect(x: newRect.origin.x, y: newRect.origin.y + (heightDelta / 2.0), width: newRect.width, height: textSize.height)
        }
        return newRect
    }
}

class MasterWidgetWindow: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

func runScript(_ code: String) -> String {
    var err: NSDictionary?
    if let sc = NSAppleScript(source: code) {
        return sc.executeAndReturnError(&err).stringValue ?? ""
    }
    return ""
}

func shellRun(_ command: String) -> String {
    let proc = Process(), pipe = Pipe()
    proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
    proc.arguments = ["-c", "export PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"; \(command)"]
    proc.standardOutput = pipe; proc.standardError = pipe
    try? proc.run(); proc.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

// MARK: - 1. REMINDERS WIDGET (tututodo)
struct Reminder: Codable {
    var id: UUID; var title: String; var isCompleted: Bool; var createdAt: Date
    init(title: String) { self.id = UUID(); self.title = title; self.isCompleted = false; self.createdAt = Date() }
}

class ReminderStore {
    static let shared = ReminderStore()
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("tututodoWidget")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("reminders.json")
    }()
    private(set) var items: [Reminder] = []
    private init() { load() }
    func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Reminder].self, from: data) else { return }
        items = decoded
    }
    func save() { try? JSONEncoder().encode(items).write(to: url) }
    func add(_ r: Reminder) { items.append(r); save() }
    func toggle(id: UUID) { if let i = items.firstIndex(where: { $0.id == id }) { items[i].isCompleted.toggle(); save() } }
    func delete(id: UUID) { items.removeAll { $0.id == id }; save() }
    func clearCompleted() { items.removeAll { $0.isCompleted }; save() }
    func updateTitle(id: UUID, title: String) { if let i = items.firstIndex(where: { $0.id == id }) { items[i].title = title; save() } }
}

class ReminderRowView: NSView {
    var reminder: Reminder
    var onToggle: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onEdit:   ((UUID, String) -> Void)?

    private let check = NSButton()
    private let label = NSTextField()
    private let del   = NSButton()

    init(_ reminder: Reminder) {
        self.reminder = reminder
        super.init(frame: .zero); build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius / 2; layer?.backgroundColor = kSurface.cgColor
        layer?.borderWidth = 0.0

        check.isBordered = false; check.bezelStyle = .regularSquare; check.setButtonType(.momentaryChange)
        check.wantsLayer = true; check.layer?.cornerRadius = 4; check.layer?.borderWidth = kBorderWidth; check.layer?.borderColor = kBorder.cgColor
        check.layer?.backgroundColor = reminder.isCompleted ? kBorder.cgColor : NSColor.clear.cgColor
        if reminder.isCompleted {
            check.attributedTitle = NSAttributedString(string: "✓", attributes: [.font: dynamicFont(size: 10, weight: .bold), .foregroundColor: NSColor.white])
        } else { check.title = "" }
        check.target = self; check.action = #selector(toggleTapped); addSubview(check)

        label.isBordered = false; label.backgroundColor = .clear; label.isEditable = false
        label.font = dynamicFont(size: 13, weight: .medium); label.lineBreakMode = .byTruncatingTail
        if reminder.isCompleted {
            let s = NSMutableAttributedString(string: reminder.title)
            let r = NSRange(location: 0, length: reminder.title.count)
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            s.addAttribute(.foregroundColor, value: kDim, range: r)
            label.attributedStringValue = s
        } else {
            label.stringValue = reminder.title
            label.textColor = kText
        }
        let dclick = NSClickGestureRecognizer(target: self, action: #selector(editTapped))
        dclick.numberOfClicksRequired = 2
        label.addGestureRecognizer(dclick)
        addSubview(label)

        del.title = "✕"; del.font = dynamicFont(size: 10); del.isBordered = false
        del.contentTintColor = kDim; del.target = self; del.action = #selector(deleteTapped); del.alphaValue = 0
        addSubview(del)

        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    override func layout() {
        super.layout()
        let h = bounds.height, w = bounds.width
        check.frame = NSRect(x: 10, y: (h-18)/2, width: 18, height: 18)
        del.frame   = NSRect(x: w-26, y: (h-18)/2, width: 20, height: 18)
        label.frame = NSRect(x: 36, y: (h-18)/2, width: w - 66, height: 18)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10; del.animator().alphaValue = 0.9; layer?.borderWidth = kBorderWidth
            layer?.borderColor = kBorder.cgColor; layer?.backgroundColor = kSurface.withAlphaComponent(0.85).cgColor
        }
    }
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10; del.animator().alphaValue = 0; layer?.borderWidth = 0.0; layer?.backgroundColor = kSurface.cgColor
        }
    }

    @objc func toggleTapped() { onToggle?(reminder.id) }
    @objc func deleteTapped()  { onDelete?(reminder.id) }
    @objc func editTapped() {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "Edit todo"
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        tf.stringValue = reminder.title
        alert.accessoryView = tf
        alert.beginSheetModal(for: window) { [weak self] r in
            guard let self = self else { return }
            if r == .alertFirstButtonReturn {
                let t = tf.stringValue.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { self.onEdit?(self.reminder.id, t) }
            }
        }
        DispatchQueue.main.async { tf.becomeFirstResponder() }
    }
}

class AddPanel: NSView {
    var onAdd:    ((Reminder) -> Void)?
    var onCancel: (() -> Void)?

    private let titleField = NSTextField()
    private let addBtn     = NSButton()
    private let cancelBtn  = NSButton()

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.backgroundColor = kBg.cgColor
        layer?.borderWidth = kBorderWidth; layer?.borderColor = kBorder.cgColor

        titleField.drawsBackground = true; titleField.backgroundColor = kSurface; titleField.textColor = kText
        titleField.font = dynamicFont(size: 14, weight: .bold); titleField.focusRingType = .none
        titleField.isBordered = true; titleField.bezelStyle = .squareBezel; titleField.wantsLayer = true
        titleField.layer?.cornerRadius = kRadius / 2; titleField.layer?.borderWidth = kBorderWidth; titleField.layer?.borderColor = kBorder.cgColor

        let pAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: kDim, .font: dynamicFont(size: 13, weight: .medium)]
        titleField.placeholderAttributedString = NSAttributedString(string: "What to do?", attributes: pAttrs)
        addSubview(titleField)

        styleBtn(addBtn, primary: true, title: "Add")
        addBtn.target = self; addBtn.action = #selector(addTapped); addSubview(addBtn)

        styleBtn(cancelBtn, primary: false, title: "Cancel")
        cancelBtn.target = self; cancelBtn.action = #selector(cancelTapped); addSubview(cancelBtn)
    }

    private func styleBtn(_ b: NSButton, primary: Bool, title: String) {
        b.title = title; b.isBordered = false; b.wantsLayer = true; b.layer?.cornerRadius = kRadius / 2
        b.layer?.borderWidth = kBorderWidth; b.layer?.borderColor = kBorder.cgColor; b.font = dynamicFont(size: 12, weight: .bold)
        b.layer?.backgroundColor = primary ? kAddBg.cgColor : kSurface.cgColor
        b.contentTintColor = primary ? .white : kText
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleField.frame  = NSRect(x: 14, y: h - 54, width: w - 28, height: 34)
        cancelBtn.frame   = NSRect(x: 14, y: 14, width: (w - 36) / 2, height: 32)
        addBtn.frame      = NSRect(x: 22 + (w - 36) / 2, y: 14, width: (w - 36) / 2, height: 32)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { self.titleField.becomeFirstResponder() }
    }

    func clear() { titleField.stringValue = "" }

    @objc func addTapped() {
        let t = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else {
            titleField.layer?.borderColor = NSColor.red.cgColor; titleField.layer?.borderWidth = 2; return
        }
        onAdd?(Reminder(title: t))
    }
    @objc func cancelTapped() { onCancel?() }
}

class TodoView: NSView {
    let widgetKey = "reminders"
    private var rows: [UUID: ReminderRowView] = [:]
    private var filterIdx = 0
    private var panelShown = false

    private var dragStart: NSPoint = .zero, dragActive = false

    private let scroll       = NSScrollView()
    private let list         = NSView()
    private let panel        = AddPanel()
    private let header       = NSTextField()
    private let badge        = NSTextField()
    private let addBtn       = NSButton()
    private let clearBtn     = NSButton()
    private let activeTabBtn = NSButton()
    private let doneTabBtn   = NSButton()

    override init(frame: NSRect) { super.init(frame: frame); build(); reload() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.borderWidth = kBorderWidth; layer?.borderColor = kBorder.cgColor
        layer?.backgroundColor = kBg.cgColor

        header.stringValue = "tututodo"
        header.font = dynamicFont(size: 17, weight: .bold); header.textColor = kText
        header.isEditable = false; header.isBordered = false; header.backgroundColor = .clear
        addSubview(header)

        badge.font = dynamicFont(size: 10, weight: .bold); badge.textColor = kText; badge.alignment = .center
        badge.isEditable = false; badge.isBordered = false; badge.backgroundColor = .clear; badge.wantsLayer = true
        badge.layer?.cornerRadius = kRadius / 2; badge.layer?.borderWidth = kBorderWidth; badge.layer?.borderColor = kBorder.cgColor
        badge.layer?.backgroundColor = kSurface.cgColor
        addSubview(badge)

        activeTabBtn.target = self; activeTabBtn.action = #selector(activeTabTapped); addSubview(activeTabBtn)
        doneTabBtn.target   = self; doneTabBtn.action   = #selector(doneTabTapped); addSubview(doneTabBtn)
        updateTabStyles()

        addBtn.title = "+ Add"; addBtn.font = dynamicFont(size: 12, weight: .bold); addBtn.isBordered = false
        addBtn.wantsLayer = true; addBtn.layer?.cornerRadius = kRadius / 2; addBtn.layer?.borderWidth = kBorderWidth; addBtn.layer?.borderColor = kBorder.cgColor
        addBtn.layer?.backgroundColor = kAddBg.cgColor; addBtn.contentTintColor = .white; addBtn.target = self; addBtn.action = #selector(showPanel); addSubview(addBtn)

        clearBtn.title = "Clear Done"; clearBtn.font = dynamicFont(size: 11, weight: .medium)
        clearBtn.isBordered = false; clearBtn.contentTintColor = kText; clearBtn.target = self; clearBtn.action = #selector(clearDone); addSubview(clearBtn)

        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false; scroll.documentView = list; addSubview(scroll)

        panel.isHidden = true; panel.alphaValue = 0
        panel.onAdd    = { [weak self] r in self?.doAdd(r) }
        panel.onCancel = { [weak self] in self?.hidePanel() }
        addSubview(panel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        header.frame    = NSRect(x: 16, y: h - 42, width: 120, height: 24)
        badge.frame     = NSRect(x: 140, y: h - 37, width: 26, height: 18)
        addBtn.frame    = NSRect(x: w - 78, y: h - 40, width: 64, height: 24)

        let tabW = (w - 28) / 2
        activeTabBtn.frame = NSRect(x: 14, y: h - 72, width: tabW, height: 24)
        doneTabBtn.frame   = NSRect(x: 14 + tabW, y: h - 72, width: tabW, height: 24)

        clearBtn.frame  = NSRect(x: 14, y: 10, width: 82, height: 18)
        scroll.frame    = NSRect(x: 10, y: 34, width: w - 20, height: h - 112)
        panel.frame     = NSRect(x: 10, y: h/2 - 78, width: w - 20, height: 156)
        relayoutList()
    }

    @objc func activeTabTapped() { filterIdx = 0; updateTabStyles(); reload() }
    @objc func doneTabTapped()   { filterIdx = 1; updateTabStyles(); reload() }

    private func updateTabStyles() {
        styleTabButton(activeTabBtn, title: "Active", isActive: filterIdx == 0)
        styleTabButton(doneTabBtn, title: "Done", isActive: filterIdx == 1)
    }
    private func styleTabButton(_ btn: NSButton, title: String, isActive: Bool) {
        btn.isBordered = false; btn.wantsLayer = true; btn.layer?.cornerRadius = kRadius / 2
        btn.layer?.borderWidth = kBorderWidth; btn.layer?.borderColor = kBorder.cgColor
        btn.layer?.backgroundColor = isActive ? kSurface.cgColor : NSColor.clear.cgColor
        btn.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: dynamicFont(size: 11, weight: isActive ? .bold : .medium),
            .foregroundColor: kText
        ])
    }

    private func filtered() -> [Reminder] {
        return filterIdx == 1 ? ReminderStore.shared.items.filter { $0.isCompleted } : ReminderStore.shared.items.filter { !$0.isCompleted }
    }

    func reload() {
        let store = ReminderStore.shared
        let pending = store.items.filter { !$0.isCompleted }.count
        badge.stringValue = "\(pending)"
        badge.isHidden = pending == 0

        let filterList = filtered()
        let currentIDs = Set(filterList.map { $0.id })
        for (id, v) in rows where !currentIDs.contains(id) { v.removeFromSuperview(); rows.removeValue(forKey: id) }

        for r in filterList {
            if let existing = rows[r.id] {
                existing.reminder = r
            } else {
                let row = ReminderRowView(r)
                row.onToggle = { [weak self] id in self?.doToggle(id) }
                row.onDelete = { [weak self] id in self?.doDelete(id) }
                row.onEdit   = { [weak self] id, t in self?.doEdit(id, t) }
                list.addSubview(row)
                rows[r.id] = row
            }
        }
        relayoutList()
    }

    private func relayoutList() {
        let filterList = filtered()
        let rowH: CGFloat = 34, gap: CGFloat = 4, totalH = CGFloat(filterList.count) * (rowH + gap)
        let w = scroll.bounds.width
        list.frame = NSRect(x: 0, y: 0, width: w, height: max(totalH, scroll.bounds.height))

        for (i, r) in filterList.enumerated() {
            if let row = rows[r.id] {
                let y = list.frame.height - CGFloat(i + 1) * (rowH + gap)
                row.frame = NSRect(x: 0, y: y, width: w, height: rowH)
            }
        }
    }

    @objc func showPanel() {
        guard !panelShown else { return }
        panelShown = true; panel.clear(); panel.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.18; panel.animator().alphaValue = 1 }
    }

    func hidePanel() {
        guard panelShown else { return }
        panelShown = false
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.15; panel.animator().alphaValue = 0 }, completionHandler: { self.panel.isHidden = true })
    }

    private func doAdd(_ r: Reminder) { ReminderStore.shared.add(r); hidePanel(); reload() }
    private func doToggle(_ id: UUID) { ReminderStore.shared.toggle(id: id); reload() }
    private func doDelete(_ id: UUID) { ReminderStore.shared.delete(id: id); reload() }
    private func doEdit(_ id: UUID, _ title: String) { ReminderStore.shared.updateTitle(id: id, title: title); reload() }
    @objc func clearDone() { ReminderStore.shared.clearCompleted(); reload() }

    override func mouseDown(with event: NSEvent) { dragStart = event.locationInWindow; dragActive = true; window?.makeKey() }
    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { return }
        let c = event.locationInWindow
        w.setFrameOrigin(NSPoint(x: w.frame.origin.x + c.x - dragStart.x, y: w.frame.origin.y + c.y - dragStart.y))
    }
    override func mouseUp(with event: NSEvent) {
        dragActive = false
        if let w = window { PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin) }
    }
}

// MARK: - MASTER APP DELEGATE
class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        FolderIconManager.updateDesktopFolderIcons(bgColor: kBg)

        let defaultTodoRect = NSRect(x: 24, y: 600, width: 280, height: 440)
        let todoOrigin = PositionManager.shared.getPosition(key: "reminders", defaultOrigin: defaultTodoRect.origin)
        addWindow(rect: NSRect(origin: todoOrigin, size: defaultTodoRect.size), view: TodoView(frame: NSRect(origin: todoOrigin, size: defaultTodoRect.size)))
    }

    private func addWindow(rect: NSRect, view: NSView) {
        let win = MasterWidgetWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false; win.backgroundColor = .clear; win.level = NSWindow.Level(rawValue: -1)
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]; win.hasShadow = false
        win.contentView = view; win.makeKeyAndOrderFront(nil); windows.append(win)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
