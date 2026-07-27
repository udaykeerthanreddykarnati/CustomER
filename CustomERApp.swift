import AppKit
import Foundation
import IOKit.pwr_mgt
import IOKit.ps

// MARK: - Modern Dark Glass Theme Tokens
var kBg          = NSColor(red: 9/255.0,   green: 13/255.0,  blue: 22/255.0,  alpha: 1.00) // #090D16 Deep Cyber Midnight
let kBlue        = NSColor(red: 99/255.0,  green: 102/255.0, blue: 241/255.0, alpha: 1.00) // #6366F1 Electric Indigo
let kText        = NSColor(red: 241/255.0, green: 245/255.0, blue: 249/255.0, alpha: 1.00) // #F1F5F9 Crystal White
let kAccent      = NSColor(red: 139/255.0, green: 92/255.0,  blue: 246/255.0, alpha: 1.00) // #8B5CF6 Violet Glow
let kAddBg       = NSColor(red: 16/255.0,  green: 185/255.0, blue: 129/255.0, alpha: 1.00) // #10B981 Emerald Green
let kDim         = NSColor(red: 100/255.0, green: 116/255.0, blue: 139/255.0, alpha: 1.00) // #64748B Steel Slate
let kSurface     = NSColor(red: 21/255.0,  green: 29/255.0,  blue: 42/255.0,  alpha: 1.00) // #151D2A Frosted Glass Card
let kBorder      = NSColor(red: 38/255.0,  green: 51/255.0,  blue: 70/255.0,  alpha: 1.00) // #263346 Subtle Glass Border
let kRadius: CGFloat = 24.0 // Ultra-smooth modern pill corners

func modernFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
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
        guard let rgb = usingColorSpace(.sRGB) else { return "#090D16" }
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
            
            let accent = NSColor(red: 99/255.0, green: 102/255.0, blue: 241/255.0, alpha: 1.0)
            
            for url in files {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue, url.pathExtension != "app" {
                    let icon = generateFolderIcon(folderName: url.lastPathComponent, bgColor: bgColor, accentColor: accent)
                    NSWorkspace.shared.setIcon(icon, forFile: url.path, options: [])
                }
            }
        }
    }

    private static func generateFolderIcon(folderName: String, bgColor: NSColor, accentColor: NSColor) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let img = NSImage(size: size)
        img.lockFocus()
        
        // Draw back tab
        let tabPath = NSBezierPath(roundedRect: NSRect(x: 72, y: 310, width: 180, height: 90), xRadius: 24, yRadius: 24)
        bgColor.setFill()
        tabPath.fill()
        accentColor.setStroke()
        tabPath.lineWidth = 6
        tabPath.stroke()
        
        // Draw front folder body
        let bodyPath = NSBezierPath(roundedRect: NSRect(x: 56, y: 96, width: 400, height: 260), xRadius: 32, yRadius: 32)
        bgColor.setFill()
        bodyPath.fill()
        accentColor.setStroke()
        bodyPath.lineWidth = 6
        bodyPath.stroke()
        
        // Draw top accent banner
        let bannerPath = NSBezierPath(roundedRect: NSRect(x: 56, y: 300, width: 400, height: 56), xRadius: 16, yRadius: 16)
        accentColor.setFill()
        bannerPath.fill()

        // Draw Folder Title text on front
        let attr: [NSAttributedString.Key: Any] = [
            .font: modernFont(size: 30, weight: .black),
            .foregroundColor: NSColor.white
        ]
        let titleStr = folderName.uppercased()
        let strSize = titleStr.size(withAttributes: attr)
        let textRect = NSRect(x: max(64, 56 + (400 - strSize.width) / 2.0), y: 170, width: min(380, strSize.width), height: strSize.height)
        titleStr.draw(in: textRect, withAttributes: attr)

        img.unlockFocus()
        return img
    }
}

// MARK: - PERSISTENT WIDGET POSITION MANAGER
class PositionManager {
    static let shared = PositionManager()
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CustomER", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("positions.json")
    }()
    private var dict: [String: [CGFloat]] = [:]

    private init() { load() }

    func load() {
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: [CGFloat]] {
            dict = json
        }
    }

    func savePosition(key: String, origin: NSPoint) {
        dict[key] = [origin.x, origin.y]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            try? data.write(to: url)
        }
    }

    func getPosition(key: String, defaultOrigin: NSPoint) -> NSPoint {
        if let arr = dict[key], arr.count >= 2 {
            return NSPoint(x: arr[0], y: arr[1])
        }
        return defaultOrigin
    }
}

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

// MARK: - 1. REMINDERS WIDGET (Modern Dark Glass)
struct Reminder: Codable {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var createdAt: Date
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
        wantsLayer = true; layer?.cornerRadius = 14.0; layer?.backgroundColor = kSurface.cgColor
        layer?.borderWidth = 1.0; layer?.borderColor = kBorder.cgColor

        check.isBordered = false; check.bezelStyle = .regularSquare; check.setButtonType(.momentaryChange)
        check.wantsLayer = true; check.layer?.cornerRadius = 9.0; check.layer?.borderWidth = 1.5; check.layer?.borderColor = kBlue.cgColor
        check.layer?.backgroundColor = reminder.isCompleted ? kBlue.cgColor : NSColor.clear.cgColor
        if reminder.isCompleted {
            check.attributedTitle = NSAttributedString(string: "✓", attributes: [.font: modernFont(size: 11, weight: .bold), .foregroundColor: NSColor.white])
        } else { check.title = "" }
        check.target = self; check.action = #selector(toggleTapped); addSubview(check)

        label.isBordered = false; label.backgroundColor = .clear; label.isEditable = false
        label.font = modernFont(size: 13, weight: .medium); label.lineBreakMode = .byTruncatingTail
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

