import AppKit
import CoreImage
import Foundation

// MARK: - 1. REMINDERS WIDGET (tututodo)
struct Reminder: Codable {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var isStarred: Bool
    var createdAt: Date
    var updatedAt: Double
    var isDeleted: Bool

    init(title: String, isStarred: Bool = false) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
        self.isStarred = isStarred
        self.createdAt = Date()
        self.updatedAt = Date().timeIntervalSince1970
        self.isDeleted = false
    }

    enum CodingKeys: String, CodingKey {
        case id, title, isCompleted, isStarred, createdAt, updatedAt, isDeleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        isStarred = try container.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Double.self, forKey: .updatedAt) ?? createdAt.timeIntervalSince1970
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }
}

final class ReminderStore {
    static let shared = ReminderStore()
    private let url = AppPaths.file("reminders.json")
    private(set) var allRecords: [Reminder] = []

    var items: [Reminder] {
        allRecords.filter { !$0.isDeleted }
    }

    private init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Reminder].self, from: data) else { return }
        allRecords = decoded
        pruneOldTombstones()
    }

    func save(pushCloud: Bool = true) {
        pruneOldTombstones()
        if let data = try? JSONEncoder().encode(allRecords) {
            AppPaths.writeAtomically(data, to: url)
        }
        if pushCloud {
            TutuSyncServer.shared.pushStateToCloud()
        }
    }

    var latestUpdatedAt: Double {
        allRecords.map(\.updatedAt).max() ?? 0
    }

    /// Per-task conflict-safe merge using `updatedAt` timestamps and soft-delete tombstones.
    func mergeFromRemote(_ remoteItems: [Reminder]) {
        var byID: [UUID: Reminder] = Dictionary(uniqueKeysWithValues: allRecords.map { ($0.id, $0) })
        for remote in remoteItems {
            if let local = byID[remote.id] {
                if remote.updatedAt > local.updatedAt {
                    byID[remote.id] = remote
                }
            } else if !remote.isDeleted {
                byID[remote.id] = remote
            }
        }
        allRecords = Array(byID.values).sorted { $0.createdAt < $1.createdAt }
        save(pushCloud: false)
    }

    /// Authoritative sync for legacy mobile clients (e.g. tututodo v1.0.1 APK) that omit deleted
    /// tasks from the array instead of sending `isDeleted` tombstones or per-task `updatedAt`.
    func replaceFromLegacyRemote(_ remoteItems: [Reminder]) {
        allRecords = remoteItems.sorted { $0.createdAt < $1.createdAt }
        save(pushCloud: false)
    }

    private func pruneOldTombstones() {
        let cutoff = Date().timeIntervalSince1970 - (7 * 24 * 3600)
        allRecords.removeAll { $0.isDeleted && $0.updatedAt < cutoff }
    }

    func add(_ r: Reminder) {
        allRecords.append(r)
        save()
    }

    func toggle(id: UUID) {
        if let i = allRecords.firstIndex(where: { $0.id == id }) {
            allRecords[i].isCompleted.toggle()
            allRecords[i].updatedAt = Date().timeIntervalSince1970
            save()
        }
    }

    func toggleStar(id: UUID) {
        if let i = allRecords.firstIndex(where: { $0.id == id }) {
            allRecords[i].isStarred.toggle()
            allRecords[i].updatedAt = Date().timeIntervalSince1970
            save()
        }
    }

    func delete(id: UUID) {
        if let i = allRecords.firstIndex(where: { $0.id == id }) {
            allRecords[i].isDeleted = true
            allRecords[i].updatedAt = Date().timeIntervalSince1970
            save()
        }
    }

    func clearCompleted() {
        let now = Date().timeIntervalSince1970
        for i in allRecords.indices where allRecords[i].isCompleted && !allRecords[i].isDeleted {
            allRecords[i].isDeleted = true
            allRecords[i].updatedAt = now
        }
        save()
    }

    func updateTitle(id: UUID, title: String) {
        if let i = allRecords.firstIndex(where: { $0.id == id }) {
            allRecords[i].title = title
            allRecords[i].updatedAt = Date().timeIntervalSince1970
            save()
        }
    }
}

class ReminderRowView: NSView {
    var reminder: Reminder { didSet { updateUI() } }
    var onToggle:     ((UUID) -> Void)?
    var onStarToggle: ((UUID) -> Void)?
    var onDelete:     ((UUID) -> Void)?
    var onEdit:       ((UUID, String) -> Void)?

