import AppKit
import Foundation

// MARK: - 1.5 RECURRING HABITS / DAILY TASKS WIDGET (Resets Daily at 2:00 AM)
struct Habit: Codable {
    var id: UUID
    var title: String
    var completedDates: [String] // "YYYY-MM-DD"
    var createdAt: Date

    init(title: String) {
        self.id = UUID()
        self.title = title
        self.completedDates = []
        self.createdAt = Date()
    }

    func isCompleted(on cycleKey: String) -> Bool {
        completedDates.contains(cycleKey)
    }

    mutating func toggle(on cycleKey: String) {
        if let idx = completedDates.firstIndex(of: cycleKey) {
            completedDates.remove(at: idx)
        } else {
            completedDates.append(cycleKey)
        }
    }
}

final class HabitStore {
    static let shared = HabitStore()
    private let url = AppPaths.file("recurring_habits.json")
    private(set) var items: [Habit] = []

    private init() {
        load()
        if items.isEmpty {
            // Generalized starter habits (double-click any habit to edit or hover to delete)
            items = [
                Habit(title: "Deep focus session (45m)"),
                Habit(title: "Read 20 pages"),
                Habit(title: "Review daily notes")
            ]
            save()
        }
    }

    static func currentCycleKey(for date: Date = Date()) -> String {
        let cal = Calendar.current
        // Shift time by -2 hours so 00:00–01:59 stays on the previous day cycle and rolls over at 2:00 AM.
        let shifted = cal.date(byAdding: .hour, value: -2, to: date) ?? date
        let comp = cal.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", comp.year!, comp.month!, comp.day!)
    }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Habit].self, from: data) else { return }
        items = decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(items) {
            AppPaths.writeAtomically(data, to: url)
        }
    }

    func add(_ habit: Habit) { items.append(habit); save() }

    func toggle(id: UUID) {
        let key = HabitStore.currentCycleKey()
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].toggle(on: key)
            save()
        }
    }

    func delete(id: UUID) { items.removeAll { $0.id == id }; save() }

    func updateTitle(id: UUID, title: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].title = title
            save()
        }
    }
}

class HabitRowView: NSView {
    var habit: Habit { didSet { updateUI() } }
    var currentCycleKey: String { didSet { updateUI() } }
    var onToggle: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onEdit: ((UUID, String) -> Void)?

    private let check = NSButton()
    private let label = NSTextField()
    private let del = NSButton()

    init(habit: Habit, currentCycleKey: String) {
        self.habit = habit
        self.currentCycleKey = currentCycleKey
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
        check.wantsLayer = true; check.layer?.cornerRadius = 5; check.layer?.borderWidth = kBorderWidth; check.layer?.borderColor = kBorder.cgColor
        check.target = self; check.action = #selector(toggleTapped)
        addSubview(check)

        label.isBordered = false; label.backgroundColor = .clear; label.isEditable = false
        label.lineBreakMode = .byTruncatingTail
        let dclick = NSClickGestureRecognizer(target: self, action: #selector(editTapped))
        dclick.numberOfClicksRequired = 2
        label.addGestureRecognizer(dclick)
        addSubview(label)

        del.title = "✕"; del.font = dynamicFont(size: 10); del.isBordered = false
        del.contentTintColor = kDim; del.target = self; del.action = #selector(deleteTapped); del.alphaValue = 0
        addSubview(del)

        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)

        updateUI()
    }

    func updateUI() {
        let isDone = habit.isCompleted(on: currentCycleKey)
        let doneGreen = NSColor(hex: "#10B981") ?? kAccent
        layer?.backgroundColor = kSurface.cgColor
        check.layer?.backgroundColor = isDone ? doneGreen.cgColor : NSColor.clear.cgColor
        check.layer?.borderColor = isDone ? doneGreen.cgColor : kBorder.cgColor

        if isDone {
            check.attributedTitle = NSAttributedString(string: "✓", attributes: [.font: dynamicFont(size: 10, weight: .bold), .foregroundColor: NSColor.white])
            let s = NSMutableAttributedString(string: habit.title)
            let r = NSRange(location: 0, length: habit.title.utf16.count)
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            s.addAttribute(.foregroundColor, value: kDim, range: r)
            label.attributedStringValue = s
        } else {
            check.title = ""
            label.stringValue = habit.title
            label.textColor = kText
            label.font = dynamicFont(size: 13, weight: .medium)
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height, w = bounds.width
        check.frame = NSRect(x: 10, y: (h - 18) / 2, width: 18, height: 18)
        del.frame   = NSRect(x: w - 26, y: (h - 18) / 2, width: 18, height: 18)
        label.frame = NSRect(x: 34, y: (h - 18) / 2, width: w - 64, height: 18)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            del.animator().alphaValue = 0.9
            layer?.backgroundColor = kSurface.withAlphaComponent(0.85).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            del.animator().alphaValue = 0
            layer?.backgroundColor = kSurface.cgColor
        }
    }