        del.title = "✕"; del.font = modernFont(size: 11, weight: .bold); del.isBordered = false
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
            ctx.duration = 0.10; del.animator().alphaValue = 0.9; layer?.borderColor = kBlue.cgColor
        }
    }
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10; del.animator().alphaValue = 0; layer?.borderColor = kBorder.cgColor
        }
    }

    @objc func toggleTapped() { onToggle?(reminder.id) }
    @objc func deleteTapped()  { onDelete?(reminder.id) }
    @objc func editTapped() {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "Edit task"
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
        layer?.borderWidth = 1.5; layer?.borderColor = kBlue.cgColor

        titleField.drawsBackground = true; titleField.backgroundColor = kSurface; titleField.textColor = kText
        titleField.font = modernFont(size: 13, weight: .bold); titleField.focusRingType = .none
        titleField.isBordered = false; titleField.wantsLayer = true
        titleField.layer?.cornerRadius = 14; titleField.layer?.borderWidth = 1; titleField.layer?.borderColor = kBorder.cgColor

        let pAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: kDim, .font: modernFont(size: 13, weight: .medium)]
        titleField.placeholderAttributedString = NSAttributedString(string: "What's on your mind?", attributes: pAttrs)
        addSubview(titleField)

        styleBtn(addBtn, primary: true, title: "Add Task")
        addBtn.target = self; addBtn.action = #selector(addTapped); addSubview(addBtn)

        styleBtn(cancelBtn, primary: false, title: "Cancel")
        cancelBtn.target = self; cancelBtn.action = #selector(cancelTapped); addSubview(cancelBtn)
    }

    private func styleBtn(_ b: NSButton, primary: Bool, title: String) {
        b.title = title; b.isBordered = false; b.wantsLayer = true; b.layer?.cornerRadius = 14
        b.layer?.borderWidth = 1; b.layer?.borderColor = kBorder.cgColor; b.font = modernFont(size: 12, weight: .bold)
        b.layer?.backgroundColor = primary ? kBlue.cgColor : kSurface.cgColor
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
            titleField.layer?.borderColor = NSColor.red.cgColor; titleField.layer?.borderWidth = 1.5; return
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

    private var dragStart: NSPoint = .zero
    private var dragActive = false

    private let scroll       = NSScrollView()
    private let list         = NSView()
    private let panel        = AddPanel()
    private let header       = NSTextField()
    private let badge        = NSTextField()
    private let addBtn       = NSButton()
    private let clearBtn     = NSButton()
    private let activeTabBtn = NSButton()
    private let doneTabBtn   = NSButton()

    override init(frame: NSRect) { super.init(frame: frame); build(); reload(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 1.5; layer?.borderColor = kBorder.cgColor

        header.stringValue = "TASKS"
        header.font = modernFont(size: 15, weight: .black); header.textColor = kText
        header.isEditable = false; header.isBordered = false; header.backgroundColor = .clear
        addSubview(header)

        let badgeCell = CenteredTextFieldCell(textCell: "0")
        badgeCell.alignment = .center; badgeCell.font = modernFont(size: 10, weight: .bold); badgeCell.textColor = .white
        badge.cell = badgeCell; badge.isEditable = false; badge.isBordered = false; badge.backgroundColor = .clear; badge.wantsLayer = true
        badge.layer?.cornerRadius = 10; badge.layer?.backgroundColor = kBlue.cgColor
        addSubview(badge)

        activeTabBtn.target = self; activeTabBtn.action = #selector(activeTabTapped); addSubview(activeTabBtn)
        doneTabBtn.target   = self; doneTabBtn.action   = #selector(doneTabTapped); addSubview(doneTabBtn)
        updateTabStyles()

        addBtn.title = "+ Add"; addBtn.font = modernFont(size: 11, weight: .bold); addBtn.isBordered = false
        addBtn.wantsLayer = true; addBtn.layer?.cornerRadius = 12; addBtn.layer?.backgroundColor = kBlue.cgColor
        addBtn.contentTintColor = .white; addBtn.target = self; addBtn.action = #selector(showPanel); addSubview(addBtn)

        clearBtn.title = "Clear Done"; clearBtn.font = modernFont(size: 11, weight: .bold)
        clearBtn.isBordered = false; clearBtn.contentTintColor = kDim; clearBtn.target = self; clearBtn.action = #selector(clearDone); addSubview(clearBtn)

        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false; scroll.documentView = list; addSubview(scroll)

        panel.isHidden = true; panel.alphaValue = 0
        panel.onAdd    = { [weak self] r in self?.doAdd(r) }
        panel.onCancel = { [weak self] in self?.hidePanel() }
        addSubview(panel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        header.frame    = NSRect(x: 16, y: h - 42, width: 100, height: 24)
        badge.frame     = NSRect(x: 100, y: h - 39, width: 24, height: 18)
        addBtn.frame    = NSRect(x: w - 74, y: h - 40, width: 60, height: 24)

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
        btn.isBordered = false; btn.wantsLayer = true; btn.layer?.cornerRadius = 12
        btn.layer?.borderWidth = isActive ? 1.0 : 0; btn.layer?.borderColor = kBorder.cgColor
        btn.layer?.backgroundColor = isActive ? kSurface.cgColor : NSColor.clear.cgColor
        btn.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: modernFont(size: 11, weight: isActive ? .bold : .medium),
            .foregroundColor: isActive ? kText : kDim
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
        let itemH: CGFloat = 38, gap: CGFloat = 6
        let totalH = max(scroll.bounds.height, CGFloat(filterList.count) * (itemH + gap))
        list.frame = NSRect(x: 0, y: 0, width: scroll.bounds.width, height: totalH)

        for (i, r) in filterList.enumerated() {
            if let row = rows[r.id] {
                let y = totalH - CGFloat(i + 1) * (itemH + gap)
                row.frame = NSRect(x: 0, y: y, width: list.bounds.width, height: itemH)
            }
        }
    }

    @objc func showPanel() {
        guard !panelShown else { return }
        panelShown = true; panel.clear(); panel.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.15; panel.animator().alphaValue = 1 }
    }
    func hidePanel() {
        guard panelShown else { return }
        panelShown = false
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.15; panel.animator().alphaValue = 0 }) { [weak self] in
            self?.panel.isHidden = true
        }
    }
    func doAdd(_ r: Reminder) { ReminderStore.shared.add(r); hidePanel(); reload() }
    func doToggle(_ id: UUID) { ReminderStore.shared.toggle(id: id); reload() }
    func doDelete(_ id: UUID) { ReminderStore.shared.delete(id: id); reload() }
    func doEdit(_ id: UUID, _ title: String) { ReminderStore.shared.updateTitle(id: id, title: title); reload() }
    @objc func clearDone() { ReminderStore.shared.clearCompleted(); reload() }

    private func listenForThemeChanges() { DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil) }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            CATransaction.commit()
        }
    }

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

// MARK: - 2. MONTHLY CALENDAR WIDGET (Modern Dark Glass)
class CalendarView: NSView {
    let widgetKey = "calendar"
    private let titleLabel = NSTextField()
    private var dayViews: [NSTextField] = []
    private var dragStart: NSPoint = .zero, dragActive = false

    override init(frame: NSRect) { super.init(frame: frame); build(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 1.5; layer?.borderColor = kBorder.cgColor

        titleLabel.font = modernFont(size: 13, weight: .black); titleLabel.textColor = kText
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear; addSubview(titleLabel)

        let headers = ["S", "M", "T", "W", "T", "F", "S"]
        for h in headers {
            let lbl = NSTextField(labelWithString: h); lbl.font = modernFont(size: 10, weight: .bold); lbl.textColor = kDim; lbl.alignment = .center
            addSubview(lbl); dayViews.append(lbl)
        }

        for _ in 0..<35 {
            let lbl = NSTextField(); lbl.font = modernFont(size: 11, weight: .bold); lbl.alignment = .center
            lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear; lbl.wantsLayer = true; lbl.layer?.cornerRadius = 10
            addSubview(lbl); dayViews.append(lbl)
        }
        updateCalendar()
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleLabel.frame = NSRect(x: 14, y: h - 30, width: w - 28, height: 20)
        let gridX: CGFloat = 12, gridY: CGFloat = 10, colW = (w - 24) / 7.0, rowH = (h - 42) / 6.0
        for i in 0..<7 { dayViews[i].frame = NSRect(x: gridX + CGFloat(i) * colW, y: gridY + 5 * rowH, width: colW, height: rowH) }
        for r in 0..<5 {
            for c in 0..<7 {
                let idx = 7 + r * 7 + c
                dayViews[idx].frame = NSRect(x: gridX + CGFloat(c) * colW, y: gridY + CGFloat(4 - r) * rowH, width: colW, height: rowH)
            }
        }
    }

    private func updateCalendar() {
        let cal = Calendar.current, now = Date(), comp = cal.dateComponents([.year, .month, .day], from: now)
        let year = comp.year!, month = comp.month!, today = comp.day!
        let df = DateFormatter(); df.dateFormat = "MMMM yyyy"; titleLabel.stringValue = df.string(from: now).uppercased()

        var fComp = DateComponents(); fComp.year = year; fComp.month = month; fComp.day = 1
        let fDate = cal.date(from: fComp)!, fWeekday = cal.component(.weekday, from: fDate) - 1
        let numDays = cal.range(of: .day, in: .month, for: now)!.count

        for i in 0..<35 {
            let lbl = dayViews[7 + i], dNum = i - fWeekday + 1
            if dNum >= 1 && dNum <= numDays {
                lbl.stringValue = "\(dNum)"
                if dNum == today {
                    lbl.backgroundColor = kBlue; lbl.textColor = .white; lbl.font = modernFont(size: 11, weight: .black)
                } else {
                    lbl.backgroundColor = .clear; lbl.textColor = kText; lbl.font = modernFont(size: 11, weight: .medium)
                }
            } else { lbl.stringValue = ""; lbl.backgroundColor = .clear }
        }
    }

    private func listenForThemeChanges() { DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil) }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            CATransaction.commit()
        }
    }

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

// MARK: - 3. BATTERY & DEVICES WIDGET (Modern Dark Glass)
class BatteryView: NSView {
    let widgetKey = "battery"
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
    private var dragStart: NSPoint = .zero, dragActive = false

