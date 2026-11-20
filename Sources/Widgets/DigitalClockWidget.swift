import AppKit
import Foundation

// MARK: - 4. DIGITAL CLOCK WIDGET (Cached Formatters, Zero Wasted Redraws)
class DigitalClockView: BaseWidgetView {
    private let timeLabel = NSTextField()
    private let dateLabel = NSTextField()
    private var timer: Timer?
    private var lastTimeString = ""
    private var lastDateString = ""

    init(frame: NSRect) {
        super.init(frame: frame, widgetKey: "digital_clock")
        build()
        updateTime(force: true)
        startTimer()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { timer?.invalidate() }

    private func build() {
        timeLabel.font = dynamicFont(size: 42, weight: .bold); timeLabel.textColor = kText; timeLabel.alignment = .center
        timeLabel.isEditable = false; timeLabel.isBordered = false; timeLabel.backgroundColor = .clear
        addSubview(timeLabel)

        dateLabel.font = dynamicFont(size: 12, weight: .bold); dateLabel.textColor = kDim; dateLabel.alignment = .center; dateLabel.tag = 99
        dateLabel.isEditable = false; dateLabel.isBordered = false; dateLabel.backgroundColor = .clear
        addSubview(dateLabel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        timeLabel.frame = NSRect(x: 10, y: 32, width: w - 20, height: 50)
        dateLabel.frame = NSRect(x: 10, y: 12, width: w - 20, height: 20)
    }

    private func startTimer() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onWake), name: NSWorkspace.didWakeNotification, object: nil)
        // Check every 5s; skips UI updates unless HH:mm or date string changed.
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateTime(force: false)
        }
    }

    @objc private func onWake() {
        updateTime(force: true)
    }

    private func updateTime(force: Bool) {
        let now = Date()
        let newTime = AppDateFormatters.timeHHmm.string(from: now)
        let newDate = AppDateFormatters.fullDate.string(from: now).uppercased()
        if force || newTime != lastTimeString {
            lastTimeString = newTime
            timeLabel.stringValue = newTime
        }
        if force || newDate != lastDateString {
            lastDateString = newDate
            dateLabel.stringValue = newDate
        }
    }

    override func applyTheme(preset: ThemePreset) {
        updateThemeRecursively(preset: preset)
        updateTime(force: true)
    }
}
