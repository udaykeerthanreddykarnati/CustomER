import AppKit
import Foundation

// MARK: - Calendar Event Model & Store
struct CalendarEvent: Codable {
    var id: UUID
    var dateKey: String // "YYYY-MM-DD"
    var title: String
    var createdAt: Date

    init(id: UUID = UUID(), dateKey: String, title: String, createdAt: Date = Date()) {
        self.id = id
        self.dateKey = dateKey
        self.title = title
        self.createdAt = createdAt
    }
}

final class CalendarEventStore {
    static let shared = CalendarEventStore()
    private let url = AppPaths.file("calendar_events.json")
    private(set) var events: [CalendarEvent] = []

    private init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CalendarEvent].self, from: data) else { return }
        events = decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(events) {
            AppPaths.writeAtomically(data, to: url)
        }
    }

    func events(for dateKey: String) -> [CalendarEvent] { events.filter { $0.dateKey == dateKey } }
    func hasEvents(for dateKey: String) -> Bool { events.contains { $0.dateKey == dateKey } }
    func add(_ ev: CalendarEvent) { events.append(ev); save() }

    func updateTitle(id: UUID, title: String) {
        if let idx = events.firstIndex(where: { $0.id == id }) {
            events[idx].title = title
            save()
        }
    }

    func delete(id: UUID) { events.removeAll { $0.id == id }; save() }
}

// MARK: - Optional Weekly Recurring Day Highlights
// To highlight recurring weekdays (e.g. gym, chores, study days), either:
//   1. Create `~/Library/Application Support/CustomER/calendar_config.json`, OR
//   2. Edit `CalendarConfig.defaultConfig` below and recompile.
struct CalendarConfig: Codable {
    struct DayTag: Codable {
        var weekdays: [Int]   // 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat
        var hexColor: String
    }

    var legend: String
    var tags: [DayTag]

    static let defaultConfig = CalendarConfig(
        legend: "DOUBLE-CLICK ANY DATE TO ADD EVENTS",
        tags: []
        // Example hardcoded tags:
        // legend: "MON/THU: GYM  •  WED/SAT: REVIEW",
        // tags: [
        //     DayTag(weekdays: [1, 4], hexColor: "#F59E0B"),
        //     DayTag(weekdays: [3, 6], hexColor: "#10B981")
        // ]
    )

    static func load() -> CalendarConfig {
        let url = AppPaths.file("calendar_config.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(CalendarConfig.self, from: data) {
            return decoded
        }
        return defaultConfig
    }
}

// MARK: - 2. MONTHLY CALENDAR WIDGET (with Month Navigation & Events)
class CalendarView: BaseWidgetView {
    private let titleLabel  = NSTextField()
    private let prevBtn     = NSButton()
    private let nextBtn     = NSButton()
    private let legendLabel = NSTextField()
    private var dayViews: [NSTextField] = []
    private var eventDots: [NSView] = []
    private var displayedMonthOffset = 0
    private var currentRowCount = 6
    private var calendarConfig = CalendarConfig.load()
    private var refreshTimer: Timer?