    override init(frame: NSRect) { super.init(frame: frame); build(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 1.5; layer?.borderColor = kBorder.cgColor

        macCard.wantsLayer = true; macCard.layer?.cornerRadius = 18; macCard.layer?.backgroundColor = kSurface.cgColor
        macCard.layer?.borderWidth = 1.0; macCard.layer?.borderColor = kBorder.cgColor; addSubview(macCard)

        macPctLabel.font = modernFont(size: 32, weight: .black); macPctLabel.textColor = kText
        macPctLabel.isEditable = false; macPctLabel.isBordered = false; macPctLabel.backgroundColor = .clear; macCard.addSubview(macPctLabel)

        let statusCell = CenteredTextFieldCell(textCell: "")
        statusCell.alignment = .center; statusCell.font = modernFont(size: 10, weight: .bold); statusCell.textColor = .white
        macStatusLabel.cell = statusCell; macStatusLabel.isEditable = false; macStatusLabel.isBordered = false
        macStatusLabel.wantsLayer = true; macStatusLabel.layer?.cornerRadius = 10; macStatusLabel.layer?.backgroundColor = kAccent.cgColor
        macStatusLabel.layer?.borderWidth = 1.0; macStatusLabel.layer?.borderColor = kBorder.cgColor; macCard.addSubview(macStatusLabel)

        macProgressBar.wantsLayer = true; macProgressBar.layer?.cornerRadius = 6; macProgressBar.layer?.backgroundColor = kBg.cgColor
        macProgressBar.layer?.borderWidth = 1.0; macProgressBar.layer?.borderColor = kBorder.cgColor; macCard.addSubview(macProgressBar)

        macProgressFill.wantsLayer = true; macProgressFill.layer?.cornerRadius = 5; macProgressFill.layer?.backgroundColor = kBlue.cgColor; macProgressBar.addSubview(macProgressFill)

        btHeaderLabel.stringValue = "BLUETOOTH DEVICES"
        btHeaderLabel.font = modernFont(size: 10, weight: .bold); btHeaderLabel.textColor = kDim
        btHeaderLabel.isEditable = false; btHeaderLabel.isBordered = false; btHeaderLabel.backgroundColor = .clear; addSubview(btHeaderLabel)

        addSubview(btListContainer)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        macCard.frame = NSRect(x: 12, y: h - 100, width: w - 24, height: 88)
        macPctLabel.frame = NSRect(x: 12, y: 40, width: 120, height: 38)
        macStatusLabel.frame = NSRect(x: w - 136, y: 46, width: 98, height: 26)
        macProgressBar.frame = NSRect(x: 12, y: 14, width: w - 48, height: 14)

        btHeaderLabel.frame = NSRect(x: 14, y: h - 124, width: w - 28, height: 16)
        btListContainer.frame = NSRect(x: 12, y: 12, width: w - 24, height: h - 142)

        updateBattery()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in self?.updateBattery() }
        }
    }

    private func updateBattery() {
        let (pct, charging) = getMacBatteryInfo()
        macPctLabel.stringValue = "\(pct)%"
        if charging {
            macStatusLabel.isHidden = false; macStatusLabel.stringValue = "CHARGING"
        } else {
            macStatusLabel.isHidden = true
        }
        let fillW = (macProgressBar.bounds.width) * (CGFloat(pct) / 100.0)
        macProgressFill.frame = NSRect(x: 0, y: 0, width: fillW, height: macProgressBar.bounds.height)

        fetchBTDevicesAsync()
    }

    private func getMacBatteryInfo() -> (percent: Int, isCharging: Bool) {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for src in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, src).takeUnretainedValue() as? [String: Any] {
                let capacity = info[kIOPSCurrentCapacityKey] as? Int ?? 100
                let isCharging = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                return (capacity, isCharging)
            }
        }
        return (100, false)
    }

    private func fetchBTDevicesAsync() {
        guard !isFetching else { return }
        isFetching = true
        DispatchQueue.global(qos: .background).async { [weak self] in
            let devices = self?.getBTDevicesBackground() ?? []
            DispatchQueue.main.async { self?.isFetching = false; self?.renderBTDevices(devices) }
        }
    }

    private func getBTDevicesBackground() -> [(name: String, battery: Int?)] {
        let pipe = Pipe(), proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        proc.arguments = ["SPBluetoothDataType"]; proc.standardOutput = pipe
        try? proc.run(); proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let str = String(data: data, encoding: .utf8) ?? ""
        var list: [(name: String, battery: Int?)] = []

        if let connRange = str.range(of: "Connected:") {
            let sub = str[connRange.upperBound...]
            let connSection: String
            if let notConnRange = sub.range(of: "Not Connected:") { connSection = String(sub[..<notConnRange.lowerBound]) }
            else { connSection = String(sub) }

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
                        list.append((name: name, battery: Int(numStr)))
                        currentName = nil
                    }
                }
            }
            if let name = currentName, !list.contains(where: { $0.name == name }) { list.append((name: name, battery: nil)) }
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
            noDevLabel.font = modernFont(size: 11, weight: .medium); noDevLabel.textColor = kDim; noDevLabel.alignment = .center
            noDevLabel.frame = NSRect(x: 0, y: (btListContainer.bounds.height - 20)/2, width: btListContainer.bounds.width, height: 20)
            btListContainer.addSubview(noDevLabel)
            return
        }

        let containerW = btListContainer.bounds.width, itemH: CGFloat = 40, gap: CGFloat = 6
        for (i, dev) in devices.enumerated() {
            let y = btListContainer.bounds.height - CGFloat(i + 1) * (itemH + gap)
            let devCard = NSView(frame: NSRect(x: 0, y: y, width: containerW, height: itemH))
            devCard.wantsLayer = true; devCard.layer?.cornerRadius = 14; devCard.layer?.backgroundColor = kSurface.cgColor
            devCard.layer?.borderWidth = 1.0; devCard.layer?.borderColor = kBorder.cgColor

            let nameTF = NSTextField()
            let nameCell = CenteredTextFieldCell(textCell: dev.name)
            nameCell.font = modernFont(size: 12, weight: .bold); nameCell.textColor = kText; nameCell.lineBreakMode = .byTruncatingTail
            nameTF.cell = nameCell; nameTF.stringValue = dev.name
            nameTF.isEditable = false; nameTF.isBordered = false; nameTF.backgroundColor = .clear
            nameTF.frame = NSRect(x: 10, y: 8, width: containerW - 74, height: 24)
            devCard.addSubview(nameTF)

            let batVal = dev.battery ?? 100
            let badgeTF = NSTextField()
            let badgeCell = CenteredTextFieldCell(textCell: "\(batVal)%")
            badgeCell.alignment = .center; badgeCell.font = modernFont(size: 10, weight: .bold); badgeCell.textColor = .white
            badgeTF.cell = badgeCell; badgeTF.stringValue = "\(batVal)%"
            badgeTF.isEditable = false; badgeTF.isBordered = false
            badgeTF.wantsLayer = true; badgeTF.layer?.cornerRadius = 10; badgeTF.layer?.backgroundColor = kBlue.cgColor
            badgeTF.layer?.borderWidth = 1.0; badgeTF.layer?.borderColor = kBorder.cgColor
            badgeTF.frame = NSRect(x: containerW - 60, y: 8, width: 48, height: 24)
            devCard.addSubview(badgeTF)

            btListContainer.addSubview(devCard)
        }
    }

    private func listenForThemeChanges() { DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil) }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            CATransaction.commit()
        }
    }

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

// MARK: - 4. DIGITAL CLOCK WIDGET (Modern Dark Glass)
class DigitalClockView: NSView {
    let widgetKey = "digital_clock"
    private let timeLabel = NSTextField()
    private let dateLabel = NSTextField()
    private var timer: Timer?
    private var dragStart: NSPoint = .zero, dragActive = false

    override init(frame: NSRect) { super.init(frame: frame); build(); updateTime(); startTimer(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 1.5; layer?.borderColor = kBorder.cgColor

        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 44, weight: .black); timeLabel.textColor = kText; timeLabel.alignment = .center
        timeLabel.isEditable = false; timeLabel.isBordered = false; timeLabel.backgroundColor = .clear; addSubview(timeLabel)

        dateLabel.font = modernFont(size: 11, weight: .bold); dateLabel.textColor = kDim; dateLabel.alignment = .center
        dateLabel.isEditable = false; dateLabel.isBordered = false; dateLabel.backgroundColor = .clear; addSubview(dateLabel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        timeLabel.frame = NSRect(x: 10, y: 32, width: w - 20, height: 52)
        dateLabel.frame = NSRect(x: 10, y: 12, width: w - 20, height: 20)
    }

    private func startTimer() { timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateTime() } }