    private let check   = NSButton()
    private let label   = NSTextField()
    private let starBtn = NSButton()
    private let del     = NSButton()

    init(_ reminder: Reminder) {
        self.reminder = reminder
        super.init(frame: .zero)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = kRadius / 2
        layer?.backgroundColor = kSurface.cgColor
        layer?.borderWidth = 0.0

        check.isBordered = false; check.bezelStyle = .regularSquare; check.setButtonType(.momentaryChange)
        check.wantsLayer = true; check.layer?.cornerRadius = 4; check.layer?.borderWidth = kBorderWidth; check.layer?.borderColor = kBorder.cgColor
        check.target = self; check.action = #selector(toggleTapped); addSubview(check)

        label.isBordered = false; label.backgroundColor = .clear; label.isEditable = false
        label.lineBreakMode = .byTruncatingTail
        let dclick = NSClickGestureRecognizer(target: self, action: #selector(editTapped))
        dclick.numberOfClicksRequired = 2
        label.addGestureRecognizer(dclick)
        addSubview(label)

        starBtn.isBordered = false; starBtn.wantsLayer = true; starBtn.layer?.cornerRadius = 5
        starBtn.layer?.borderWidth = kBorderWidth; starBtn.layer?.borderColor = kBorder.cgColor
        starBtn.target = self; starBtn.action = #selector(starTapped)
        addSubview(starBtn)

        del.title = "✕"; del.font = dynamicFont(size: 10); del.isBordered = false
        del.contentTintColor = kDim; del.target = self; del.action = #selector(deleteTapped); del.alphaValue = 0
        addSubview(del)

        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)

        updateUI()
    }

    func updateUI() {
        layer?.backgroundColor = kSurface.cgColor
        check.layer?.borderColor = kBorder.cgColor
        check.layer?.backgroundColor = reminder.isCompleted ? kBorder.cgColor : NSColor.clear.cgColor
        if reminder.isCompleted {
            check.attributedTitle = NSAttributedString(string: "✓", attributes: [.font: dynamicFont(size: 10, weight: .bold), .foregroundColor: NSColor.white])
        } else {
            check.title = ""
        }

        if reminder.isCompleted {
            let s = NSMutableAttributedString(string: reminder.title)
            let r = NSRange(location: 0, length: reminder.title.utf16.count)
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            s.addAttribute(.foregroundColor, value: kDim, range: r)
            label.attributedStringValue = s
            layer?.borderWidth = 0.0
            layer?.borderColor = NSColor.clear.cgColor
            starBtn.layer?.backgroundColor = NSColor.clear.cgColor
            starBtn.layer?.borderColor = kBorder.withAlphaComponent(0.3).cgColor
            starBtn.attributedTitle = NSAttributedString(string: "★", attributes: [.font: dynamicFont(size: 12, weight: .bold), .foregroundColor: kDim.withAlphaComponent(0.4)])
            starBtn.alphaValue = 0.4
        } else if reminder.isStarred {
            let starAmber = NSColor(hex: "#F59E0B")!
            label.stringValue = reminder.title
            label.textColor = starAmber
            label.font = dynamicFont(size: 13, weight: .bold)
            layer?.borderWidth = kBorderWidth + 0.5
            layer?.borderColor = starAmber.withAlphaComponent(0.6).cgColor
            starBtn.layer?.backgroundColor = starAmber.cgColor
            starBtn.layer?.borderColor = NSColor(hex: "#D97706")!.cgColor
            starBtn.attributedTitle = NSAttributedString(string: "★", attributes: [.font: dynamicFont(size: 13, weight: .bold), .foregroundColor: NSColor.white])
            starBtn.alphaValue = 1.0
        } else {
            label.stringValue = reminder.title
            label.textColor = kText
            label.font = dynamicFont(size: 13, weight: .medium)
            layer?.borderWidth = 0.0
            layer?.borderColor = NSColor.clear.cgColor
            starBtn.layer?.backgroundColor = NSColor.clear.cgColor
            starBtn.layer?.borderColor = kBorder.cgColor
            starBtn.attributedTitle = NSAttributedString(string: "★", attributes: [.font: dynamicFont(size: 12, weight: .bold), .foregroundColor: kDim.withAlphaComponent(0.6)])
            starBtn.alphaValue = 0.6
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height, w = bounds.width
        check.frame   = NSRect(x: 10, y: (h - 18) / 2, width: 18, height: 18)
        starBtn.frame = NSRect(x: w - 52, y: (h - 24) / 2, width: 24, height: 24)
        del.frame     = NSRect(x: w - 24, y: (h - 18) / 2, width: 18, height: 18)
        label.frame   = NSRect(x: 34, y: (h - 18) / 2, width: w - 90, height: 18)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            del.animator().alphaValue = 0.9
            if !reminder.isStarred && !reminder.isCompleted {
                starBtn.animator().alphaValue = 0.9
            }
            if !reminder.isStarred {
                layer?.borderWidth = kBorderWidth
                layer?.borderColor = kBorder.cgColor
            }
            layer?.backgroundColor = kSurface.withAlphaComponent(0.85).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            del.animator().alphaValue = 0
            if !reminder.isStarred && !reminder.isCompleted {
                starBtn.animator().alphaValue = 0.5
            }
            if !reminder.isStarred {
                layer?.borderWidth = 0.0
            }
            layer?.backgroundColor = kSurface.cgColor
        }
    }