    init(frame: NSRect) {
        super.init(frame: frame, widgetKey: "calendar")
        build()
        setupDailyRefresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { refreshTimer?.invalidate() }

    private func setupDailyRefresh() {
        NotificationCenter.default.addObserver(self, selector: #selector(onDayChanged), name: .NSCalendarDayChanged, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onDayChanged), name: NSWorkspace.didWakeNotification, object: nil)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            self?.updateCalendar()
        }
    }

    @objc private func onDayChanged() {
        DispatchQueue.main.async { self.updateCalendar() }
    }

    private func build() {
        let titleCell = CenteredTextFieldCell(textCell: "")
        titleCell.alignment = .left; titleCell.font = dynamicFont(size: 13, weight: .bold); titleCell.textColor = kText
        titleLabel.cell = titleCell
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.drawsBackground = false; titleLabel.backgroundColor = .clear
        let resetClick = NSClickGestureRecognizer(target: self, action: #selector(jumpToToday))
        titleLabel.addGestureRecognizer(resetClick)
        addSubview(titleLabel)

        for (btn, sym, sel) in [(prevBtn, "<", #selector(prevMonth)), (nextBtn, ">", #selector(nextMonth))] {
            btn.isBordered = false; btn.wantsLayer = true
            btn.layer?.cornerRadius = kRadius
            btn.layer?.borderWidth = kBorderWidth; btn.layer?.borderColor = kBorder.cgColor
            btn.layer?.backgroundColor = kSurface.cgColor
            btn.attributedTitle = NSAttributedString(string: sym, attributes: [
                .font: dynamicFont(size: 11, weight: .bold),
                .foregroundColor: kText
            ])
            btn.target = self; btn.action = sel
            addSubview(btn)
        }

        let legendCell = CenteredTextFieldCell(textCell: calendarConfig.legend)
        legendCell.alignment = .center; legendCell.font = dynamicFont(size: 8.5, weight: .bold); legendCell.textColor = kDim
        legendLabel.cell = legendCell; legendLabel.tag = 99
        legendLabel.isEditable = false; legendLabel.isBordered = false; legendLabel.drawsBackground = false; legendLabel.backgroundColor = .clear
        addSubview(legendLabel)

        let headers = ["S", "M", "T", "W", "T", "F", "S"]
        for (idx, h) in headers.enumerated() {
            let lbl = NSTextField()
            let cell = CenteredTextFieldCell(textCell: h)
            cell.alignment = .center; cell.font = dynamicFont(size: 10, weight: .bold)
            lbl.cell = cell; lbl.stringValue = h
            lbl.isEditable = false; lbl.isBordered = false; lbl.drawsBackground = false; lbl.backgroundColor = .clear
            if let tagColor = tagColorForWeekday(idx) {
                lbl.textColor = tagColor; lbl.tag = 100
            } else {
                lbl.textColor = kDim; lbl.tag = 99
            }
            addSubview(lbl); dayViews.append(lbl)
        }

        for _ in 0..<42 {
            let lbl = NSTextField()
            let cell = CenteredTextFieldCell(textCell: "")
            cell.alignment = .center; cell.font = dynamicFont(size: 11, weight: .bold)
            lbl.cell = cell
            lbl.isEditable = false; lbl.isBordered = false; lbl.drawsBackground = false; lbl.backgroundColor = .clear
            lbl.wantsLayer = true; lbl.layer?.cornerRadius = kRadius
            let dclick = NSClickGestureRecognizer(target: self, action: #selector(dayDoubleClicked(_:)))
            dclick.numberOfClicksRequired = 2
            lbl.addGestureRecognizer(dclick)

            let dot = NSView()
            dot.wantsLayer = true; dot.layer?.cornerRadius = 1.5; dot.isHidden = true
            lbl.addSubview(dot)
            eventDots.append(dot)

            addSubview(lbl); dayViews.append(lbl)
        }
        updateCalendar()
    }

    private func tagColorForWeekday(_ weekdayIndex: Int) -> NSColor? {
        for tag in calendarConfig.tags where tag.weekdays.contains(weekdayIndex) {
            if let c = NSColor(hex: tag.hexColor) { return c }
        }
        return nil
    }

    private func displayedDate() -> Date {
        let cal = Calendar.current
        let base = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return cal.date(byAdding: .month, value: displayedMonthOffset, to: base) ?? base
    }

    @objc private func prevMonth()   { displayedMonthOffset -= 1; updateCalendar() }
    @objc private func nextMonth()   { displayedMonthOffset += 1; updateCalendar() }
    @objc private func jumpToToday() { displayedMonthOffset = 0; updateCalendar() }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleLabel.frame  = NSRect(x: 12, y: h - 30, width: w - 76, height: 20)
        prevBtn.frame     = NSRect(x: w - 60, y: h - 30, width: 22, height: 20)
        nextBtn.frame     = NSRect(x: w - 34, y: h - 30, width: 22, height: 20)
        legendLabel.frame = NSRect(x: 12, y: 6, width: w - 24, height: 14)

        let gridX: CGFloat = 12
        let gridBottom: CGFloat = 24
        let gridTop: CGFloat = h - 36
        let headerH: CGFloat = 18
        let colW = (w - 24) / 7.0
        let rowsCount = max(5, currentRowCount)
        let daysAreaH = max(40, gridTop - headerH - gridBottom)
        let rowH = daysAreaH / CGFloat(rowsCount)

        for i in 0..<7 {
            dayViews[i].frame = NSRect(x: gridX + CGFloat(i) * colW, y: gridTop - headerH, width: colW, height: headerH)
        }

        let insetX: CGFloat = 2.0
        let insetY: CGFloat = 2.0
        for r in 0..<6 {
            for c in 0..<7 {
                let idx = 7 + r * 7 + c
                let lbl = dayViews[idx]
                if r < rowsCount {
                    lbl.isHidden = false
                    let cellRect = NSRect(
                        x: gridX + CGFloat(c) * colW + insetX,
                        y: gridBottom + CGFloat(rowsCount - 1 - r) * rowH + insetY,
                        width: max(8, colW - insetX * 2),
                        height: max(8, rowH - insetY * 2)
                    )
                    lbl.frame = cellRect
                    let dot = eventDots[r * 7 + c]
                    dot.frame = NSRect(x: (cellRect.width - 3.5) / 2, y: 2.5, width: 3.5, height: 3.5)
                } else {
                    lbl.isHidden = true
                }
            }
        }
    }

    private func updateCalendar() {
        let cal = Calendar.current
        let now = Date()
        let todayComp = cal.dateComponents([.year, .month, .day], from: now)
        let targetDate = displayedDate()
        let comp = cal.dateComponents([.year, .month], from: targetDate)
        let year = comp.year!, month = comp.month!
        let isCurrentMonth = (year == todayComp.year && month == todayComp.month)
        let today = todayComp.day!

        titleLabel.stringValue = AppDateFormatters.monthYear.string(from: targetDate).uppercased()

        var fComp = DateComponents(); fComp.year = year; fComp.month = month; fComp.day = 1
        let fDate = cal.date(from: fComp)!, fWeekday = cal.component(.weekday, from: fDate) - 1
        let numDays = cal.range(of: .day, in: .month, for: targetDate)!.count
        let neededRows = max(5, Int(ceil(Double(fWeekday + numDays) / 7.0)))
        if neededRows != currentRowCount {
            currentRowCount = neededRows
            needsLayout = true
        }

        for i in 0..<42 {
            let lbl = dayViews[7 + i], dNum = i - fWeekday + 1
            let dot = eventDots[i]
            let c = i % 7
            let recurringColor = tagColorForWeekday(c)

            if dNum >= 1 && dNum <= numDays {
                lbl.tag = dNum
                let dateKey = String(format: "%04d-%02d-%02d", year, month, dNum)
                let hasEv = CalendarEventStore.shared.hasEvents(for: dateKey)
                lbl.stringValue = "\(dNum)"
                dot.isHidden = !hasEv

                if isCurrentMonth && dNum == today {
                    lbl.layer?.backgroundColor = kAccent.cgColor
                    let fg: NSColor = (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish) ? .white : kSurface
                    lbl.textColor = fg
                    lbl.font = dynamicFont(size: 11, weight: .bold)
                    lbl.layer?.borderWidth = recurringColor != nil ? 2.0 : kBorderWidth
                    lbl.layer?.borderColor = (recurringColor ?? kBorder).cgColor
                    dot.layer?.backgroundColor = fg.cgColor
                } else if hasEv {
                    lbl.font = dynamicFont(size: 11, weight: .bold)
                    lbl.layer?.backgroundColor = (NSColor(hex: "#8B5CF6") ?? kAccent).withAlphaComponent(0.25).cgColor
                    let fg = (ThemeManager.shared.currentPreset == .glass) ? (NSColor(hex: "#C4B5FD") ?? kText) : (NSColor(hex: "#6D28D9") ?? kText)
                    lbl.textColor = fg
                    lbl.layer?.borderWidth = 1.5
                    lbl.layer?.borderColor = (NSColor(hex: "#8B5CF6") ?? kAccent).withAlphaComponent(0.6).cgColor
                    dot.layer?.backgroundColor = fg.cgColor
                } else if let rc = recurringColor {
                    lbl.font = dynamicFont(size: 11, weight: .semibold)
                    lbl.layer?.backgroundColor = rc.withAlphaComponent(0.22).cgColor
                    lbl.textColor = rc
                    lbl.layer?.borderWidth = 1.0
                    lbl.layer?.borderColor = rc.withAlphaComponent(0.55).cgColor
                } else {
                    lbl.font = dynamicFont(size: 11, weight: .medium)
                    lbl.layer?.backgroundColor = NSColor.clear.cgColor
                    lbl.textColor = kText
                    lbl.layer?.borderWidth = 0
                    lbl.layer?.borderColor = NSColor.clear.cgColor
                }
            } else {
                lbl.tag = 0
                lbl.stringValue = ""
                dot.isHidden = true
                lbl.layer?.backgroundColor = NSColor.clear.cgColor
                lbl.layer?.borderWidth = 0
                lbl.layer?.borderColor = NSColor.clear.cgColor
            }
            lbl.needsDisplay = true
        }
    }

    @objc private func dayDoubleClicked(_ sender: NSClickGestureRecognizer) {
        guard let lbl = sender.view as? NSTextField, lbl.tag > 0 else { return }
        let day = lbl.tag
        let comp = Calendar.current.dateComponents([.year, .month], from: displayedDate())
        let year = comp.year!, month = comp.month!
        let dateKey = String(format: "%04d-%02d-%02d", year, month, day)
        manageEvents(for: dateKey, day: day, month: month, year: year)
    }

    private func manageEvents(for dateKey: String, day: Int, month: Int, year: Int) {
        guard let window = self.window else { return }
        let evList = CalendarEventStore.shared.events(for: dateKey)
        var dateComp = DateComponents(); dateComp.year = year; dateComp.month = month; dateComp.day = day
        let dateObj = Calendar.current.date(from: dateComp) ?? Date()
        let dateTitle = AppDateFormatters.readableDate.string(from: dateObj)

        let alert = NSAlert()
        alert.messageText = "Events for \(dateTitle)"
        if evList.isEmpty {
            alert.informativeText = "No events scheduled for this day."
        } else {
            let evLines = evList.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "\n")
            alert.informativeText = "Scheduled Events (\(evList.count)):\n\(evLines)"
        }

        alert.addButton(withTitle: "+ Add Event")
        if !evList.isEmpty {
            alert.addButton(withTitle: "Edit Event")
            alert.addButton(withTitle: "Delete Event")
        }
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { [weak self] resp in
            guard let self = self else { return }
            if resp == .alertFirstButtonReturn {
                self.promptAddEvent(dateKey: dateKey, dateTitle: dateTitle)
            } else if resp == .alertSecondButtonReturn && !evList.isEmpty {
                self.promptEditEvent(dateTitle: dateTitle, events: evList)
            } else if resp == .alertThirdButtonReturn && !evList.isEmpty {
                self.promptDeleteEvent(dateTitle: dateTitle, events: evList)
            }
        }
    }

    private func promptAddEvent(dateKey: String, dateTitle: String) {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "Add Event for \(dateTitle)"
        alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        tf.placeholderString = "Event title (e.g. Meeting @ 3PM)"
        alert.accessoryView = tf
        alert.beginSheetModal(for: window) { [weak self] resp in
            if resp == .alertFirstButtonReturn {
                let t = tf.stringValue.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty {
                    CalendarEventStore.shared.add(CalendarEvent(dateKey: dateKey, title: t))
                    self?.updateCalendar()
                }
            }
        }
        DispatchQueue.main.async { tf.becomeFirstResponder() }
    }

    private func promptEditEvent(dateTitle: String, events: [CalendarEvent]) {
        guard let window = self.window else { return }
        if events.count == 1 {
            promptSingleEdit(ev: events[0], dateTitle: dateTitle)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Select Event to Edit (\(dateTitle))"
        alert.addButton(withTitle: "Edit Selected"); alert.addButton(withTitle: "Cancel")
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        for ev in events { pop.addItem(withTitle: ev.title) }
        alert.accessoryView = pop
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard let self = self, resp == .alertFirstButtonReturn else { return }
            let idx = pop.indexOfSelectedItem
            if idx >= 0 && idx < events.count { self.promptSingleEdit(ev: events[idx], dateTitle: dateTitle) }
        }
    }

    private func promptSingleEdit(ev: CalendarEvent, dateTitle: String) {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "Edit Event (\(dateTitle))"
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        tf.stringValue = ev.title
        alert.accessoryView = tf
        alert.beginSheetModal(for: window) { [weak self] resp in
            if resp == .alertFirstButtonReturn {
                let newT = tf.stringValue.trimmingCharacters(in: .whitespaces)
                if !newT.isEmpty {
                    CalendarEventStore.shared.updateTitle(id: ev.id, title: newT)
                    self?.updateCalendar()
                }
            }
        }
        DispatchQueue.main.async { tf.becomeFirstResponder() }
    }

    private func promptDeleteEvent(dateTitle: String, events: [CalendarEvent]) {
        guard let window = self.window else { return }
        if events.count == 1 {
            CalendarEventStore.shared.delete(id: events[0].id)
            updateCalendar()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Select Event to Delete (\(dateTitle))"
        alert.addButton(withTitle: "Delete Selected"); alert.addButton(withTitle: "Cancel")
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        for ev in events { pop.addItem(withTitle: ev.title) }
        alert.accessoryView = pop
        alert.beginSheetModal(for: window) { [weak self] resp in
            if resp == .alertFirstButtonReturn {
                let idx = pop.indexOfSelectedItem
                if idx >= 0 && idx < events.count {
                    CalendarEventStore.shared.delete(id: events[idx].id)
                    self?.updateCalendar()
                }
            }
        }
    }

    override func applyTheme(preset: ThemePreset) {
        for (btn, sym) in [(prevBtn, "<"), (nextBtn, ">")] {
            btn.layer?.backgroundColor = kSurface.cgColor
            btn.layer?.borderColor = kBorder.cgColor
            btn.layer?.borderWidth = kBorderWidth
            btn.attributedTitle = NSAttributedString(string: sym, attributes: [
                .font: dynamicFont(size: 11, weight: .bold),
                .foregroundColor: kText
            ])
        }
        updateThemeRecursively(preset: preset)
        updateCalendar()
    }
}