    private func updateTime() {
        let now = Date()
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        timeLabel.stringValue = tf.string(from: now)

        let df = DateFormatter(); df.dateFormat = "EEEE, MMMM d, yyyy"
        dateLabel.stringValue = df.string(from: now).uppercased()
    }

    private func listenForThemeChanges() { DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil) }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            CATransaction.commit()
        }
    }

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

// MARK: - 5. COLOR PICKER WIDGET (Modern Dark Glass)
class ColorPickerView: NSView {
    let widgetKey = "color_picker"
    private let swatchesContainer = NSView()
    private let pickerBtn = NSButton()
    private var dragStart: NSPoint = .zero, dragActive = false
    private let presetHexes = ["#090D16", "#1E293B", "#0F172A", "#18181B", "#171717", "#0F0F0F"]

    override init(frame: NSRect) { super.init(frame: frame); build(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 1.5; layer?.borderColor = kBorder.cgColor

        swatchesContainer.wantsLayer = true; addSubview(swatchesContainer)
        renderSwatches()

        pickerBtn.title = "CUSTOM COLOR"
        pickerBtn.font = modernFont(size: 10, weight: .bold)
        pickerBtn.isBordered = false; pickerBtn.wantsLayer = true; pickerBtn.layer?.cornerRadius = 12
        pickerBtn.layer?.backgroundColor = kBlue.cgColor; pickerBtn.layer?.borderWidth = 1; pickerBtn.layer?.borderColor = kBorder.cgColor
        pickerBtn.contentTintColor = .white
        pickerBtn.target = self; pickerBtn.action = #selector(openSystemColorPicker)
        addSubview(pickerBtn)
    }

    private func renderSwatches() {
        for sub in swatchesContainer.subviews { sub.removeFromSuperview() }
        let count = presetHexes.count, itemW: CGFloat = 28, itemH: CGFloat = 28, gap: CGFloat = 8
        let totalW = CGFloat(count) * itemW + CGFloat(count - 1) * gap, startX = (bounds.width - totalW) / 2.0

        for (i, hex) in presetHexes.enumerated() {
            let x = startX + CGFloat(i) * (itemW + gap)
            let btn = NSButton(frame: NSRect(x: x, y: 0, width: itemW, height: itemH))
            btn.title = ""; btn.isBordered = false; btn.wantsLayer = true; btn.layer?.cornerRadius = 14
            if let color = NSColor(hex: hex) { btn.layer?.backgroundColor = color.cgColor }
            btn.layer?.borderWidth = 1.0; btn.layer?.borderColor = kBorder.cgColor
            btn.tag = i; btn.target = self; btn.action = #selector(swatchTapped(_:))
            swatchesContainer.addSubview(btn)
        }
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        swatchesContainer.frame = NSRect(x: 0, y: h - 42, width: w, height: 30)
        pickerBtn.frame = NSRect(x: (w - 120)/2, y: 10, width: 120, height: 22)
    }

    @objc private func swatchTapped(_ sender: NSButton) {
        let hex = presetHexes[sender.tag]
        if let col = NSColor(hex: hex) { ThemeManager.shared.currentBgColor = col }
    }

    @objc private func openSystemColorPicker() {
        NSColorPanel.shared.color = ThemeManager.shared.currentBgColor
        NSColorPanel.shared.setTarget(self); NSColorPanel.shared.setAction(#selector(onColorChanged(_:)))
        NSColorPanel.shared.orderFront(nil)
    }

    @objc private func onColorChanged(_ sender: Any) {
        let col = NSColorPanel.shared.color
        ThemeManager.shared.currentBgColor = col
    }

    private func listenForThemeChanges() { DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil) }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            CATransaction.commit()
        }
    }

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

// MARK: - 6. CIRCULAR ANALOG CLOCK WIDGET (Modern Dark Glass)
class AnalogClockView: NSView {
    let widgetKey = "analog_clock"
    private var timer: Timer?, dragStart: NSPoint = .zero, dragActive = false

    override init(frame: NSRect) { super.init(frame: frame); build(); startTimer(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = bounds.width / 2.0
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 1.5; layer?.borderColor = kBorder.cgColor
    }

    private func startTimer() { timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY), radius = bounds.width / 2.0 - 10.0

        ctx.setStrokeColor(kBorder.cgColor); ctx.setLineWidth(1.5)
        ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)); ctx.strokePath()

        for i in 0..<12 {
            let angle = CGFloat(i) * (CGFloat.pi / 6.0), innerR = radius - 8.0
            ctx.setStrokeColor(kDim.cgColor)
            ctx.move(to: CGPoint(x: center.x + radius * sin(angle), y: center.y + radius * cos(angle)))
            ctx.addLine(to: CGPoint(x: center.x + innerR * sin(angle), y: center.y + innerR * cos(angle))); ctx.strokePath()
        }

        let cal = Calendar.current, comp = cal.dateComponents([.hour, .minute, .second], from: Date())
        let sec = CGFloat(comp.second!), min = CGFloat(comp.minute!) + sec / 60.0, hr = CGFloat(comp.hour! % 12) + min / 60.0

        let hrAngle = hr * (CGFloat.pi / 6.0), hrLen = radius * 0.5
        ctx.setLineWidth(3.5); ctx.setStrokeColor(kText.cgColor)
        ctx.move(to: center); ctx.addLine(to: CGPoint(x: center.x + hrLen * sin(hrAngle), y: center.y + hrLen * cos(hrAngle))); ctx.strokePath()

        let minAngle = min * (CGFloat.pi / 30.0), minLen = radius * 0.7
        ctx.setLineWidth(2.0); ctx.setStrokeColor(kBlue.cgColor)
        ctx.move(to: center); ctx.addLine(to: CGPoint(x: center.x + minLen * sin(minAngle), y: center.y + minLen * cos(minAngle))); ctx.strokePath()

        let secAngle = sec * (CGFloat.pi / 30.0), secLen = radius * 0.85
        ctx.setLineWidth(1.2); ctx.setStrokeColor(kAccent.cgColor)
        ctx.move(to: center); ctx.addLine(to: CGPoint(x: center.x + secLen * sin(secAngle), y: center.y + secLen * cos(secAngle))); ctx.strokePath()

        ctx.setFillColor(kText.cgColor); ctx.addEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)); ctx.fillPath()
    }

    private func listenForThemeChanges() { DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil) }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            CATransaction.commit()
        }
    }

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

// MARK: - 7. SPOTIFY LIVE PLAYER WIDGET (Modern Dark Glass)
class AudioEqualizerView: NSView {
    var isPlaying: Bool = false { didSet { isPlaying ? startAnimation() : stopAnimation() } }
    private var barHeights: [CGFloat] = [0.3, 0.6, 0.4, 0.8], animTimer: Timer?

    private func startAnimation() {
        guard animTimer == nil else { return }
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.barHeights = (0..<4).map { _ in CGFloat.random(in: 0.25...1.0) }
            self?.needsDisplay = true
        }
    }
    private func stopAnimation() { animTimer?.invalidate(); animTimer = nil; barHeights = [0.15, 0.15, 0.15, 0.15]; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let barCount = 4, gap: CGFloat = 3, barW = (bounds.width - CGFloat(barCount - 1) * gap) / CGFloat(barCount), maxH = bounds.height
        ctx.setFillColor(kBlue.cgColor)
        for i in 0..<barCount {
            let h = max(3.0, maxH * barHeights[i])
            ctx.fill(CGRect(x: CGFloat(i) * (barW + gap), y: (maxH - h) / 2.0, width: barW, height: h))
        }
    }
}

class ProgressBarView: NSView {
    var progress: CGFloat = 0.0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(kSurface.cgColor); ctx.fill(bounds)
        ctx.setStrokeColor(kBorder.cgColor); ctx.setLineWidth(1.0); ctx.stroke(bounds)
        let fillW = max(0, min(bounds.width * progress, bounds.width))
        if fillW > 0 {
            ctx.setFillColor(kBlue.cgColor); ctx.fill(NSRect(x: 0, y: 0, width: fillW, height: bounds.height))
            let r: CGFloat = 4.0, c = CGPoint(x: fillW, y: bounds.midY)
            ctx.setFillColor(kText.cgColor); ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2)); ctx.fillPath()
        }
    }
}

