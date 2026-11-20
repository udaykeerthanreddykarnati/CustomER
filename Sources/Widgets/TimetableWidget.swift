import AppKit
import Foundation

// MARK: - 12. TIMETABLE WIDGET (Generalized Defaults + Optional JSON Override)
struct TimetableSlot: Codable {
    var startCol: Int // Column index in `headers` (1-based; column 0 is "Day")
    var span: Int     // Number of consecutive columns this class/block occupies
    var code: String  // Short display label (e.g. "MATH", "CS LAB")
}

struct TimetableConfig: Codable {
    var days: [String]
    var headers: [String]
    var breakColumns: [Int]
    var schedule: [String: [TimetableSlot]]
    var subjectColors: [String: String]? // Optional hex colors keyed by uppercase subject code

    // =========================================================================
    // MARK: - CUSTOMIZE YOUR HARDCODED TIMETABLE HERE
    // =========================================================================
    // Edit `days`, `headers`, `breakColumns`, `schedule`, and `subjectColors`
    // below, then rebuild with `./build.sh`.
    //
    // Tip: You can also override this WITHOUT recompiling by placing a
    // `timetable.json` file in `~/Library/Application Support/CustomER/`.
    // =========================================================================
    static let defaultConfig = TimetableConfig(
        days: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"],
        headers: [
            "Day",          // Col 0
            "8:00-9:00",    // Col 1
            "9:00-10:00",   // Col 2
            "Break",        // Col 3 (narrow break column)
            "10:30-11:30",  // Col 4
            "11:30-12:30",  // Col 5
            "Lunch",        // Col 6 (narrow lunch column)
            "1:15-2:15",    // Col 7
            "2:15-3:15"     // Col 8
        ],
        breakColumns: [3, 6],
        schedule: [
            "Monday": [
                TimetableSlot(startCol: 1, span: 1, code: "CS101"),
                TimetableSlot(startCol: 2, span: 1, code: "MATH"),
                TimetableSlot(startCol: 4, span: 2, code: "PHYS"),
                TimetableSlot(startCol: 7, span: 2, code: "CS LAB")
            ],
            "Tuesday": [
                TimetableSlot(startCol: 1, span: 2, code: "DESIGN"),
                TimetableSlot(startCol: 4, span: 1, code: "MATH"),
                TimetableSlot(startCol: 5, span: 1, code: "ENG")
            ],
            "Wednesday": [
                TimetableSlot(startCol: 1, span: 1, code: "ENG"),
                TimetableSlot(startCol: 2, span: 1, code: "CS101"),
                TimetableSlot(startCol: 4, span: 1, code: "ENG"),
                TimetableSlot(startCol: 5, span: 1, code: "MATH")
            ],
            "Thursday": [
                TimetableSlot(startCol: 1, span: 2, code: "PHYS"),
                TimetableSlot(startCol: 4, span: 1, code: "CS101"),
                TimetableSlot(startCol: 5, span: 1, code: "ENG"),
                TimetableSlot(startCol: 7, span: 2, code: "PHYS LAB")
            ],
            "Friday": [
                TimetableSlot(startCol: 1, span: 1, code: "MATH"),
                TimetableSlot(startCol: 2, span: 1, code: "CS101"),
                TimetableSlot(startCol: 4, span: 2, code: "DESIGN")
            ]
        ],
        subjectColors: [
            "CS101":    "#D9E0FA",
            "ENG":      "#D6EDDB",
            "MATH":     "#EBDBFA",
            "DESIGN":   "#FAE8C7",
            "PHYS":     "#FAD9DE",
            "CS LAB":   "#D1EBFA",
            "PHYS LAB": "#F7D6EB"
        ]
    )

    static func load() -> TimetableConfig {
        let url = AppPaths.file("timetable.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(TimetableConfig.self, from: data),
           !decoded.days.isEmpty,
           decoded.headers.count >= 2 {
            return decoded
        }
        return defaultConfig
    }
}

class TimetableWidgetView: BaseWidgetView {
    private let titleLabel = NSTextField()
    private let cardView   = NSView()
    private var config = TimetableConfig.load()
    private var lastRenderedBoundsSize: NSSize = .zero

