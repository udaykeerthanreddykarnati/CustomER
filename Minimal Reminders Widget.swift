import AppKit
import Foundation

// MARK: - Model

struct Reminder: Codable {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var createdAt: Date

    init(title: String) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
        self.createdAt = Date()
    }
}

// MARK: - Store

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
              let decoded = try? JSONDecoder().decode([Reminder].self, from: data)
        else { return }
        items = decoded
    }

    func save() { try? JSONEncoder().encode(items).write(to: url) }

    func add(_ r: Reminder)      { items.append(r); save() }
    func toggle(id: UUID)        { if let i = items.firstIndex(where: { $0.id == id }) { items[i].isCompleted.toggle(); save() } }
    func delete(id: UUID)        { items.removeAll { $0.id == id }; save() }
    func clearCompleted()        { items.removeAll { $0.isCompleted }; save() }
    func updateTitle(id: UUID, title: String) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].title = title; save() }
    }
}

// MARK: - Colors (Soft Eye-Pleasing Pastel Yellow)

let kBg         = NSColor(red: 254/255.0, green: 249/255.0, blue: 195/255.0, alpha: 1.00)  // Default Soft Pastel Butter
let kBlue       = NSColor(red: 128/255.0, green: 0/255.0, blue: 32/255.0, alpha: 1.00)  // Rich Burgundy header & text (#800020)
let kBlue2      = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.12)  // Badge background
let kAddBg      = NSColor(red: 128/255.0, green: 0/255.0, blue: 32/255.0, alpha: 1.00)  // Rich Burgundy (#800020)
let kDim        = NSColor(red: 0.35, green: 0.35, blue: 0.25, alpha: 1.00)  // Muted text
let kSurface    = NSColor(red: 254/255.0, green: 252/255.0, blue: 232/255.0, alpha: 1.00)  // Lighter Soft Cream (#FEFCE8)
let kBorder     = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.00)  // Solid Black Border

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

// MARK: - Custom Window (canBecomeKey for typing)

class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Row View

class ReminderRowView: NSView {
    var reminder: Reminder
    var onToggle: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onEdit:   ((UUID, String) -> Void)?

    private let check  = NSButton()
    private let label  = NSTextField()
    private let del    = NSButton()

    init(_ reminder: Reminder) {
        self.reminder = reminder
        super.init(frame: .zero)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.backgroundColor = kSurface.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = kBorder.cgColor

        // Checkbox (Sharp Square)
        check.isBordered = false
        check.bezelStyle = .regularSquare
        check.setButtonType(.momentaryChange)
        check.wantsLayer = true
        check.layer?.cornerRadius = 0
        check.layer?.borderWidth = 1.5
        check.layer?.borderColor = kBorder.cgColor
        check.layer?.backgroundColor = reminder.isCompleted ? kBorder.cgColor : NSColor.clear.cgColor
        if reminder.isCompleted {
            check.attributedTitle = NSAttributedString(string: "✓", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor.white
            ])
        } else { check.title = "" }
        check.target = self
        check.action = #selector(toggleTapped)
        addSubview(check)