class SpotifyView: NSView {
    let widgetKey = "spotify"
    private let eqView = AudioEqualizerView()
    private let artImageView = NSImageView()
    private let trackLabel = NSTextField(), artistLabel = NSTextField()
    private let progressBar = ProgressBarView(), currTimeLabel = NSTextField(), durTimeLabel = NSTextField()
    private let prevBtn = NSButton(), playBtn = NSButton(), nextBtn = NSButton(), statusLabel = NSTextField()
    private var timer: Timer?, currentArtUrl = "", isPlaying = false, dragStart: NSPoint = .zero, dragActive = false

    override init(frame: NSRect) { super.init(frame: frame); build(); updateSpotifyInfo(); startTimer(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 1.5; layer?.borderColor = kBorder.cgColor
        addSubview(eqView)

        artImageView.wantsLayer = true; artImageView.layer?.cornerRadius = 18; artImageView.layer?.borderWidth = 1.0; artImageView.layer?.borderColor = kBorder.cgColor
        artImageView.imageScaling = .scaleAxesIndependently; artImageView.imageAlignment = .alignCenter; addSubview(artImageView)

        trackLabel.font = modernFont(size: 13, weight: .black); trackLabel.textColor = kText; trackLabel.isEditable = false; trackLabel.isBordered = false; trackLabel.backgroundColor = .clear; trackLabel.lineBreakMode = .byTruncatingTail; addSubview(trackLabel)
        artistLabel.font = modernFont(size: 11, weight: .bold); artistLabel.textColor = kDim; artistLabel.isEditable = false; artistLabel.isBordered = false; artistLabel.backgroundColor = .clear; artistLabel.lineBreakMode = .byTruncatingTail; addSubview(artistLabel)

        progressBar.wantsLayer = true; addSubview(progressBar)
        currTimeLabel.font = modernFont(size: 10, weight: .bold); currTimeLabel.textColor = kText; currTimeLabel.isEditable = false; currTimeLabel.isBordered = false; currTimeLabel.backgroundColor = .clear; addSubview(currTimeLabel)
        durTimeLabel.font = modernFont(size: 10, weight: .bold); durTimeLabel.textColor = kDim; durTimeLabel.isEditable = false; durTimeLabel.isBordered = false; durTimeLabel.backgroundColor = .clear; durTimeLabel.alignment = .right; addSubview(durTimeLabel)

        setupBtn(prevBtn, title: "⏮", action: #selector(onPrev))
        setupBtn(playBtn, title: "▶", action: #selector(onPlayPause))
        setupBtn(nextBtn, title: "⏭", action: #selector(onNext))

        statusLabel.stringValue = "Spotify Offline"; statusLabel.font = modernFont(size: 12, weight: .bold); statusLabel.textColor = kDim; statusLabel.alignment = .center; statusLabel.isEditable = false; statusLabel.isBordered = false; statusLabel.backgroundColor = .clear; statusLabel.isHidden = true; addSubview(statusLabel)
    }

    private func setupBtn(_ btn: NSButton, title: String, action: Selector) {
        btn.title = title; btn.font = modernFont(size: 12, weight: .bold); btn.isBordered = false; btn.wantsLayer = true; btn.layer?.cornerRadius = 10; btn.layer?.backgroundColor = kSurface.cgColor; btn.layer?.borderWidth = 1.0; btn.layer?.borderColor = kBorder.cgColor; btn.contentTintColor = kText; btn.target = self; btn.action = action; addSubview(btn)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height, artSize: CGFloat = 96
        eqView.frame = NSRect(x: w - 44, y: h - 22, width: 32, height: 14)
        artImageView.frame = NSRect(x: 12, y: 12, width: artSize, height: artSize)
        let infoX = artSize + 22, infoW = w - infoX - 12
        trackLabel.frame  = NSRect(x: infoX, y: h - 42, width: infoW - 36, height: 20)
        artistLabel.frame = NSRect(x: infoX, y: h - 58, width: infoW, height: 16)
        progressBar.frame   = NSRect(x: infoX, y: 46, width: infoW, height: 6)
        currTimeLabel.frame = NSRect(x: infoX, y: 28, width: infoW / 2, height: 14)
        durTimeLabel.frame  = NSRect(x: infoX + infoW / 2, y: 28, width: infoW / 2, height: 14)
        let btnW: CGFloat = 38, btnH: CGFloat = 20, gap: CGFloat = 6
        prevBtn.frame = NSRect(x: infoX, y: 6, width: btnW, height: btnH)
        playBtn.frame = NSRect(x: infoX + btnW + gap, y: 6, width: btnW, height: btnH)
        nextBtn.frame = NSRect(x: infoX + (btnW + gap) * 2, y: 6, width: btnW, height: btnH)
        statusLabel.frame = NSRect(x: 10, y: (h - 30)/2, width: w - 20, height: 30)
    }

    private func startTimer() { timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateSpotifyInfo() } }

    private func fmtTime(_ sec: Double) -> String {
        guard sec > 0 && !sec.isNaN && !sec.isInfinite else { return "0:00" }
        let t = Int(sec); return String(format: "%d:%02d", t / 60, t % 60)
    }

    @objc private func updateSpotifyInfo() {
        let sc = """
        tell application "System Events" to set isRunning to (name of processes) contains "Spotify"
        if isRunning then
            tell application "Spotify"
                if player state is playing or player state is paused then
                    return (name of current track) & "|||" & (artist of current track) & "|||" & (artwork url of current track) & "|||" & (player state is playing) & "|||" & (player position) & "|||" & ((duration of current track) / 1000.0)
                end if
            end tell
        end if
        return "OFFLINE"
        """
        let res = runScript(sc)
        if res == "OFFLINE" || res.isEmpty {
            eqView.isPlaying = false; eqView.isHidden = true; artImageView.isHidden = true; trackLabel.isHidden = true; artistLabel.isHidden = true; progressBar.isHidden = true; currTimeLabel.isHidden = true; durTimeLabel.isHidden = true; prevBtn.isHidden = true; playBtn.isHidden = true; nextBtn.isHidden = true
            statusLabel.stringValue = "Spotify Offline"; statusLabel.isHidden = false
        } else {
            let p = res.components(separatedBy: "|||")
            if p.count >= 6 {
                trackLabel.stringValue = p[0]; artistLabel.stringValue = p[1]; isPlaying = (p[3] == "true")
                playBtn.title = isPlaying ? "⏸" : "▶"; eqView.isPlaying = isPlaying
                let pos = Double(p[4]) ?? 0.0, dur = Double(p[5]) ?? 1.0
                currTimeLabel.stringValue = fmtTime(pos); durTimeLabel.stringValue = fmtTime(dur)
                progressBar.progress = dur > 0 ? CGFloat(pos / dur) : 0.0
                statusLabel.isHidden = true; eqView.isHidden = false; artImageView.isHidden = false; trackLabel.isHidden = false; artistLabel.isHidden = false; progressBar.isHidden = false; currTimeLabel.isHidden = false; durTimeLabel.isHidden = false; prevBtn.isHidden = false; playBtn.isHidden = false; nextBtn.isHidden = false
                if p[2] != currentArtUrl && !p[2].isEmpty { currentArtUrl = p[2]; loadArtwork(from: p[2]) }
            }
        }
    }

    private func loadArtwork(from urlStr: String) {
        guard let url = URL(string: urlStr) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            if let data = data, let img = NSImage(data: data) { DispatchQueue.main.async { self?.artImageView.image = img } }
        }.resume()
    }

    @objc private func onPrev() { _ = runScript("tell application \"Spotify\" to previous track"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.updateSpotifyInfo() } }
    @objc private func onPlayPause() { _ = runScript("tell application \"Spotify\" to playpause"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.updateSpotifyInfo() } }
    @objc private func onNext() { _ = runScript("tell application \"Spotify\" to next track"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.updateSpotifyInfo() } }

    private func listenForThemeChanges() { DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil) }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            CATransaction.commit()
        }
    }

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

