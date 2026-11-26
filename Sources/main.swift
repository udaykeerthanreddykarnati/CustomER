import AppKit
import Carbon
import Foundation

// MARK: - Single-Instance Guard (Prevents Duplicate Widgets & Port 4321 Collisions)
final class SingleInstanceLock {
    private var fd: Int32 = -1

    func acquire(lockName: String = "com.customer.app.lock") -> Bool {
        let path = "/tmp/\(lockName)"
        fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return true }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            fd = -1
            return false
        }
        return true
    }

    deinit {
        if fd >= 0 {
            flock(fd, LOCK_UN)
            close(fd)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var widgetWindows: [String: NSWindow] = [:]
    var wallpaperWindow: NSWindow?
    var themeCustomizerWindow: NSWindow?

    private var wallpaperHotKeyRef: EventHotKeyRef?
    private var themeHotKeyRef: EventHotKeyRef?
    private var desktopHotKeyRef: EventHotKeyRef?
    private var savedVisibility: [String: Bool] = [:]
    private let visibilityURL = AppPaths.file("widget_visibility.json")

    private func loadWidgetVisibility() {
        if let data = try? Data(contentsOf: visibilityURL),
           let dict = try? JSONDecoder().decode([String: Bool].self, from: data) {
            savedVisibility = dict
        }
    }

    private func setWidgetVisible(_ key: String, visible: Bool) {
        savedVisibility[key] = visible
        if let data = try? JSONEncoder().encode(savedVisibility) {
            AppPaths.writeAtomically(data, to: visibilityURL)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPaths.migrateLegacyDataIfNeeded()
        loadWidgetVisibility()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleIPCControlNotification(_:)),
            name: Notification.Name("com.user.CustomERApp.control"),
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            FolderIconManager.updateDesktopFolderIcons(
                bgColor: ThemeManager.shared.currentBgColor,
                accentColor: ThemeManager.shared.currentAccentColor
            )
            FolderIconManager.startWatchingDesktop()
        }

        // 1. Reminders (tututodo)
        spawnWidget(key: "reminders", defaultRect: NSRect(x: 5, y: 616, width: 280, height: 440)) { TodoView(frame: $0) }

        // 1.5 Recurring Habits (Resets daily at 2:00 AM)
        spawnWidget(key: "habits", defaultRect: NSRect(x: 580, y: 616, width: 280, height: 230)) { HabitsView(frame: $0) }

        // 2. Calendar (with Month Navigation & Events)
        spawnWidget(key: "calendar", defaultRect: NSRect(x: 294, y: 331, width: 280, height: 230)) { CalendarView(frame: $0) }

        // 3. Battery & Bluetooth
        spawnWidget(key: "battery", defaultRect: NSRect(x: 6, y: 331, width: 280, height: 280)) { BatteryView(frame: $0) }

        // 4. Digital Clock
        spawnWidget(key: "digital_clock", defaultRect: NSRect(x: 294, y: 695, width: 280, height: 110)) { DigitalClockView(frame: $0) }

        // 7. Spotify Player
        spawnWidget(key: "spotify", defaultRect: NSRect(x: 716, y: 782, width: 280, height: 130)) { SpotifyView(frame: $0) }

        // 8. Transparent GIF Widget
        spawnWidget(key: "gif", defaultRect: NSRect(x: 526, y: 861, width: 196, height: 196)) { GifView(frame: $0) }

        // 10. Gmail Unread Widget
        spawnWidget(key: "mail", defaultRect: NSRect(x: 293, y: 573, width: 280, height: 110)) { MailView(frame: $0) }

        // 11. Timetable Vector Grid
        let ttWin = spawnWidget(key: "timetable", defaultRect: NSRect(x: 4, y: 103, width: 520, height: 220)) { TimetableWidgetView(frame: $0) }
        ttWin.setContentSize(NSSize(width: 520, height: 220))

        // 13. Wallpaper Switcher (Option + W)
        let wallWin = spawnWidget(key: "wallpaper_switcher", defaultRect: NSRect(x: 269, y: 241, width: 680, height: 420), hidden: true) { WallpaperPickerView(frame: $0) }
        wallpaperWindow = wallWin

        // 14. Theme & Style Customizer (Option + E)
        let styleWin = spawnWidget(key: "theme_customizer", defaultRect: NSRect(x: 612, y: 540, width: 486, height: 75), hidden: true) { ThemeCustomizerView(frame: $0) }
        themeCustomizerWindow = styleWin

        // 15. BoringNotch-Style Themed Dynamic Notch (Enabled by default; toggle with `widgets hide notch`)
        setupNotchWidget(hidden: false)

        setupHotkeys()
    }

    @discardableResult
    private func spawnWidget(key: String, defaultRect: NSRect, hidden: Bool = false, makeView: (NSRect) -> NSView) -> NSWindow {
        let origin = PositionManager.shared.getPosition(key: key, defaultOrigin: defaultRect.origin, size: defaultRect.size)
        let rect = NSRect(origin: origin, size: defaultRect.size)
        let win = addWindow(rect: rect, view: makeView(NSRect(origin: .zero, size: rect.size)))
        widgetWindows[key] = win
        let shouldHide = savedVisibility[key].map { !$0 } ?? hidden
        if shouldHide { win.orderOut(nil) }
        return win
    }

    private func setupNotchWidget(hidden: Bool) {
        let geom = NotchGeometry.current(for: NSScreen.main)
        let initialSize = NotchWidgetView.idleWindowSize(for: geom)
        let origin = NSPoint(
            x: geom.screenFrame.midX - initialSize.width / 2,
            y: geom.screenFrame.maxY - initialSize.height
        )
        let notchWin = NotchWidgetWindow(
            contentRect: NSRect(origin: origin, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        notchWin.isFloatingPanel = true
        notchWin.hidesOnDeactivate = false
        notchWin.isOpaque = false
        notchWin.backgroundColor = .clear
        notchWin.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 3)
        notchWin.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        notchWin.hasShadow = false
        notchWin.ignoresMouseEvents = false
        notchWin.contentView = NotchWidgetView(frame: NSRect(origin: .zero, size: initialSize))
        let shouldHide = savedVisibility["notch"].map { !$0 } ?? hidden
        if !shouldHide { notchWin.orderFrontRegardless() }
        widgetWindows["notch"] = notchWin
        windows.append(notchWin)
    }

    @objc private func screensDidChange() {
        for (key, win) in widgetWindows where key != "notch" {
            let clamped = PositionManager.shared.clampToScreens(origin: win.frame.origin, size: win.frame.size)
            if clamped != win.frame.origin {
                win.setFrameOrigin(clamped)
            }
        }
    }

    // MARK: - DistributedNotificationCenter IPC
    @objc private func handleIPCControlNotification(_ notif: Notification) {
        guard let userInfo = notif.userInfo as? [String: String],
              let action = userInfo["action"] else { return }

        DispatchQueue.main.async {
            switch action {
            case "kill_app":
                NSApp.terminate(nil); return
            case "hide_all", "kill_all", "close_all":
                self.widgetWindows.values.forEach { $0.orderOut(nil) }; return
            case "show_all", "open_all":
                for (key, win) in self.widgetWindows where key != "wallpaper_switcher" && key != "theme_customizer" && key != "notch" {
                    win.orderFrontRegardless()
                }
                return
            case "set_font":
                if let fontName = userInfo["value"] { ThemeManager.shared.customFontName = fontName }; return
            case "set_text_color":
                if let val = userInfo["value"], let col = NSColor(hex: val) { ThemeManager.shared.customTextColor = col }; return
            case "set_bg_color":
                if let val = userInfo["value"], let col = NSColor(hex: val) { ThemeManager.shared.customBgColor = col }; return
            case "set_accent_color":
                if let val = userInfo["value"], let col = NSColor(hex: val) { ThemeManager.shared.customAccentColor = col }; return
            case "reset_styles":
                ThemeManager.shared.resetCustomStyles(); return
            case "set_bw", "black_and_white":
                ThemeManager.shared.customTextColor = .white
                ThemeManager.shared.customBgColor = .black; return
            case "open_color_picker":
                ColorPanelDelegate.shared.openColorWheel(for: .text, initialColor: kText); return
            case "open_font_picker":
                FontPanelDelegate.shared.openFontPicker(); return
            default:
                break
            }

            let rawWidgetKey = userInfo["widget"] ?? ""
            if rawWidgetKey.isEmpty || rawWidgetKey == "all" {
                if ["hide", "kill", "close"].contains(action) {
                    self.widgetWindows.values.forEach { $0.orderOut(nil) }
                } else if ["show", "open"].contains(action) {
                    self.widgetWindows.values.forEach { $0.orderFrontRegardless() }
                }
                return
            }

            let widgetKey = self.canonicalWidgetKey(rawWidgetKey)
            guard let win = self.widgetWindows[widgetKey] else { return }

            switch action {
            case "hide", "kill", "close":
                win.orderOut(nil)
                self.setWidgetVisible(widgetKey, visible: false)
            case "show", "open":
                if widgetKey == "notch" {
                    (win.contentView as? NotchWidgetView)?.repositionWindowToTopCenter()
                }
                win.orderFrontRegardless()
                self.setWidgetVisible(widgetKey, visible: true)
            case "toggle":
                let nextVisible = !win.isVisible
                if nextVisible {
                    if widgetKey == "notch" {
                        (win.contentView as? NotchWidgetView)?.repositionWindowToTopCenter()
                    }
                    win.orderFrontRegardless()
                } else {
                    win.orderOut(nil)
                }
                self.setWidgetVisible(widgetKey, visible: nextVisible)
            default: break
            }
        }
    }

    private func canonicalWidgetKey(_ input: String) -> String {
        let key = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "todo", "reminders", "reminder": return "reminders"
        case "habits", "habit", "recurring", "daily", "dailytasks", "tutuhabits": return "habits"
        case "calendar", "cal": return "calendar"
        case "battery", "bat": return "battery"
        case "clock", "digital", "digital_clock": return "digital_clock"
        case "spotify", "music": return "spotify"
        case "gif": return "gif"
        case "mail", "email", "gmail": return "mail"
        case "timetable", "schedule": return "timetable"
        case "wallpaper", "switcher", "wallpaper_switcher": return "wallpaper_switcher"
        case "theme", "styles", "style", "theme_customizer": return "theme_customizer"
        case "notch", "dynamic_island", "pill", "notch_widget": return "notch"
        default: return key
        }
    }

    // MARK: - Global Carbon Hotkeys
    private func setupHotkeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, userPtr) -> OSStatus in
            guard let ptr = userPtr, let event = eventRef else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async {
                switch hkID.id {
                case 1: appDelegate.toggleWallpaperWindow()
                case 2: appDelegate.toggleThemeCustomizerWindow()
                case 3: appDelegate.toggleDesktopIcons()
                default: break
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        RegisterEventHotKey(13, UInt32(optionKey), EventHotKeyID(signature: OSType(0x57414C4C), id: 1), GetApplicationEventTarget(), 0, &wallpaperHotKeyRef)
        RegisterEventHotKey(14, UInt32(optionKey), EventHotKeyID(signature: OSType(0x5448454D), id: 2), GetApplicationEventTarget(), 0, &themeHotKeyRef)
        RegisterEventHotKey(2,  UInt32(optionKey), EventHotKeyID(signature: OSType(0x4445534B), id: 3), GetApplicationEventTarget(), 0, &desktopHotKeyRef)
    }

    @objc func toggleDesktopIcons() {
        let current = UserDefaults(suiteName: "com.apple.finder")?.bool(forKey: "CreateDesktop") ?? true
        let nextVal = !current
        let p1 = Process()
        p1.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p1.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", nextVal ? "true" : "false"]
        try? p1.run(); p1.waitUntilExit()

        let p2 = Process()
        p2.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p2.arguments = ["Finder"]
        try? p2.run()
    }

    func isDesktopOrAppFrontmost() -> Bool {
        if NSColorPanel.shared.isVisible || NSFontPanel.shared.isVisible { return true }
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let bundleID = app.bundleIdentifier ?? ""
        return bundleID == "com.apple.finder" || bundleID == "com.user.CustomERApp" || app.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    func toggleWallpaperWindow() {
        guard isDesktopOrAppFrontmost(), let win = wallpaperWindow else { return }
        if win.isVisible { win.orderOut(nil) }
        else { win.level = .floating; win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }

    func toggleThemeCustomizerWindow() {
        guard isDesktopOrAppFrontmost(), let win = themeCustomizerWindow else { return }
        if win.isVisible { win.orderOut(nil) }
        else { win.level = .floating; win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }

    @objc private func activeAppDidChange(_ notif: Notification) {
        if NSColorPanel.shared.isVisible || NSFontPanel.shared.isVisible { return }
        if !isDesktopOrAppFrontmost() {
            wallpaperWindow?.orderOut(nil)
            themeCustomizerWindow?.orderOut(nil)
        }
    }

    @discardableResult
    private func addWindow(rect: NSRect, view: NSView) -> NSWindow {
        let win = MasterWidgetWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = NSWindow.Level(rawValue: -1)
        win.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        win.isMovableByWindowBackground = true
        win.hasShadow = false
        win.contentView = view
        win.orderFrontRegardless()
        windows.append(win)
        return win
    }
}

let instanceLock = SingleInstanceLock()
guard instanceLock.acquire() else {
    fputs("CustomERApp is already running.\n", stderr)
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