    @objc func toggleTapped() { onToggle?(reminder.id) }
    @objc func starTapped()   { onStarToggle?(reminder.id) }
    @objc func deleteTapped() { onDelete?(reminder.id) }
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

class AddPanel: NSView, NSTextFieldDelegate {
    var onAdd:    ((Reminder) -> Void)?
    var onCancel: (() -> Void)?

    private let titleField = NSTextField()
    private let addBtn     = NSButton()
    private let cancelBtn  = NSButton()

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        titleField.drawsBackground = true
        titleField.focusRingType = .none
        titleField.isBordered = true
        titleField.bezelStyle = .squareBezel
        titleField.wantsLayer = true
        titleField.delegate = self
        addSubview(titleField)

        addBtn.target = self; addBtn.action = #selector(addTapped); addBtn.keyEquivalent = "\r"; addSubview(addBtn)
        cancelBtn.target = self; cancelBtn.action = #selector(cancelTapped); cancelBtn.keyEquivalent = "\u{1b}"; addSubview(cancelBtn)

        refreshTheme()
    }

    func refreshTheme() {
        layer?.cornerRadius = kRadius
        layer?.backgroundColor = kBg.cgColor
        layer?.borderWidth = kBorderWidth
        layer?.borderColor = kBorder.cgColor

        titleField.backgroundColor = kSurface
        titleField.textColor = kText
        titleField.font = dynamicFont(size: 14, weight: .bold)
        titleField.layer?.cornerRadius = kRadius / 2
        titleField.layer?.borderWidth = kBorderWidth
        titleField.layer?.borderColor = kBorder.cgColor

        let pAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: kDim, .font: dynamicFont(size: 13, weight: .medium)]
        titleField.placeholderAttributedString = NSAttributedString(string: "What to do? (Enter to add, Esc to cancel)", attributes: pAttrs)

        styleBtn(addBtn, primary: true, title: "Add")
        styleBtn(cancelBtn, primary: false, title: "Cancel")
    }

    private func styleBtn(_ b: NSButton, primary: Bool, title: String) {
        b.title = title; b.isBordered = false; b.wantsLayer = true; b.layer?.cornerRadius = kRadius / 2
        b.layer?.borderWidth = kBorderWidth; b.layer?.borderColor = kBorder.cgColor; b.font = dynamicFont(size: 12, weight: .bold)
        b.layer?.backgroundColor = primary ? kAddBg.cgColor : kSurface.cgColor
        b.contentTintColor = primary ? (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish ? .white : kSurface) : kText
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleField.frame = NSRect(x: 14, y: h - 54, width: w - 28, height: 34)
        cancelBtn.frame  = NSRect(x: 14, y: 14, width: (w - 36) / 2, height: 32)
        addBtn.frame     = NSRect(x: 22 + (w - 36) / 2, y: 14, width: (w - 36) / 2, height: 32)
    }

    func focusField() {
        titleField.layer?.borderColor = kBorder.cgColor
        titleField.layer?.borderWidth = kBorderWidth
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.makeKey()
            self.window?.makeFirstResponder(self.titleField)
        }
    }

    func clear() { titleField.stringValue = "" }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            addTapped()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelTapped()
            return true
        }
        return false
    }

    @objc func addTapped() {
        let t = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else {
            titleField.layer?.borderColor = NSColor.red.cgColor
            titleField.layer?.borderWidth = 2
            return
        }
        onAdd?(Reminder(title: t))
    }

    @objc func cancelTapped() { onCancel?() }
}