// MARK: - 8. ROBLOX DANCE TRANSPARENT GIF WIDGET (Modern Dark Glass)
class GifView: NSView {
    let widgetKey = "gif"
    private let imageView = NSImageView()
    private var dragStart: NSPoint = .zero
    private var dragMoved = false

    override init(frame: NSRect) { super.init(frame: frame); build(); loadGif() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.isOpaque = false; layer?.backgroundColor = NSColor.clear.cgColor
        imageView.wantsLayer = true; imageView.layer?.isOpaque = false; imageView.layer?.backgroundColor = NSColor.clear.cgColor
        imageView.animates = false; imageView.canDrawSubviewsIntoLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown; imageView.imageAlignment = .alignCenter
        addSubview(imageView)
    }

    override func layout() { super.layout(); imageView.frame = bounds }

    private func loadGif() {
        let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("CustomERGifs")
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
           let firstGif = files.filter({ $0.pathExtension.lowercased() == "gif" }).first,
           let img = NSImage(contentsOf: firstGif) {
            imageView.image = img
            imageView.animates = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        dragMoved = false
        window?.makeKey()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let w = window else { return }
        let c = event.locationInWindow
        let dx = c.x - dragStart.x, dy = c.y - dragStart.y
        if abs(dx) > 2 || abs(dy) > 2 {
            dragMoved = true
            w.setFrameOrigin(NSPoint(x: w.frame.origin.x + dx, y: w.frame.origin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !dragMoved {
            imageView.animates.toggle()
        } else {
            if let w = window { PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin) }
        }
    }
}

// MARK: - 9. GITHUB WIDGET (Modern Dark Glass)
class GithubView: NSView {
    let widgetKey = "github"
    private var username: String = {
        let u = runScript("gh api user -q .login 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
        return u.isEmpty ? "username" : u
    }()
    
    private let titleLabel      = NSTextField()
    private let userBadge       = NSTextField()
    private let avatarImageView = NSImageView()
    
    private let reposCard       = NSView()
    private let reposNum        = NSTextField()
    private let reposLbl        = NSTextField()

    private let contribsCard    = NSView()
    private let contribsNum     = NSTextField()
    private let contribsLbl     = NSTextField()

    private var timer: Timer?
    private var dragStart: NSPoint = .zero
    private var dragMoved = false

    override init(frame: NSRect) { super.init(frame: frame); build(); fetchStats(); startTimer(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 1.5; layer?.borderColor = kBorder.cgColor

        titleLabel.stringValue = "GITHUB"
        titleLabel.font = modernFont(size: 13, weight: .black); titleLabel.textColor = kText
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        userBadge.stringValue = "@\(username)"
        userBadge.font = modernFont(size: 10, weight: .bold); userBadge.textColor = kDim; userBadge.alignment = .right
        userBadge.isEditable = false; userBadge.isBordered = false; userBadge.backgroundColor = .clear
        addSubview(userBadge)

        avatarImageView.wantsLayer = true; avatarImageView.layer?.cornerRadius = 41; avatarImageView.layer?.borderWidth = 1.5; avatarImageView.layer?.borderColor = kBlue.cgColor
        avatarImageView.imageScaling = .scaleAxesIndependently; avatarImageView.imageAlignment = .alignCenter
        addSubview(avatarImageView)

        setupStatCard(reposCard, numLabel: reposNum, titleLabel: reposLbl, title: "REPOS")
        setupStatCard(contribsCard, numLabel: contribsNum, titleLabel: contribsLbl, title: "CONTRIBS")
    }

    private func setupStatCard(_ card: NSView, numLabel: NSTextField, titleLabel: NSTextField, title: String) {
        card.wantsLayer = true; card.layer?.cornerRadius = 16; card.layer?.backgroundColor = kSurface.cgColor
        card.layer?.borderWidth = 1.0; card.layer?.borderColor = kBorder.cgColor; addSubview(card)

        numLabel.stringValue = "-"
        numLabel.font = modernFont(size: 18, weight: .black); numLabel.textColor = kText; numLabel.alignment = .center
        numLabel.isEditable = false; numLabel.isBordered = false; numLabel.backgroundColor = .clear; card.addSubview(numLabel)

        titleLabel.stringValue = title
        titleLabel.font = modernFont(size: 10, weight: .bold); titleLabel.textColor = kDim; titleLabel.alignment = .center
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear; card.addSubview(titleLabel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleLabel.frame = NSRect(x: 12, y: h - 28, width: 130, height: 18)
        userBadge.frame  = NSRect(x: w - 140, y: h - 28, width: 128, height: 18)

        let avSize: CGFloat = 82
        avatarImageView.frame = NSRect(x: 12, y: 12, width: avSize, height: avSize)

        let gridX: CGFloat = avSize + 22, gridW = w - gridX - 12
        let cardW = (gridW - 8) / 2.0, cardH: CGFloat = 52

        reposCard.frame     = NSRect(x: gridX, y: 26, width: cardW, height: cardH)
        contribsCard.frame  = NSRect(x: gridX + cardW + 8, y: 26, width: cardW, height: cardH)

        layoutCardContent(reposNum, reposLbl, cardH: cardH, cardW: cardW)
        layoutCardContent(contribsNum, contribsLbl, cardH: cardH, cardW: cardW)
    }

    private func layoutCardContent(_ num: NSTextField, _ lbl: NSTextField, cardH: CGFloat, cardW: CGFloat) {
        num.frame = NSRect(x: 0, y: 22, width: cardW, height: 24)
        lbl.frame = NSRect(x: 0, y: 6, width: cardW, height: 14)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 900.0, repeats: true) { [weak self] _ in self?.fetchStats() }
    }

    private func fetchStats() {
        let u = username
        DispatchQueue.global(qos: .background).async { [weak self] in
            let token = runScript("gh auth token 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let url = URL(string: "https://api.github.com/users/\(u)") {
                var req = URLRequest(url: url)
                req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
                if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                
                URLSession.shared.dataTask(with: req) { data, _, _ in
                    guard let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                    
                    let repos = json["public_repos"] as? Int ?? 0
                    let avatarUrl = json["avatar_url"] as? String ?? ""

                    DispatchQueue.main.async {
                        self?.reposNum.stringValue = "\(repos)"
                    }
                    
                    if !avatarUrl.isEmpty, let aUrl = URL(string: avatarUrl) {
                        URLSession.shared.dataTask(with: aUrl) { aData, _, _ in
                            if let aData = aData, let img = NSImage(data: aData) {
                                DispatchQueue.main.async { self?.avatarImageView.image = img }
                            }
                        }.resume()
                    }
                }.resume()
            }

            if !token.isEmpty, let gqlUrl = URL(string: "https://api.github.com/graphql") {
                var gReq = URLRequest(url: gqlUrl)
                gReq.httpMethod = "POST"
                gReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                gReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let query = ["query": "query { user(login: \"\(u)\") { contributionsCollection { contributionCalendar { totalContributions } } } }"]
                if let bodyData = try? JSONSerialization.data(withJSONObject: query) {
                    gReq.httpBody = bodyData
                    URLSession.shared.dataTask(with: gReq) { gData, _, _ in
                        if let gData = gData,
                           let json = try? JSONSerialization.jsonObject(with: gData) as? [String: Any],
                           let dataObj = json["data"] as? [String: Any],
                           let userObj = dataObj["user"] as? [String: Any],
                           let cc = userObj["contributionsCollection"] as? [String: Any],
                           let cal = cc["contributionCalendar"] as? [String: Any],
                           let total = cal["totalContributions"] as? Int {
                            DispatchQueue.main.async {
                                self?.contribsNum.stringValue = "\(total)"
                            }
                            return
                        }
                    }.resume()
                }
            } else if let cUrl = URL(string: "https://github.com/users/\(u)/contributions") {
                URLSession.shared.dataTask(with: cUrl) { cData, _, _ in
                    guard let cData = cData, let html = String(data: cData, encoding: .utf8) else { return }
                    if let regex = try? NSRegularExpression(pattern: #"(\d+[\d,]*)\s+contributions\s+in the last year"#, options: .caseInsensitive),
                       let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
                       let range = Range(match.range(at: 1), in: html) {
                        let countStr = String(html[range])
                        DispatchQueue.main.async {
                            self?.contribsNum.stringValue = countStr
                        }
                    }
                }.resume()
            }
        }
    }

    private func listenForThemeChanges() { DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil) }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            CATransaction.commit()
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        dragMoved = false
        window?.makeKey()
        if event.clickCount == 2 {
            if let url = URL(string: "https://github.com/\(username)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let w = window else { return }
        let c = event.locationInWindow
        let dx = c.x - dragStart.x, dy = c.y - dragStart.y
        if abs(dx) > 2 || abs(dy) > 2 {
            dragMoved = true
            w.setFrameOrigin(NSPoint(x: w.frame.origin.x + dx, y: w.frame.origin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragMoved, let w = window {
            PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin)
        }
    }
}

// MARK: - 10. ONLINE GMAIL / MAIL UNREAD WIDGET (Modern Dark Glass)
struct GmailEntry {
    var title: String = ""
    var summary: String = ""
    var authorName: String = ""
    var authorEmail: String = ""
}

class GmailAtomParser: NSObject, XMLParserDelegate {
    var fullCount: Int = 0
    var entries: [GmailEntry] = []
    
    private var currentElement = ""
    private var currentTitle = ""
    private var currentSummary = ""
    private var currentAuthorName = ""
    private var currentAuthorEmail = ""
    private var inEntry = false
    private var inAuthor = false

    func parse(xmlData: Data) {
        let parser = XMLParser(data: xmlData)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "entry" {
            inEntry = true; currentTitle = ""; currentSummary = ""; currentAuthorName = ""; currentAuthorEmail = ""
        } else if elementName == "author" {
            inAuthor = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let str = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return }
        if !inEntry && currentElement == "fullcount" {
            fullCount = Int(str) ?? 0
        } else if inEntry {
            if currentElement == "title" {
                currentTitle += string
            } else if currentElement == "summary" {
                currentSummary += string
            } else if inAuthor {
                if currentElement == "name" { currentAuthorName += string }
                else if currentElement == "email" { currentAuthorEmail += string }
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?) {
        if elementName == "entry" {
            inEntry = false
            entries.append(GmailEntry(title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                      summary: currentSummary.trimmingCharacters(in: .whitespacesAndNewlines),
                                      authorName: currentAuthorName.trimmingCharacters(in: .whitespacesAndNewlines),
                                      authorEmail: currentAuthorEmail.trimmingCharacters(in: .whitespacesAndNewlines)))
        } else if elementName == "author" {
            inAuthor = false
        }
    }
}

class MailView: NSView {
    let widgetKey = "mail"
    private let titleLabel    = NSTextField()
    private let badgeLabel    = NSTextField()
    private let cardView      = NSView()
    private let countNumLabel = NSTextField()
    private let senderLabel   = NSTextField()
    private let subjectLabel  = NSTextField()

    private var timer: Timer?
    private var dragStart: NSPoint = .zero, dragActive = false

    override init(frame: NSRect) { super.init(frame: frame); build(); updateMail(); startTimer(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 1.5; layer?.borderColor = kBorder.cgColor

        titleLabel.stringValue = "GMAIL"
        titleLabel.font = modernFont(size: 13, weight: .black); titleLabel.textColor = kText
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        badgeLabel.stringValue = "0 UNREAD"
        badgeLabel.font = modernFont(size: 10, weight: .bold); badgeLabel.textColor = kDim; badgeLabel.alignment = .right
        badgeLabel.isEditable = false; badgeLabel.isBordered = false; badgeLabel.backgroundColor = .clear
        addSubview(badgeLabel)

        cardView.wantsLayer = true; cardView.layer?.cornerRadius = 16; cardView.layer?.backgroundColor = kSurface.cgColor
        cardView.layer?.borderWidth = 1.0; cardView.layer?.borderColor = kBorder.cgColor; addSubview(cardView)

        countNumLabel.stringValue = "0"
        countNumLabel.font = modernFont(size: 22, weight: .black); countNumLabel.textColor = kBlue; countNumLabel.alignment = .center
        countNumLabel.isEditable = false; countNumLabel.isBordered = false; countNumLabel.backgroundColor = .clear; cardView.addSubview(countNumLabel)

        senderLabel.stringValue = "Double-click to set Gmail"
        senderLabel.font = modernFont(size: 11, weight: .bold); senderLabel.textColor = kText; senderLabel.lineBreakMode = .byTruncatingTail
        senderLabel.isEditable = false; senderLabel.isBordered = false; senderLabel.backgroundColor = .clear; cardView.addSubview(senderLabel)

        subjectLabel.stringValue = "Or open Apple Mail"
        subjectLabel.font = modernFont(size: 10, weight: .medium); subjectLabel.textColor = kDim; subjectLabel.lineBreakMode = .byTruncatingTail
        subjectLabel.isEditable = false; subjectLabel.isBordered = false; subjectLabel.backgroundColor = .clear; cardView.addSubview(subjectLabel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleLabel.frame = NSRect(x: 12, y: h - 28, width: 100, height: 18)
        badgeLabel.frame = NSRect(x: w - 120, y: h - 28, width: 108, height: 18)

        cardView.frame   = NSRect(x: 12, y: 12, width: w - 24, height: 58)
        countNumLabel.frame = NSRect(x: 8, y: 14, width: 44, height: 30)
        senderLabel.frame   = NSRect(x: 58, y: 30, width: w - 90, height: 16)
        subjectLabel.frame  = NSRect(x: 58, y: 12, width: w - 90, height: 16)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in self?.updateMail() }
    }

    private func getGmailCredentials() -> (email: String, pass: String)? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CustomER/gmail.json")
        if let data = try? Data(contentsOf: path),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let u = json["email"], !u.isEmpty,
           let p = json["app_password"], !p.isEmpty {
            return (u, p)
        }
        return nil
    }

    private func updateMail() {
        guard let creds = getGmailCredentials() else {
            countNumLabel.stringValue = "0"
            badgeLabel.stringValue = "0 UNREAD"
            senderLabel.stringValue = "Double-click to set Gmail"
            subjectLabel.stringValue = "Online Gmail Sync"
            return
        }
        fetchGmailOnline(user: creds.email, pass: creds.pass)
    }

    private func fetchGmailOnline(user: String, pass: String) {
        guard let url = URL(string: "https://mail.google.com/mail/feed/atom") else { return }
        let loginStr = "\(user):\(pass)"
        guard let loginData = loginStr.data(using: .utf8) else { return }
        let base64Login = loginData.base64EncodedString()

        var req = URLRequest(url: url)
        req.setValue("Basic \(base64Login)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }
            let parser = GmailAtomParser()
            parser.parse(xmlData: data)

            DispatchQueue.main.async {
                let count = parser.fullCount
                self?.countNumLabel.stringValue = "\(count)"
                self?.badgeLabel.stringValue = "\(count) UNREAD"
                if let first = parser.entries.first {
                    let sender = first.authorName.isEmpty ? (first.authorEmail.isEmpty ? "Gmail Sender" : first.authorEmail) : first.authorName
                    let subject = !first.title.isEmpty ? first.title : (!first.summary.isEmpty ? first.summary : "(No Subject)")
                    self?.senderLabel.stringValue = sender
                    self?.subjectLabel.stringValue = subject
                } else if count > 0 {
                    self?.senderLabel.stringValue = "Unread Email"
                    self?.subjectLabel.stringValue = "Check Gmail Inbox"
                } else {
                    self?.senderLabel.stringValue = "No unread mail"
                    self?.subjectLabel.stringValue = "All caught up!"
                }
            }
        }.resume()
    }

    private func listenForThemeChanges() { DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil) }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            CATransaction.commit()
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow; dragActive = true; window?.makeKey()
        if event.clickCount == 2 {
            if let url = URL(string: "https://mail.google.com") {
                NSWorkspace.shared.open(url)
            }
        }
    }
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

// MARK: - 11. PHOTO SLOTS WIDGET (Modern Dark Glass)
struct PhotoSlot { let id: Int; let folderName: String; let rect: NSRect }

class PhotosView: NSView {
    let widgetKey: String
    private let imageView = NSImageView()
    private let folderName: String
    private var dragStart: NSPoint = .zero, dragActive = false

    init(frame: NSRect, folderName: String, slotId: Int) {
        self.folderName = folderName
        self.widgetKey = "photo_\(slotId)"
        super.init(frame: frame); build(); loadPhoto()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.backgroundColor = NSColor.clear.cgColor
        imageView.wantsLayer = true; imageView.layer?.cornerRadius = kRadius; imageView.layer?.borderWidth = 1.5; imageView.layer?.borderColor = kBorder.cgColor
        imageView.imageScaling = .scaleAxesIndependently; imageView.imageAlignment = .alignCenter
        addSubview(imageView)
    }

    override func layout() { super.layout(); imageView.frame = bounds }

    private func loadPhoto() {
        let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent(folderName)
        let ext = ["jpg", "jpeg", "png", "heic", "webp"]
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
           let firstPhoto = files.filter({ ext.contains($0.pathExtension.lowercased()) }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first,
           let img = NSImage.downsampledImage(at: firstPhoto, targetSize: NSSize(width: 196, height: 196)) {
            imageView.image = img
        }
    }

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
        FolderIconManager.updateDesktopFolderIcons(bgColor: ThemeManager.shared.currentBgColor)

        // 1. Reminders
        let defaultTodoRect = NSRect(x: 24, y: 600, width: 280, height: 440)
        let todoOrigin = PositionManager.shared.getPosition(key: "reminders", defaultOrigin: defaultTodoRect.origin)
        addWindow(rect: NSRect(origin: todoOrigin, size: defaultTodoRect.size), view: TodoView(frame: NSRect(origin: todoOrigin, size: defaultTodoRect.size)))

        // 2. Calendar
        let defaultCalRect = NSRect(x: 24, y: 350, width: 280, height: 230)
        let calOrigin = PositionManager.shared.getPosition(key: "calendar", defaultOrigin: defaultCalRect.origin)
        addWindow(rect: NSRect(origin: calOrigin, size: defaultCalRect.size), view: CalendarView(frame: NSRect(origin: calOrigin, size: defaultCalRect.size)))

        // 3. Battery
        let defaultBatRect = NSRect(x: 24, y: 50, width: 280, height: 280)
        let batOrigin = PositionManager.shared.getPosition(key: "battery", defaultOrigin: defaultBatRect.origin)
        addWindow(rect: NSRect(origin: batOrigin, size: defaultBatRect.size), view: BatteryView(frame: NSRect(origin: batOrigin, size: defaultBatRect.size)))

        // 4. Digital Clock
        let defaultClockRect = NSRect(x: 320, y: 930, width: 280, height: 110)
        let clockOrigin = PositionManager.shared.getPosition(key: "digital_clock", defaultOrigin: defaultClockRect.origin)
        addWindow(rect: NSRect(origin: clockOrigin, size: defaultClockRect.size), view: DigitalClockView(frame: NSRect(origin: clockOrigin, size: defaultClockRect.size)))

        // 5. Color Picker
        let defaultColorRect = NSRect(x: 320, y: 830, width: 280, height: 80)
        let colorOrigin = PositionManager.shared.getPosition(key: "color_picker", defaultOrigin: defaultColorRect.origin)
        addWindow(rect: NSRect(origin: colorOrigin, size: defaultColorRect.size), view: ColorPickerView(frame: NSRect(origin: colorOrigin, size: defaultColorRect.size)))

        // 6. Circular Analog Clock
        let defaultAnalogRect = NSRect(x: 613, y: 827, width: 220, height: 220)
        let analogOrigin = PositionManager.shared.getPosition(key: "analog_clock", defaultOrigin: defaultAnalogRect.origin)
        addWindow(rect: NSRect(origin: analogOrigin, size: defaultAnalogRect.size), view: AnalogClockView(frame: NSRect(origin: analogOrigin, size: defaultAnalogRect.size)))

        // 7. Spotify Player
        let defaultSpotRect = NSRect(x: 872, y: 905, width: 280, height: 130)
        let spotOrigin = PositionManager.shared.getPosition(key: "spotify", defaultOrigin: defaultSpotRect.origin)
        addWindow(rect: NSRect(origin: spotOrigin, size: defaultSpotRect.size), view: SpotifyView(frame: NSRect(origin: spotOrigin, size: defaultSpotRect.size)))

        // 8. Roblox Dance GIF
        let defaultGifRect = NSRect(x: 268, y: 694, width: 196, height: 196)
        let gifOrigin = PositionManager.shared.getPosition(key: "gif", defaultOrigin: defaultGifRect.origin)
        addWindow(rect: NSRect(origin: gifOrigin, size: defaultGifRect.size), view: GifView(frame: NSRect(origin: gifOrigin, size: defaultGifRect.size)))

        // 9. GitHub Profile Stats Widget
        let defaultGithubRect = NSRect(x: 320, y: 290, width: 280, height: 130)
        let githubOrigin = PositionManager.shared.getPosition(key: "github", defaultOrigin: defaultGithubRect.origin)
        addWindow(rect: NSRect(origin: githubOrigin, size: defaultGithubRect.size), view: GithubView(frame: NSRect(origin: githubOrigin, size: defaultGithubRect.size)))

        // 10. Apple Mail Unread Widget
        let defaultMailRect = NSRect(x: 320, y: 165, width: 280, height: 110)
        let mailOrigin = PositionManager.shared.getPosition(key: "mail", defaultOrigin: defaultMailRect.origin)
        addWindow(rect: NSRect(origin: mailOrigin, size: defaultMailRect.size), view: MailView(frame: NSRect(origin: mailOrigin, size: defaultMailRect.size)))

        // 11. 13 Photo Slots (Compact 110x110 in 1 Single Continuous Row)
        let photoSlots: [PhotoSlot] = [
            PhotoSlot(id: 1,  folderName: "CustomERPhotos",   rect: NSRect(x: 30,   y: 480, width: 110, height: 110)),
            PhotoSlot(id: 2,  folderName: "CustomERPhotos2",  rect: NSRect(x: 145,  y: 480, width: 110, height: 110)),
            PhotoSlot(id: 3,  folderName: "CustomERPhotos3",  rect: NSRect(x: 260,  y: 480, width: 110, height: 110)),
            PhotoSlot(id: 4,  folderName: "CustomERPhotos4",  rect: NSRect(x: 375,  y: 480, width: 110, height: 110)),
            PhotoSlot(id: 5,  folderName: "CustomERPhotos5",  rect: NSRect(x: 490,  y: 480, width: 110, height: 110)),
            PhotoSlot(id: 6,  folderName: "CustomERPhotos6",  rect: NSRect(x: 605,  y: 480, width: 110, height: 110)),
            PhotoSlot(id: 7,  folderName: "CustomERPhotos7",  rect: NSRect(x: 720,  y: 480, width: 110, height: 110)),
            PhotoSlot(id: 8,  folderName: "CustomERPhotos8",  rect: NSRect(x: 835,  y: 480, width: 110, height: 110)),
            PhotoSlot(id: 9,  folderName: "CustomERPhotos9",  rect: NSRect(x: 950,  y: 480, width: 110, height: 110)),
            PhotoSlot(id: 10, folderName: "CustomERPhotos10", rect: NSRect(x: 1065, y: 480, width: 110, height: 110)),
            PhotoSlot(id: 11, folderName: "CustomERPhotos11", rect: NSRect(x: 1180, y: 480, width: 110, height: 110)),
            PhotoSlot(id: 12, folderName: "CustomERPhotos12", rect: NSRect(x: 1295, y: 480, width: 110, height: 110)),
            PhotoSlot(id: 13, folderName: "CustomERPhotos13", rect: NSRect(x: 1410, y: 480, width: 110, height: 110))
        ]

        for slot in photoSlots {
            let key = "photo_\(slot.id)"
            let origin = PositionManager.shared.getPosition(key: key, defaultOrigin: slot.rect.origin)
            let winRect = NSRect(origin: origin, size: slot.rect.size)
            addWindow(rect: winRect, view: PhotosView(frame: winRect, folderName: slot.folderName, slotId: slot.id))
        }
    }

    private func addWindow(rect: NSRect, view: NSView) {
        let win = MasterWidgetWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = NSWindow.Level(rawValue: -1)
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.hasShadow = false
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        windows.append(win)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