    private let fallbackPalette: [NSColor] = [
        NSColor(srgbRed: 0.85, green: 0.88, blue: 0.98, alpha: 0.92),
        NSColor(srgbRed: 0.84, green: 0.93, blue: 0.86, alpha: 0.92),
        NSColor(srgbRed: 0.92, green: 0.86, blue: 0.98, alpha: 0.92),
        NSColor(srgbRed: 0.98, green: 0.91, blue: 0.78, alpha: 0.92),
        NSColor(srgbRed: 0.98, green: 0.85, blue: 0.87, alpha: 0.92),
        NSColor(srgbRed: 0.82, green: 0.92, blue: 0.98, alpha: 0.92),
        NSColor(srgbRed: 0.97, green: 0.84, blue: 0.92, alpha: 0.92)
    ]

    init(frame: NSRect) {
        super.init(frame: frame, widgetKey: "timetable")
        build()
        setupDailyRefresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupDailyRefresh() {
        NotificationCenter.default.addObserver(self, selector: #selector(onDayChanged), name: .NSCalendarDayChanged, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onDayChanged), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func onDayChanged() {
        DispatchQueue.main.async {
            self.config = TimetableConfig.load()
            self.renderGrid()
        }
    }

    private func build() {
        titleLabel.stringValue = "TIMETABLE"
        titleLabel.font = dynamicFont(size: 13, weight: .bold)
        titleLabel.textColor = kText
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = kRadius / 2
        cardView.layer?.backgroundColor = kSurface.cgColor
        cardView.layer?.borderWidth = kBorderWidth
        cardView.layer?.borderColor = kBorder.cgColor
        addSubview(cardView)

        renderGrid()
    }

    private func getMergedItems(for dayName: String) -> [TimetableSlot] {
        guard let items = config.schedule[dayName] else { return [] }
        var result: [TimetableSlot] = []
        for item in items {
            if let last = result.last, last.code == item.code, last.startCol + last.span == item.startCol {
                result[result.count - 1].span += item.span
            } else {
                result.append(item)
            }
        }
        return result
    }

    private func colorForSubject(_ code: String) -> NSColor {
        let key = code.uppercased()
        if let hex = config.subjectColors?[key], let c = NSColor(hex: hex) {
            return c.withAlphaComponent(0.92)
        }
        // Deterministic pastel color for any custom subject code
        let hash = key.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return fallbackPalette[abs(hash) % fallbackPalette.count]
    }

    private func renderGrid() {
        cardView.subviews.forEach { $0.removeFromSuperview() }

        let boundsW = cardView.bounds.width > 0 ? cardView.bounds.width : 500
        let boundsH = cardView.bounds.height > 0 ? cardView.bounds.height : 184

        let numRows = CGFloat(config.days.count + 1)
        let rowH = boundsH / numRows

        let breakSet = Set(config.breakColumns)
        let weights: [CGFloat] = config.headers.indices.map { breakSet.contains($0) ? 0.30 : 1.0 }
        let totalWeight = weights.reduce(0, +)
        var colX: [CGFloat] = [0]
        for w in weights {
            colX.append(colX.last! + (w / totalWeight) * boundsW)
        }

        let todayName = AppDateFormatters.weekdayFull.string(from: Date())

        // 1. Header Row
        for (i, hText) in config.headers.enumerated() {
            let cellX = colX[i], cellW = colX[i + 1] - cellX, y = boundsH - rowH
            var displayStr = hText
            if breakSet.contains(i) && cellW < 35, let first = hText.first {
                displayStr = String(first)
            }
            let label = createLabel(text: displayStr, size: 9.0, weight: .bold, color: kText, align: .center)
            label.frame = NSRect(x: cellX, y: y + (rowH - 18) / 2, width: cellW, height: 18)
            cardView.addSubview(label)
        }

        let hDiv = NSView(frame: NSRect(x: 0, y: boundsH - rowH, width: boundsW, height: 1))
        hDiv.wantsLayer = true; hDiv.layer?.backgroundColor = kBorder.cgColor
        cardView.addSubview(hDiv)

        // 2. Break Columns
        for colIdx in config.breakColumns where colIdx < config.headers.count {
            let bx1 = colX[colIdx], bw = colX[colIdx + 1] - bx1
            let breakBg = NSView(frame: NSRect(x: bx1, y: 0, width: bw, height: boundsH - rowH))
            breakBg.wantsLayer = true; breakBg.layer?.backgroundColor = kDim.withAlphaComponent(0.08).cgColor
            cardView.addSubview(breakBg)
        }

        // 3. Days & Classes
        let tileTextColor = (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentTextColor == .white)
            ? (NSColor(hex: "#0F172A") ?? .black)
            : kText

        for (rowIdx, dayName) in config.days.enumerated() {
            let y = boundsH - CGFloat(rowIdx + 2) * rowH
            let isToday = (dayName.caseInsensitiveCompare(todayName) == .orderedSame)

            if isToday {
                let rowHighlight = NSView(frame: NSRect(x: 0, y: y, width: boundsW, height: rowH))
                rowHighlight.wantsLayer = true; rowHighlight.layer?.backgroundColor = kAccent.withAlphaComponent(0.15).cgColor
                cardView.addSubview(rowHighlight)
            }

            let dayX = colX[0], dayW = colX[1] - dayX
            let dLabel = createLabel(text: dayName, size: 10, weight: isToday ? .black : .bold, color: isToday ? kAccent : kText, align: .center)
            dLabel.frame = NSRect(x: dayX + 2, y: y + (rowH - 16) / 2, width: dayW - 4, height: 16)
            cardView.addSubview(dLabel)

            for item in getMergedItems(for: dayName) {
                guard item.startCol >= 1, item.startCol + item.span < colX.count else { continue }
                let cx1 = colX[item.startCol], cx2 = colX[item.startCol + item.span], cw = cx2 - cx1

                let cellBox = NSView(frame: NSRect(x: cx1 + 2, y: y + 2, width: cw - 4, height: rowH - 4))
                cellBox.wantsLayer = true; cellBox.layer?.cornerRadius = 4.0
                cellBox.layer?.borderWidth = 1.0; cellBox.layer?.borderColor = kBorder.withAlphaComponent(0.5).cgColor
                cellBox.layer?.backgroundColor = colorForSubject(item.code).cgColor

                let cLabel = createLabel(text: item.code, size: item.span > 1 ? 11 : 10, weight: .bold, color: tileTextColor, align: .center)
                cLabel.tag = 100
                cLabel.frame = NSRect(x: 0, y: (rowH - 4 - 16) / 2, width: cw - 4, height: 16)
                cellBox.addSubview(cLabel)
                cardView.addSubview(cellBox)
            }

            if rowIdx < config.days.count - 1 {
                let rDiv = NSView(frame: NSRect(x: 0, y: y, width: boundsW, height: 1))
                rDiv.wantsLayer = true; rDiv.layer?.backgroundColor = kBorder.withAlphaComponent(0.20).cgColor
                cardView.addSubview(rDiv)
            }
        }
    }

    private func createLabel(text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, align: NSTextAlignment) -> NSTextField {
        let tf = NSTextField()
        tf.stringValue = text; tf.font = dynamicFont(size: size, weight: weight); tf.textColor = color; tf.alignment = align
        tf.isEditable = false; tf.isBordered = false; tf.backgroundColor = .clear
        tf.cell?.usesSingleLineMode = true; tf.cell?.lineBreakMode = .byClipping
        return tf
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleLabel.frame = NSRect(x: 14, y: h - 26, width: 200, height: 18)
        cardView.frame   = NSRect(x: 10, y: 10, width: w - 20, height: h - 36)
        if cardView.bounds.size != lastRenderedBoundsSize {
            lastRenderedBoundsSize = cardView.bounds.size
            renderGrid()
        }
    }

    override func applyTheme(preset: ThemePreset) {
        cardView.layer?.cornerRadius = preset.cornerRadius / 2
        cardView.layer?.backgroundColor = preset.surfaceColor.cgColor
        cardView.layer?.borderColor = preset.borderColor.cgColor
        cardView.layer?.borderWidth = preset.borderWidth
        titleLabel.textColor = ThemeManager.shared.currentTextColor
        titleLabel.font = dynamicFont(size: 13, weight: .bold)
        renderGrid()
    }
}