    @objc func toggleTapped() { onToggle?(habit.id) }
    @objc func deleteTapped() { onDelete?(habit.id) }
    @objc func editTapped() {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "Edit Recurring Habit"
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        tf.stringValue = habit.title
        alert.accessoryView = tf
        alert.beginSheetModal(for: window) { [weak self] r in
            guard let self = self else { return }
            if r == .alertFirstButtonReturn {
                let t = tf.stringValue.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { self.onEdit?(self.habit.id, t) }
            }
        }
        DispatchQueue.main.async { tf.becomeFirstResponder() }
    }
}

class AddHabitPanel: NSView, NSTextFieldDelegate {
    var onAdd: ((Habit) -> Void)?
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
        titleField.font = dynamicFont(size: 13, weight: .bold)
        titleField.layer?.cornerRadius = kRadius / 2
        titleField.layer?.borderWidth = kBorderWidth
        titleField.layer?.borderColor = kBorder.cgColor

        let pAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: kDim, .font: dynamicFont(size: 12, weight: .medium)]
        titleField.placeholderAttributedString = NSAttributedString(string: "Daily habit (Enter to add)", attributes: pAttrs)

        styleBtn(addBtn, primary: true, title: "Add")
        styleBtn(cancelBtn, primary: false, title: "Cancel")
    }

    private func styleBtn(_ b: NSButton, primary: Bool, title: String) {
        b.title = title; b.isBordered = false; b.wantsLayer = true
        b.layer?.cornerRadius = kRadius / 2; b.layer?.borderWidth = kBorderWidth; b.layer?.borderColor = kBorder.cgColor
        b.font = dynamicFont(size: 11, weight: .bold)
        b.layer?.backgroundColor = primary ? kAddBg.cgColor : kSurface.cgColor
        b.contentTintColor = primary ? (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish ? .white : kSurface) : kText
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleField.frame = NSRect(x: 12, y: h - 44, width: w - 24, height: 30)
        cancelBtn.frame  = NSRect(x: 12, y: 10, width: (w - 30) / 2, height: 28)
        addBtn.frame     = NSRect(x: 18 + (w - 30) / 2, y: 10, width: (w - 30) / 2, height: 28)
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
            addTapped(); return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelTapped(); return true
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
        onAdd?(Habit(title: t))
    }

    @objc func cancelTapped() { onCancel?() }
}

class DraggableListContainer: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

class HabitsView: BaseWidgetView {
    override var mouseDownCanMoveWindow: Bool { true }
    private var rows: [UUID: HabitRowView] = [:]
    private var panelShown = false
    private var lastCycleKey: String = HabitStore.currentCycleKey()

    private let scroll    = NSScrollView()
    private let list      = DraggableListContainer()
    private let panel     = AddHabitPanel()
    private let header    = NSTextField()
    private let badge     = NSTextField()
    private let addBtn    = NSButton()
    private var refreshTimer: Timer?

    init(frame: NSRect) {
        super.init(frame: frame, widgetKey: "habits")
        build()
        reload()
        setupCycleRefresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { refreshTimer?.invalidate() }

    private func setupCycleRefresh() {
        NotificationCenter.default.addObserver(self, selector: #selector(checkCycle), name: .NSCalendarDayChanged, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(checkCycle), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onWindowMoved), name: NSWindow.didMoveNotification, object: nil)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkCycle()
        }
    }

    @objc private func onWindowMoved(_ notif: Notification) {
        guard let w = self.window, (notif.object as? NSWindow) == w else { return }
        PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin)
    }

    @objc private func checkCycle() {
        let newCycle = HabitStore.currentCycleKey()
        if newCycle != lastCycleKey {
            lastCycleKey = newCycle
            DispatchQueue.main.async { self.reload() }
        }
    }

