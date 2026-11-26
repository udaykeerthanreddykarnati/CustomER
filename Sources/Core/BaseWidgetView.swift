import AppKit

// MARK: - Shared Widget Base Class (Dragging, Position Persistence & Theme Sync)
class BaseWidgetView: NSView {
    let widgetKey: String
    private var dragStart: NSPoint = .zero
    private var initialWinOrigin: NSPoint = .zero
    private var dragActive = false
    var allowWindowDrag: Bool = true

    init(frame: NSRect, widgetKey: String) {
        self.widgetKey = widgetKey
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = kRadius
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        registerThemeObservers()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func registerThemeObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeNotification), name: ThemeManager.notifName, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleThemeNotification), name: ThemeManager.notifName, object: nil)
    }

    @objc private func handleThemeNotification() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let preset = ThemeManager.shared.currentPreset
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            self.layer?.cornerRadius = preset.cornerRadius
            self.layer?.borderColor = NSColor.clear.cgColor
            self.layer?.borderWidth = 0
            self.applyTheme(preset: preset)
            CATransaction.commit()
            self.needsDisplay = true
        }
    }

    /// Override in subclasses for custom surfaces/borders beyond recursive label/button styling.
    func applyTheme(preset: ThemePreset) {
        updateThemeRecursively(preset: preset)
    }

    override func mouseDown(with event: NSEvent) {
        guard allowWindowDrag else { super.mouseDown(with: event); return }
        let pt = convert(event.locationInWindow, from: nil)
        if let hit = hitTest(pt), hit is NSButton || hit is NSTextField && (hit as! NSTextField).isEditable {
            super.mouseDown(with: event)
            return
        }
        dragStart = NSEvent.mouseLocation
        if let w = window { initialWinOrigin = w.frame.origin }
        dragActive = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard allowWindowDrag, dragActive, let w = window else { return }
        let cur = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(
            x: initialWinOrigin.x + (cur.x - dragStart.x),
            y: initialWinOrigin.y + (cur.y - dragStart.y)
        ))
    }

    override func mouseUp(with event: NSEvent) {
        guard allowWindowDrag else { super.mouseUp(with: event); return }
        if dragActive {
            dragActive = false
            if let w = window {
                PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin)
            }
        }
    }
}