        // Title
        label.isBordered = false; label.backgroundColor = .clear
        label.isEditable = false; label.isSelectable = false
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        if reminder.isCompleted {
            let s = NSMutableAttributedString(string: reminder.title)
            let r = NSRange(location: 0, length: reminder.title.count)
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            s.addAttribute(.foregroundColor, value: kDim, range: r)
            label.attributedStringValue = s
        } else {
            label.stringValue = reminder.title
            label.textColor = kBlue
        }
        let dclick = NSClickGestureRecognizer(target: self, action: #selector(editTapped))
        dclick.numberOfClicksRequired = 2
        label.addGestureRecognizer(dclick)
        addSubview(label)

        // Delete button
        del.title = "✕"
        del.font = NSFont.systemFont(ofSize: 10)
        del.isBordered = false
        del.contentTintColor = kDim
        del.target = self
        del.action = #selector(deleteTapped)
        del.alphaValue = 0
        addSubview(del)

        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
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
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.10
            del.animator().alphaValue = 0.9
            layer?.borderWidth = 0.5
            layer?.backgroundColor = NSColor(red: 254/255.0, green: 240/255.0, blue: 138/255.0, alpha: 1.0).cgColor
        }
    }
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.10
            del.animator().alphaValue = 0
            layer?.borderWidth = 0.0
            layer?.backgroundColor = kSurface.cgColor
        }
    }

    @objc func toggleTapped() { onToggle?(reminder.id) }
    @objc func deleteTapped()  { onDelete?(reminder.id) }
    @objc func editTapped() {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "Edit todo"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
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

// MARK: - Add Panel

class AddPanel: NSView {
    var onAdd:    ((Reminder) -> Void)?
    var onCancel: (() -> Void)?

    private let titleField   = NSTextField()
    private let addBtn       = NSButton()
    private let cancelBtn    = NSButton()

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.backgroundColor = kBg.cgColor
        layer?.borderWidth = 2
        layer?.borderColor = kBorder.cgColor

        titleField.drawsBackground = true
        titleField.backgroundColor = .white
        titleField.textColor = .black
        titleField.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        titleField.focusRingType = .none
        titleField.isBordered = true
        titleField.bezelStyle = .squareBezel
        titleField.wantsLayer = true
        titleField.layer?.cornerRadius = 0
        titleField.layer?.borderWidth = 2
        titleField.layer?.borderColor = kBorder.cgColor
        
        let pAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(white: 0.45, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
        ]
        titleField.placeholderAttributedString = NSAttributedString(string: "What to do?", attributes: pAttrs)
        addSubview(titleField)

        styleBtn(addBtn, primary: true, title: "Add")
        addBtn.target = self; addBtn.action = #selector(addTapped)
        addSubview(addBtn)

        styleBtn(cancelBtn, primary: false, title: "Cancel")
        cancelBtn.target = self; cancelBtn.action = #selector(cancelTapped)
        addSubview(cancelBtn)
    }

    private func styleBtn(_ b: NSButton, primary: Bool, title: String) {
        b.title = title; b.isBordered = false; b.wantsLayer = true
        b.layer?.cornerRadius = 0
        b.layer?.borderWidth = 1.5
        b.layer?.borderColor = kBorder.cgColor
        b.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        b.layer?.backgroundColor = primary ? kAddBg.cgColor
            : NSColor(red: 245/255.0, green: 238/255.0, blue: 70/255.0, alpha: 1).cgColor
        b.contentTintColor = primary ? .white : .black
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

    func clear() {
        titleField.stringValue = ""
    }

    @objc func addTapped() {
        let t = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else {
            titleField.layer?.borderColor = NSColor.red.cgColor
            titleField.layer?.borderWidth = 2; return
        }
        onAdd?(Reminder(title: t))
    }
    @objc func cancelTapped() { onCancel?() }
}

// MARK: - Main Widget View

class WidgetView: NSView {
    private var rows: [UUID: ReminderRowView] = [:]
    private var filterIdx = 0
    private var panelShown = false

    // Drag state
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

    override init(frame: NSRect) { super.init(frame: frame); build(); reload() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(onThemeChanged),
            name: ThemeManager.notifName,
            object: nil
        )

        // Header label
        header.stringValue = "tututodo"
        header.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        header.textColor = kBlue
        header.isEditable = false; header.isBordered = false; header.backgroundColor = .clear
        addSubview(header)

        // Badge
        badge.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        badge.textColor = kBlue; badge.alignment = .center
        badge.isEditable = false; badge.isBordered = false; badge.backgroundColor = .clear
        badge.wantsLayer = true; badge.layer?.cornerRadius = 0
        badge.layer?.borderWidth = 1; badge.layer?.borderColor = kBorder.cgColor
        badge.layer?.backgroundColor = NSColor.white.cgColor
        addSubview(badge)

        // Custom Tabs
        activeTabBtn.target = self; activeTabBtn.action = #selector(activeTabTapped)
        doneTabBtn.target   = self; doneTabBtn.action   = #selector(doneTabTapped)
        addSubview(activeTabBtn)
        addSubview(doneTabBtn)
        updateTabStyles()

        // Add button
        addBtn.title = "+ Add"
        addBtn.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        addBtn.isBordered = false; addBtn.wantsLayer = true
        addBtn.layer?.cornerRadius = 0
        addBtn.layer?.backgroundColor = kAddBg.cgColor
        addBtn.contentTintColor = .white
        addBtn.target = self; addBtn.action = #selector(showPanel)
        addSubview(addBtn)

        // Clear done
        clearBtn.title = "Clear Done"
        clearBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        clearBtn.isBordered = false; clearBtn.contentTintColor = kBlue
        clearBtn.target = self; clearBtn.action = #selector(clearDone)
        addSubview(clearBtn)

        // Scroll
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.documentView = list
        addSubview(scroll)

        // Panel
        panel.isHidden = true; panel.alphaValue = 0
        panel.onAdd    = { [weak self] r in self?.doAdd(r) }
        panel.onCancel = { [weak self] in self?.hidePanel() }
        addSubview(panel)
    }

    @objc func activeTabTapped() {
        filterIdx = 0
        updateTabStyles()
        reload()
    }

    @objc func doneTabTapped() {
        filterIdx = 1
        updateTabStyles()
        reload()
    }

    private func updateTabStyles() {
        styleTabButton(activeTabBtn, title: "Active", isActive: filterIdx == 0)
        styleTabButton(doneTabBtn, title: "Done", isActive: filterIdx == 1)
    }

    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            }
        }
    }

    private func styleTabButton(_ btn: NSButton, title: String, isActive: Bool) {
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 0
        btn.layer?.borderWidth = isActive ? 1.5 : 0
        btn.layer?.borderColor = kBlue.cgColor
        btn.layer?.backgroundColor = isActive ? NSColor.white.cgColor : NSColor.clear.cgColor
        
        let attrTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: isActive ? .bold : .medium),
            .foregroundColor: kBlue
        ])
        btn.attributedTitle = attrTitle
    }

    // MARK: - Dragging (any click on empty space moves the window)
    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        dragActive = true
        window?.makeKey()
        super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { super.mouseDragged(with: event); return }
        let c = event.locationInWindow
        w.setFrameOrigin(NSPoint(x: w.frame.origin.x + c.x - dragStart.x,
                                  y: w.frame.origin.y + c.y - dragStart.y))
    }
    override func mouseUp(with event: NSEvent) {
        dragActive = false
        super.mouseUp(with: event)
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
    }

    // MARK: Data

    private func filtered() -> [Reminder] {
        switch filterIdx {
        case 1:  return ReminderStore.shared.items.filter {  $0.isCompleted }
        default: return ReminderStore.shared.items.filter { !$0.isCompleted }
        }
    }

    func reload() {
        let items = filtered()
        let pending = ReminderStore.shared.items.filter { !$0.isCompleted }.count
        badge.stringValue = "\(pending)"
        badge.isHidden = pending == 0

        for sub in list.subviews { sub.removeFromSuperview() }
        rows.removeAll()

        let rowH: CGFloat = 42, gap: CGFloat = 5
        let w = scroll.frame.width - 6
        let totalH = max(scroll.frame.height, CGFloat(items.count) * (rowH + gap))
        list.frame = NSRect(x: 0, y: 0, width: w, height: totalH)

        for (i, item) in items.enumerated() {
            let y = totalH - CGFloat(i + 1) * (rowH + gap)
            let row = ReminderRowView(item)
            row.frame = NSRect(x: 0, y: y, width: w, height: rowH)
            row.onToggle = { [weak self] id in ReminderStore.shared.toggle(id: id); self?.reload() }
            row.onDelete = { [weak self] id in self?.deleteAnim(id: id) }
            row.onEdit   = { [weak self] id, t in ReminderStore.shared.updateTitle(id: id, title: t); self?.reload() }
            list.addSubview(row)
            rows[item.id] = row
        }
    }

    private func deleteAnim(id: UUID) {
        guard let row = rows[id] else { ReminderStore.shared.delete(id: id); reload(); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            row.animator().alphaValue = 0
            row.animator().frame = NSRect(x: row.frame.width, y: row.frame.origin.y,
                                          width: row.frame.width, height: row.frame.height)
        } completionHandler: { [weak self] in
            ReminderStore.shared.delete(id: id); self?.reload()
        }
    }

    private func doAdd(_ r: Reminder) { ReminderStore.shared.add(r); hidePanel(); reload() }

    @objc func showPanel() {
        guard !panelShown else { return }
        panel.clear()
        panelShown = true; panel.isHidden = false; window?.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.18
            panel.animator().alphaValue = 1
            scroll.animator().alphaValue = 0.25
        }
    }

    func hidePanel() {
        guard panelShown else { return }
        panelShown = false
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.18
            panel.animator().alphaValue = 0
            scroll.animator().alphaValue = 1
        } completionHandler: { [weak self] in self?.panel.isHidden = true }
    }

    @objc func clearDone()     { ReminderStore.shared.clearCompleted(); reload() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { hidePanel() } else { super.keyDown(with: event) }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 24, y: 600, width: 280, height: 440)
        window = WidgetWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: -1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false
        window.contentView = WidgetView(frame: rect)
        window.makeKeyAndOrderFront(nil)
    }

    @objc func show() { window.makeKeyAndOrderFront(nil) }
}

// MARK: - Run

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