class PhoneQRPanel: NSView {
    var onClose: (() -> Void)?

    private let titleLabel = NSTextField()
    private let qrView     = NSImageView()
    private let urlLabel   = NSTextField()
    private let copyBtn    = NSButton()
    private let closeBtn   = NSButton()
    private var currentUrl = "http://127.0.0.1:4321/"

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        titleLabel.stringValue = "MOBILE LIVE SYNC"
        titleLabel.alignment = .center
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        qrView.wantsLayer = true
        qrView.layer?.backgroundColor = NSColor.white.cgColor
        qrView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(qrView)

        urlLabel.alignment = .center
        urlLabel.isEditable = false; urlLabel.isBordered = false; urlLabel.backgroundColor = .clear
        addSubview(urlLabel)

        copyBtn.target = self; copyBtn.action = #selector(copyTapped); addSubview(copyBtn)
        closeBtn.target = self; closeBtn.action = #selector(closeTapped); addSubview(closeBtn)

        refreshQR()
    }

    func styleBtn(_ b: NSButton, primary: Bool, title: String) {
        b.title = title; b.isBordered = false; b.wantsLayer = true
        b.layer?.cornerRadius = kRadius / 2
        b.layer?.borderWidth = kBorderWidth
        b.layer?.borderColor = kBorder.cgColor
        b.font = dynamicFont(size: 11, weight: .bold)
        b.layer?.backgroundColor = primary ? kAddBg.cgColor : kSurface.cgColor
        b.contentTintColor = primary ? (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish ? .white : kSurface) : kText
    }

    func refreshQR() {
        layer?.cornerRadius = kRadius
        layer?.backgroundColor = kBg.cgColor
        layer?.borderWidth = kBorderWidth + 1
        layer?.borderColor = kBorder.cgColor
        qrView.layer?.borderWidth = kBorderWidth
        qrView.layer?.borderColor = kBorder.cgColor

        titleLabel.textColor = kText
        titleLabel.font = dynamicFont(size: 11, weight: .bold)
        urlLabel.textColor = kDim
        urlLabel.font = dynamicFont(size: 9, weight: .bold)
        styleBtn(copyBtn, primary: false, title: "Copy URL")
        styleBtn(closeBtn, primary: true, title: "Done")

        currentUrl = TutuSyncServer.shared.pairingURL()
        let ip = TutuSyncServer.shared.getLanIP()
        urlLabel.stringValue = "http://\(ip):4321 (Token Protected)"

        if let data = currentUrl.data(using: .utf8),
           let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            if let output = filter.outputImage {
                let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
                let rep = NSCIImageRep(ciImage: scaled)
                let img = NSImage(size: rep.size)
                img.addRepresentation(rep)
                qrView.image = img
            }
        }
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleLabel.frame = NSRect(x: 10, y: h - 26, width: w - 20, height: 18)
        let qrSize: CGFloat = 148
        qrView.frame     = NSRect(x: (w - qrSize) / 2, y: h - 32 - qrSize, width: qrSize, height: qrSize)
        urlLabel.frame   = NSRect(x: 8, y: 46, width: w - 16, height: 16)
        copyBtn.frame    = NSRect(x: 12, y: 12, width: (w - 32) / 2, height: 28)
        closeBtn.frame   = NSRect(x: 20 + (w - 32) / 2, y: 12, width: (w - 32) / 2, height: 28)
    }

    @objc private func copyTapped() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentUrl, forType: .string)
        copyBtn.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyBtn.title = "Copy URL"
        }
    }

    @objc private func closeTapped() { onClose?() }
}

class TodoView: BaseWidgetView {
    private var rows: [UUID: ReminderRowView] = [:]
    private var filterIdx = 0
    private var panelShown = false
    private var qrShown = false

    private let scroll       = NSScrollView()
    private let list         = NSView()
    private let panel        = AddPanel()
    private let qrPanel      = PhoneQRPanel()
    private let header       = NSTextField()
    private let badge        = NSTextField()
    private let addBtn       = NSButton()
    private let clearBtn     = NSButton()
    private let syncBtn      = NSButton()
    private let activeTabBtn = NSButton()
    private let doneTabBtn   = NSButton()