    private func build() {
        let headerCell = CenteredTextFieldCell(textCell: "DAILY HABITS")
        headerCell.alignment = .left; headerCell.font = dynamicFont(size: 13.5, weight: .bold); headerCell.textColor = kText
        header.cell = headerCell; header.stringValue = "DAILY HABITS"
        header.isEditable = false; header.isBordered = false; header.drawsBackground = false; header.backgroundColor = .clear
        addSubview(header)

        let badgeCell = CenteredTextFieldCell(textCell: "")
        badgeCell.alignment = .center; badgeCell.font = dynamicFont(size: 10, weight: .bold); badgeCell.textColor = kText
        badge.cell = badgeCell
        badge.isEditable = false; badge.isBordered = false; badge.drawsBackground = false; badge.backgroundColor = .clear; badge.wantsLayer = true
        badge.layer?.cornerRadius = kRadius / 2; badge.layer?.borderWidth = kBorderWidth; badge.layer?.borderColor = kBorder.cgColor
        badge.layer?.backgroundColor = kSurface.cgColor
        addSubview(badge)

        addBtn.title = "+ Add"; addBtn.font = dynamicFont(size: 11, weight: .bold); addBtn.isBordered = false
        addBtn.wantsLayer = true; addBtn.layer?.cornerRadius = kRadius / 2; addBtn.layer?.borderWidth = kBorderWidth; addBtn.layer?.borderColor = kBorder.cgColor
        addBtn.layer?.backgroundColor = kAddBg.cgColor; addBtn.tag = 100
        addBtn.contentTintColor = (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish) ? .white : kSurface
        addBtn.target = self; addBtn.action = #selector(showPanel)
        addSubview(addBtn)

        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false; scroll.documentView = list
        addSubview(scroll)

        panel.isHidden = true; panel.alphaValue = 0
        panel.onAdd = { [weak self] h in self?.doAdd(h) }
        panel.onCancel = { [weak self] in self?.hidePanel() }
        addSubview(panel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        header.frame = NSRect(x: 12, y: h - 34, width: 108, height: 22)
        badge.frame  = NSRect(x: 124, y: h - 34, width: 66, height: 22)
        addBtn.frame = NSRect(x: w - 68, y: h - 34, width: 56, height: 22)
        scroll.frame = NSRect(x: 8, y: 8, width: w - 16, height: h - 46)
        panel.frame  = NSRect(x: 8, y: h - 132, width: w - 16, height: 86)
        layoutList()
    }

    func reload() {
        let cycleKey = HabitStore.currentCycleKey()
        lastCycleKey = cycleKey
        let allHabits = HabitStore.shared.items
        let doneCount = allHabits.filter { $0.isCompleted(on: cycleKey) }.count
        badge.stringValue = "\(doneCount)/\(allHabits.count) DONE"

        for (_, row) in rows { row.removeFromSuperview() }
        rows.removeAll()

        for habit in allHabits {
            let row = HabitRowView(habit: habit, currentCycleKey: cycleKey)
            row.onToggle = { [weak self] id in HabitStore.shared.toggle(id: id); self?.reload() }
            row.onDelete = { [weak self] id in HabitStore.shared.delete(id: id); self?.reload() }
            row.onEdit   = { [weak self] id, title in HabitStore.shared.updateTitle(id: id, title: title); self?.reload() }
            rows[habit.id] = row
            list.addSubview(row)
        }
        layoutList()
    }

    private func layoutList() {
        let allHabits = HabitStore.shared.items
        let rowH: CGFloat = 34, gap: CGFloat = 5
        let totalH = CGFloat(allHabits.count) * (rowH + gap)
        let w = scroll.bounds.width > 0 ? scroll.bounds.width : 260
        let listH = max(totalH, scroll.bounds.height)
        list.frame = NSRect(x: 0, y: 0, width: w, height: listH)

        for (i, habit) in allHabits.enumerated() {
            guard let row = rows[habit.id] else { continue }
            let y = listH - CGFloat(i + 1) * (rowH + gap)
            row.frame = NSRect(x: 2, y: y, width: w - 4, height: rowH)
        }
    }

    @objc private func showPanel() {
        guard !panelShown else { return }
        panelShown = true
        panel.clear(); panel.refreshTheme(); panel.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18; panel.animator().alphaValue = 1
        }
        panel.focusField()
    }

    @objc private func hidePanel() {
        guard panelShown else { return }
        panelShown = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12; panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.panelShown == false { self?.panel.isHidden = true }
        })
    }

    private func doAdd(_ habit: Habit) { HabitStore.shared.add(habit); hidePanel(); reload() }

    override func applyTheme(preset: ThemePreset) {
        badge.layer?.backgroundColor = kSurface.cgColor
        badge.layer?.borderColor = kBorder.cgColor
        addBtn.layer?.backgroundColor = kAddBg.cgColor
        addBtn.layer?.borderColor = kBorder.cgColor
        addBtn.contentTintColor = (preset == .glass || preset == .childish) ? .white : kSurface
        panel.refreshTheme()
        updateThemeRecursively(preset: preset)
        reload()
    }
}