    init(frame: NSRect) {
        super.init(frame: frame, widgetKey: "reminders")
        build()
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(onInMemoryTodoSync), name: NSNotification.Name("com.user.tututodo.reload"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onExternalTodoSync), name: NSNotification.Name("com.user.tututodo.reload"), object: nil)
        TutuSyncServer.shared.start()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let headerCell = CenteredTextFieldCell(textCell: "tututodo")
        headerCell.alignment = .left; headerCell.font = dynamicFont(size: 17, weight: .bold); headerCell.textColor = kText
        header.cell = headerCell; header.stringValue = "tututodo"
        header.isEditable = false; header.isBordered = false; header.drawsBackground = false; header.backgroundColor = .clear
        addSubview(header)

        let badgeCell = CenteredTextFieldCell(textCell: "")
        badgeCell.alignment = .center; badgeCell.font = dynamicFont(size: 10, weight: .bold); badgeCell.textColor = kText
        badge.cell = badgeCell
        badge.isEditable = false; badge.isBordered = false; badge.drawsBackground = false; badge.backgroundColor = .clear; badge.wantsLayer = true
        badge.layer?.cornerRadius = kRadius / 2; badge.layer?.borderWidth = kBorderWidth; badge.layer?.borderColor = kBorder.cgColor
        badge.layer?.backgroundColor = kSurface.cgColor
        addSubview(badge)

        activeTabBtn.target = self; activeTabBtn.action = #selector(activeTabTapped); addSubview(activeTabBtn)
        doneTabBtn.target   = self; doneTabBtn.action   = #selector(doneTabTapped); addSubview(doneTabBtn)
        updateTabStyles()

        addBtn.title = "+ Add"; addBtn.font = dynamicFont(size: 12, weight: .bold); addBtn.isBordered = false
        addBtn.wantsLayer = true; addBtn.layer?.cornerRadius = kRadius / 2; addBtn.layer?.borderWidth = kBorderWidth; addBtn.layer?.borderColor = kBorder.cgColor
        addBtn.layer?.backgroundColor = kAddBg.cgColor; addBtn.tag = 100
        addBtn.contentTintColor = (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish) ? .white : kSurface
        addBtn.target = self; addBtn.action = #selector(showPanel); addSubview(addBtn)

        clearBtn.title = "Clear Done"; clearBtn.font = dynamicFont(size: 11, weight: .medium)
        clearBtn.isBordered = false; clearBtn.contentTintColor = kText; clearBtn.target = self; clearBtn.action = #selector(clearDone); addSubview(clearBtn)

        syncBtn.title = "Sync"; syncBtn.font = dynamicFont(size: 10, weight: .bold)
        syncBtn.isBordered = false; syncBtn.wantsLayer = true
        syncBtn.layer?.cornerRadius = kRadius / 2; syncBtn.layer?.borderWidth = kBorderWidth; syncBtn.layer?.borderColor = kBorder.cgColor
        syncBtn.layer?.backgroundColor = kSurface.cgColor; syncBtn.contentTintColor = kText
        syncBtn.target = self; syncBtn.action = #selector(toggleQRPanel)
        addSubview(syncBtn)

        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false; scroll.documentView = list; addSubview(scroll)

        panel.isHidden = true; panel.alphaValue = 0
        panel.onAdd    = { [weak self] r in self?.doAdd(r) }
        panel.onCancel = { [weak self] in self?.hidePanel() }
        addSubview(panel)

        qrPanel.isHidden = true; qrPanel.alphaValue = 0
        qrPanel.onClose = { [weak self] in self?.hideQRPanel() }
        addSubview(qrPanel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        header.frame    = NSRect(x: 14, y: h - 40, width: 88, height: 24)
        badge.frame     = NSRect(x: 106, y: h - 38, width: 26, height: 20)
        addBtn.frame    = NSRect(x: w - 78, y: h - 40, width: 64, height: 24)

        let tabW = (w - 28) / 2
        activeTabBtn.frame = NSRect(x: 14, y: h - 72, width: tabW, height: 24)
        doneTabBtn.frame   = NSRect(x: 14 + tabW, y: h - 72, width: tabW, height: 24)

        clearBtn.frame  = NSRect(x: 14, y: 10, width: 82, height: 18)
        syncBtn.frame   = NSRect(x: w - 84, y: 9, width: 70, height: 20)
        scroll.frame    = NSRect(x: 10, y: 34, width: w - 20, height: h - 112)
        panel.frame     = NSRect(x: 10, y: h / 2 - 78, width: w - 20, height: 156)
        qrPanel.frame   = NSRect(x: 12, y: h / 2 - 125, width: w - 24, height: 250)
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
        btn.layer?.borderWidth = kBorderWidth
        btn.layer?.borderColor = kBorder.cgColor
        btn.layer?.backgroundColor = isActive ? kSurface.cgColor : NSColor.clear.cgColor
        btn.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: dynamicFont(size: 11, weight: isActive ? .bold : .medium),
            .foregroundColor: kText
        ])
    }

    private func filtered() -> [Reminder] {
        let raw = filterIdx == 1
            ? ReminderStore.shared.items.filter { $0.isCompleted }
            : ReminderStore.shared.items.filter { !$0.isCompleted }
        return raw.sorted { a, b in
            if a.isStarred != b.isStarred { return a.isStarred && !b.isStarred }
            return a.createdAt > b.createdAt
        }
    }

    func reload() {
        let pending = ReminderStore.shared.items.filter { !$0.isCompleted }.count
        badge.stringValue = "\(pending)"
        badge.isHidden = pending == 0

        let filterList = filtered()
        let currentIDs = Set(filterList.map { $0.id })
        for (id, v) in rows where !currentIDs.contains(id) {
            v.removeFromSuperview()
            rows.removeValue(forKey: id)
        }

        for r in filterList {
            if let existing = rows[r.id] {
                existing.reminder = r
            } else {
                let row = ReminderRowView(r)
                row.onToggle     = { [weak self] id in self?.doToggle(id) }
                row.onStarToggle = { [weak self] id in self?.doStarToggle(id) }
                row.onDelete     = { [weak self] id in self?.doDelete(id) }
                row.onEdit       = { [weak self] id, t in self?.doEdit(id, t) }
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
        hideQRPanel()
        guard !panelShown else { return }
        panelShown = true; panel.clear(); panel.refreshTheme(); panel.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18; panel.animator().alphaValue = 1
        }
        panel.focusField()
    }

    func hidePanel() {
        guard panelShown else { return }
        panelShown = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15; panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.panelShown == false { self?.panel.isHidden = true }
        })
    }

    @objc func toggleQRPanel() {
        if qrShown {
            hideQRPanel()
        } else {
            hidePanel()
            qrShown = true
            qrPanel.refreshQR()
            qrPanel.isHidden = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18; qrPanel.animator().alphaValue = 1
            }
        }
    }

    func hideQRPanel() {
        guard qrShown else { return }
        qrShown = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15; qrPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.qrShown == false { self?.qrPanel.isHidden = true }
        })
    }

    private func doAdd(_ r: Reminder) { ReminderStore.shared.add(r); hidePanel(); reload() }
    private func doToggle(_ id: UUID) { ReminderStore.shared.toggle(id: id); reload() }
    private func doStarToggle(_ id: UUID) { ReminderStore.shared.toggleStar(id: id); reload() }
    private func doDelete(_ id: UUID) { ReminderStore.shared.delete(id: id); reload() }
    private func doEdit(_ id: UUID, _ title: String) { ReminderStore.shared.updateTitle(id: id, title: title); reload() }
    @objc func clearDone() { ReminderStore.shared.clearCompleted(); reload() }

    @objc private func onInMemoryTodoSync() {
        DispatchQueue.main.async { self.reload(); self.needsDisplay = true }
    }

    @objc private func onExternalTodoSync() {
        DispatchQueue.main.async { ReminderStore.shared.load(); self.reload(); self.needsDisplay = true }
    }

    override func applyTheme(preset: ThemePreset) {
        badge.layer?.backgroundColor = kSurface.cgColor
        badge.layer?.borderColor = kBorder.cgColor
        badge.layer?.borderWidth = kBorderWidth
        addBtn.layer?.backgroundColor = kAddBg.cgColor
        addBtn.layer?.borderColor = kBorder.cgColor
        addBtn.contentTintColor = (preset == .glass || preset == .childish) ? .white : kSurface
        syncBtn.layer?.backgroundColor = kSurface.cgColor
        syncBtn.layer?.borderColor = kBorder.cgColor
        syncBtn.contentTintColor = kText
        updateTabStyles()
        panel.refreshTheme()
        qrPanel.refreshQR()
        updateThemeRecursively(preset: preset)
        reload()
    }
}
