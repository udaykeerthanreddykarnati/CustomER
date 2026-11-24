// Dynamic Notch widget — design & UX inspired by boring.notch by TheBoredTeam
// Reference: https://github.com/TheBoredTeam/boring.notch
// Implemented natively in AppKit/CoreAnimation for CustomER's live theme engine.

import AppKit
import Foundation
import IOKit.ps

// MARK: - Hardware Notch Geometry Detection
struct NotchGeometry {
    let screenFrame: NSRect
    let hardwareWidth: CGFloat
    let hardwareHeight: CGFloat
    let hasPhysicalNotch: Bool

    static func current(for screen: NSScreen? = NSScreen.main) -> NotchGeometry {
        let s = screen ?? NSScreen.screens.first
        let frame = s?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        if let s = s,
           s.safeAreaInsets.top > 0,
           let left = s.auxiliaryTopLeftArea,
           let right = s.auxiliaryTopRightArea {
            let notchW = max(160, frame.width - left.width - right.width)
            let notchH = max(30, s.safeAreaInsets.top)
            return NotchGeometry(screenFrame: frame, hardwareWidth: notchW, hardwareHeight: notchH, hasPhysicalNotch: true)
        }

        return NotchGeometry(screenFrame: frame, hardwareWidth: 185, hardwareHeight: 32, hasPhysicalNotch: false)
    }

    /// Generates an authentic BoringNotch silhouette with concave top ears that merge into the top screen bezel
    /// and convex rounded bottom corners. Constant segment count enables buttery CoreAnimation path morphing.
    static func makeNotchPath(in rect: CGRect, topEarRadius tR: CGFloat, bottomRadius bR: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let L = rect.minX
        let R = rect.maxX
        let B = rect.minY
        let T = rect.maxY

        let safeTR = min(tR, rect.width * 0.2, rect.height * 0.45)
        let safeBR = min(bR, (rect.width - 2 * safeTR) * 0.45, rect.height - safeTR)

        // Start at top-left outer ear tip (flush with screen top edge)
        path.move(to: CGPoint(x: L, y: T))
        // Concave top-left ear curving smoothly downward into left vertical wall
        path.addQuadCurve(to: CGPoint(x: L + safeTR, y: T - safeTR), control: CGPoint(x: L + safeTR, y: T))
        // Left vertical wall
        path.addLine(to: CGPoint(x: L + safeTR, y: B + safeBR))
        // Convex bottom-left corner
        path.addQuadCurve(to: CGPoint(x: L + safeTR + safeBR, y: B), control: CGPoint(x: L + safeTR, y: B))
        // Bottom edge
        path.addLine(to: CGPoint(x: R - safeTR - safeBR, y: B))
        // Convex bottom-right corner
        path.addQuadCurve(to: CGPoint(x: R - safeTR, y: B + safeBR), control: CGPoint(x: R - safeTR, y: B))
        // Right vertical wall
        path.addLine(to: CGPoint(x: R - safeTR, y: T - safeTR))
        // Concave top-right ear curving smoothly outward into top screen edge
        path.addQuadCurve(to: CGPoint(x: R, y: T), control: CGPoint(x: R - safeTR, y: T))
        path.closeSubpath()
        return path
    }
}

// MARK: - Equalizer Bars (Themed)
class NotchEqualizerView: NSView {
    var isPlaying: Bool = false { didSet { isPlaying ? start() : stop() } }
    var barColor: NSColor = .white { didSet { needsDisplay = true } }
    private var barHeights: [CGFloat] = [0.35, 0.75, 0.50, 0.90]
    private var animTimer: Timer?

    deinit { animTimer?.invalidate() }

    private func start() {
        guard animTimer == nil else { return }
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            self?.barHeights = (0..<4).map { _ in CGFloat.random(in: 0.22...1.0) }
            self?.needsDisplay = true
        }
    }

    private func stop() {
        animTimer?.invalidate(); animTimer = nil
        barHeights = [0.22, 0.22, 0.22, 0.22]
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let barCount = 4, gap: CGFloat = 2.0
        let barW = (bounds.width - CGFloat(barCount - 1) * gap) / CGFloat(barCount)
        let maxH = bounds.height
        barColor.setFill()
        for i in 0..<barCount {
            let h = max(2.5, maxH * barHeights[i])
            let rect = CGRect(x: CGFloat(i) * (barW + gap), y: (maxH - h) / 2.0, width: barW, height: h)
            NSBezierPath(roundedRect: rect, xRadius: 1.2, yRadius: 1.2).fill()
        }
    }
}

// MARK: - Scrubbable Themed Progress Bar
class NotchProgressView: NSView {
    var progress: CGFloat = 0.0 { didSet { needsDisplay = true } }
    var onSeek: ((CGFloat) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let trackH: CGFloat = 5.0
        let trackRect = NSRect(x: 0, y: (bounds.height - trackH) / 2, width: bounds.width, height: trackH)

        kSurface.setFill()
        NSBezierPath(rect: trackRect).fill()
        kBorder.withAlphaComponent(0.55).setStroke()
        let border = NSBezierPath(rect: trackRect)
        border.lineWidth = 1.0
        border.stroke()

        let fillW = max(0, min(bounds.width * progress, bounds.width))
        if fillW > 0 {
            kAccent.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: trackRect.minY, width: fillW, height: trackH)).fill()
        }
    }

    private func seekFromEvent(_ event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let frac = max(0, min(1, loc.x / max(1, bounds.width)))
        progress = frac
        onSeek?(frac)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { seekFromEvent(event) }
    override func mouseDragged(with event: NSEvent) { seekFromEvent(event) }
}

// MARK: - Shelf File Card (Drag Out / Click to Open / Remove)
final class ShelfItemView: NSView, NSDraggingSource {
    let fileURL: URL
    var onRemove: ((URL) -> Void)?

    private let iconView = NSImageView()
    private let nameLabel = NSTextField()
    private let removeBtn = NSButton()
    private var mouseDownPoint: NSPoint = .zero
    private var didStartDrag = false

    init(url: URL) {
        self.fileURL = url
        super.init(frame: .zero)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = kSurface.cgColor
        layer?.borderColor = kBorder.cgColor
        layer?.borderWidth = kBorderWidth

        iconView.image = NSWorkspace.shared.icon(forFile: fileURL.path)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        nameLabel.stringValue = fileURL.lastPathComponent
        nameLabel.font = dynamicFont(size: 9.5, weight: .bold)
        nameLabel.textColor = kText
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.isEditable = false; nameLabel.isBordered = false; nameLabel.backgroundColor = .clear
        addSubview(nameLabel)

        removeBtn.title = "✕"
        removeBtn.font = dynamicFont(size: 8.5, weight: .bold)
        removeBtn.isBordered = false
        removeBtn.contentTintColor = kDim
        removeBtn.target = self; removeBtn.action = #selector(removeTapped)
        addSubview(removeBtn)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        iconView.frame = NSRect(x: (w - 34) / 2, y: h - 46, width: 34, height: 34)
        nameLabel.frame = NSRect(x: 4, y: 6, width: w - 8, height: 22)
        removeBtn.frame = NSRect(x: w - 18, y: h - 18, width: 16, height: 16)
    }

    @objc private func removeTapped() { onRemove?(fileURL) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag else { return }
        let pt = convert(event.locationInWindow, from: nil)
        if hypot(pt.x - mouseDownPoint.x, pt.y - mouseDownPoint.y) < 4 { return }
        didStartDrag = true

        let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        item.setDraggingFrame(NSRect(x: pt.x - 20, y: pt.y - 20, width: 40, height: 40), contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didStartDrag && event.clickCount == 2 {
            NSWorkspace.shared.open(fileURL)
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link] : .copy
    }
}

private final class FirstMouseContainerView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Non-Activating Top Notch Panel (Responds on First Click, Never Steals App Focus)
class NotchWidgetWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

// MARK: - BoringNotch-Inspired Themed Notch View
class NotchWidgetView: NSView {
    let widgetKey = "notch"

    private enum NotchState {
        case idle          // Exact physical notch size (invisible blend when no music)
        case liveActivity  // Physical notch + Left Album Art & Right Live Equalizer wings
        case sneak         // Brief track-change banner peek
        case open          // Full expanded CustomER-themed panel (Home & Shelf tabs)
    }

    private enum NotchTab { case home, pomo, shelf }

    private var state: NotchState = .idle
    private var activeTab: NotchTab = .home
    private var isPinned = false
    private var isDraggingFileOver = false
    private var geometry = NotchGeometry.current()

    // Initial compact idle window size — NSWindow shrinks/grows dynamically with notch state
    // so collapsed states NEVER block clicks over apps below the menu bar.
    static func idleWindowSize(for geom: NotchGeometry) -> NSSize {
        NSSize(width: geom.hardwareWidth + 72, height: ceil(geom.hardwareHeight))
    }

    private let openWidth: CGFloat = 570
    private let openHeight: CGFloat = 196

    // CoreAnimation notch silhouette layers
    private let shapeLayer = CAShapeLayer()
    private let strokeLayer = CAShapeLayer()
    private let cameraCapLayer = CAShapeLayer()
    private let contentMaskLayer = CAShapeLayer()
    private let contentHost = FirstMouseContainerView()

    // Compact Live-Activity / Sneak views (flanking physical notch)
    private let compactArtView = NSImageView()
    private let compactEqView = NotchEqualizerView()
    private let compactPomoTag = NSTextField()
    private let compactPomoTime = NSTextField()
    private let sneakLabel = NSTextField()

    // Expanded header (flanking physical camera cap)
    private let headerContainer = FirstMouseContainerView()
    private let homeTabBtn = NSButton()
    private let pomoTabBtn = NSButton()
    private let shelfTabBtn = NSButton()
    private let batteryBadge = NSTextField()
    private let pinBtn = NSButton()
    private let themeBtn = NSButton()

    // Tab 1: Home (Left: Media Player, Right: Tasks & Today)
    private let homeContainer = FirstMouseContainerView()
    private let mediaCard = NSView()
    private let artView = NSImageView()
    private let playerSourceBadge = NSTextField()
    private let trackLabel = NSTextField()
    private let artistLabel = NSTextField()
    private let progressBar = NotchProgressView()
    private let currTimeLabel = NSTextField()
    private let durTimeLabel = NSTextField()
    private let prevBtn = NSButton()
    private let playBtn = NSButton()
    private let nextBtn = NSButton()
    private let openEqView = NotchEqualizerView()
    private let offlineLabel = NSTextField()

    private let glanceCard = NSView()
    private let glanceHeaderLabel = NSTextField()
    private let glanceDateLabel = NSTextField()
    private let glanceTasksContainer = NSView()
    private let glanceEventsLabel = NSTextField()

    // Tab 2: Minimal Pomodoro Focus Timer
    private let pomoContainer = FirstMouseContainerView()
    private let pomoCard = NSView()
    private let pomoModeLabel = NSTextField()
    private let pomoTimeLabel = NSTextField()
    private let pomoPreset25Btn = NSButton()
    private let pomoPreset50Btn = NSButton()
    private let pomoPreset5Btn = NSButton()
    private let pomoStartBtn = NSButton()
    private let pomoResetBtn = NSButton()

    private var pomoDurationSec: Int = 25 * 60
    private var pomoRemainingSec: Int = 25 * 60
    private var pomoIsBreak: Bool = false
    private var pomoRunning: Bool = false
    private var pomoEndDate: Date?
    private var pomoTimer: Timer?

    // Tab 3: Shelf (Drag & Drop File Staging + AirDrop)
    private let shelfContainer = FirstMouseContainerView()
    private let shelfDropBox = NSView()
    private let shelfEmptyLabel = NSTextField()
    private let shelfScroll = NSScrollView()
    private let shelfContent = NSView()
    private let airDropBtn = NSButton()
    private let clearShelfBtn = NSButton()
    private var shelfURLs: [URL] = []

    // Media & hover state
    private enum MediaSource { case none, spotify, appleMusic }
    private var mediaSource: MediaSource = .none
    private var isPlaying = false
    private var currentTrack = ""
    private var currentArtist = ""
    private var currentArtUrl = ""
    private var currentPosition: Double = 0
    private var currentDuration: Double = 1
    private var artTask: URLSessionDataTask?

    private var localTickTimer: Timer?
    private var openWatchdogTimer: Timer?
    private var resyncCounter = 0
    private var hoverCloseWorkItem: DispatchWorkItem?
    private var sneakDismissWorkItem: DispatchWorkItem?
    private var lastOpenedAt: Date = .distantPast
    private var currentTrackingArea: NSTrackingArea?
    private var currentNotchRect: NSRect = .zero
    private var powerRunLoopSource: CFRunLoopSource?
    private var globalClickMonitor: Any?
    private var isTransitioningWindowFrame = false
    private var isAnimatingCollapse = false
    private var transitionGen: Int = 0
    private var lastLaidOutSize: NSSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        setupObservers()
        refreshMediaState()
        updateBatteryBadge()
        refreshGlancePanel()
        applyState(.idle, animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        localTickTimer?.invalidate()
        openWatchdogTimer?.invalidate()
        pomoTimer?.invalidate()
        artTask?.cancel()
        hoverCloseWorkItem?.cancel()
        sneakDismissWorkItem?.cancel()
        if let src = powerRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Build View Hierarchy
    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes([.fileURL])

        shapeLayer.fillColor = NSColor.black.cgColor
        layer?.addSublayer(shapeLayer)

        strokeLayer.fillColor = NSColor.clear.cgColor
        strokeLayer.lineWidth = 1.0
        layer?.addSublayer(strokeLayer)

        contentHost.wantsLayer = true
        contentHost.layer?.backgroundColor = NSColor.clear.cgColor
        contentHost.layer?.mask = contentMaskLayer
        addSubview(contentHost)

        // Subtle black camera island cap over the physical webcam cutout when expanded in light themes
        cameraCapLayer.fillColor = NSColor.black.cgColor
        contentHost.layer?.addSublayer(cameraCapLayer)

        buildCompactWings()
        buildExpandedHeader()
        buildHomeTab()
        buildPomoTab()
        buildShelfTab()
        applyThemeColors()
    }

    private func buildCompactWings() {
        compactArtView.wantsLayer = true
        compactArtView.layer?.cornerRadius = 4
        compactArtView.layer?.masksToBounds = true
        compactArtView.imageScaling = .scaleAxesIndependently
        contentHost.addSubview(compactArtView)

        compactEqView.barColor = kAccent
        contentHost.addSubview(compactEqView)

        let tagCell = CenteredTextFieldCell(textCell: "FOC")
        tagCell.alignment = .center
        tagCell.font = dynamicFont(size: 9, weight: .bold)
        compactPomoTag.cell = tagCell
        compactPomoTag.font = dynamicFont(size: 9, weight: .bold)
        compactPomoTag.alignment = .center
        compactPomoTag.isEditable = false; compactPomoTag.isBordered = false
        compactPomoTag.drawsBackground = false; compactPomoTag.backgroundColor = .clear
        contentHost.addSubview(compactPomoTag)

        let timeCell = CenteredTextFieldCell(textCell: "25:00")
        timeCell.alignment = .center
        timeCell.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)
        compactPomoTime.cell = timeCell
        compactPomoTime.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .bold)
        compactPomoTime.textColor = .white
        compactPomoTime.alignment = .center
        compactPomoTime.isEditable = false; compactPomoTime.isBordered = false
        compactPomoTime.drawsBackground = false; compactPomoTime.backgroundColor = .clear
        contentHost.addSubview(compactPomoTime)

        sneakLabel.font = dynamicFont(size: 10.5, weight: .bold)
        sneakLabel.textColor = .white
        sneakLabel.alignment = .center
        sneakLabel.lineBreakMode = .byTruncatingTail
        sneakLabel.isEditable = false; sneakLabel.isBordered = false; sneakLabel.backgroundColor = .clear
        contentHost.addSubview(sneakLabel)
    }

    private func buildExpandedHeader() {
        contentHost.addSubview(headerContainer)

        setupTabBtn(homeTabBtn, title: "HOME", action: #selector(selectHomeTab))
        setupTabBtn(pomoTabBtn, title: "POMO", action: #selector(selectPomoTab))
        setupTabBtn(shelfTabBtn, title: "SHELF", action: #selector(selectShelfTab))

        let batCell = CenteredTextFieldCell(textCell: "")
        batCell.alignment = .center
        batCell.font = dynamicFont(size: 9.5, weight: .bold)
        batteryBadge.cell = batCell
        batteryBadge.isEditable = false; batteryBadge.isBordered = false
        batteryBadge.drawsBackground = false; batteryBadge.backgroundColor = .clear
        batteryBadge.wantsLayer = true
        headerContainer.addSubview(batteryBadge)

        pinBtn.title = "PIN"
        pinBtn.font = dynamicFont(size: 9, weight: .bold)
        pinBtn.isBordered = false; pinBtn.wantsLayer = true
        pinBtn.target = self; pinBtn.action = #selector(togglePin)
        headerContainer.addSubview(pinBtn)

        themeBtn.title = "THEME"
        themeBtn.font = dynamicFont(size: 9, weight: .bold)
        themeBtn.isBordered = false; themeBtn.wantsLayer = true
        themeBtn.target = self; themeBtn.action = #selector(cycleThemePreset)
        headerContainer.addSubview(themeBtn)
    }

    private func setupTabBtn(_ btn: NSButton, title: String, action: Selector) {
        btn.title = title
        btn.font = dynamicFont(size: 9.5, weight: .bold)
        btn.isBordered = false; btn.wantsLayer = true
        btn.target = self; btn.action = action
        headerContainer.addSubview(btn)
    }

    private func buildHomeTab() {
        contentHost.addSubview(homeContainer)

        // Left: Media Card
        mediaCard.wantsLayer = true
        homeContainer.addSubview(mediaCard)

        artView.wantsLayer = true; artView.layer?.masksToBounds = true
        artView.imageScaling = .scaleAxesIndependently
        mediaCard.addSubview(artView)

        playerSourceBadge.font = dynamicFont(size: 8.5, weight: .bold)
        playerSourceBadge.isEditable = false; playerSourceBadge.isBordered = false; playerSourceBadge.backgroundColor = .clear
        mediaCard.addSubview(playerSourceBadge)

        trackLabel.font = dynamicFont(size: 13, weight: .bold)
        trackLabel.lineBreakMode = .byTruncatingTail
        trackLabel.isEditable = false; trackLabel.isBordered = false; trackLabel.backgroundColor = .clear
        mediaCard.addSubview(trackLabel)

        artistLabel.font = dynamicFont(size: 10.5, weight: .medium)
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.isEditable = false; artistLabel.isBordered = false; artistLabel.backgroundColor = .clear
        mediaCard.addSubview(artistLabel)

        progressBar.wantsLayer = true
        progressBar.onSeek = { [weak self] frac in self?.seekTo(fraction: frac) }
        mediaCard.addSubview(progressBar)

        currTimeLabel.font = dynamicFont(size: 9, weight: .bold)
        currTimeLabel.isEditable = false; currTimeLabel.isBordered = false; currTimeLabel.backgroundColor = .clear
        mediaCard.addSubview(currTimeLabel)

        durTimeLabel.font = dynamicFont(size: 9, weight: .bold); durTimeLabel.alignment = .right
        durTimeLabel.isEditable = false; durTimeLabel.isBordered = false; durTimeLabel.backgroundColor = .clear
        mediaCard.addSubview(durTimeLabel)

        setupMediaBtn(prevBtn, title: "⏮", action: #selector(onPrev))
        setupMediaBtn(playBtn, title: "▶", action: #selector(onPlayPause))
        setupMediaBtn(nextBtn, title: "⏭", action: #selector(onNext))

        mediaCard.addSubview(openEqView)

        offlineLabel.stringValue = "No Media Playing\nPlay Spotify or Apple Music"
        offlineLabel.font = dynamicFont(size: 11, weight: .bold); offlineLabel.alignment = .center
        offlineLabel.maximumNumberOfLines = 2
        offlineLabel.isEditable = false; offlineLabel.isBordered = false; offlineLabel.backgroundColor = .clear
        mediaCard.addSubview(offlineLabel)

        // Right: CustomER Glance Card (Live Tasks + Calendar Count)
        glanceCard.wantsLayer = true
        homeContainer.addSubview(glanceCard)

        glanceHeaderLabel.stringValue = "TASKS"
        glanceHeaderLabel.font = dynamicFont(size: 9.5, weight: .bold)
        glanceHeaderLabel.isEditable = false; glanceHeaderLabel.isBordered = false; glanceHeaderLabel.backgroundColor = .clear
        glanceCard.addSubview(glanceHeaderLabel)

        glanceDateLabel.font = dynamicFont(size: 9, weight: .bold); glanceDateLabel.alignment = .right
        glanceDateLabel.isEditable = false; glanceDateLabel.isBordered = false; glanceDateLabel.backgroundColor = .clear
        glanceCard.addSubview(glanceDateLabel)

        glanceCard.addSubview(glanceTasksContainer)

        glanceEventsLabel.font = dynamicFont(size: 9, weight: .bold)
        glanceEventsLabel.isEditable = false; glanceEventsLabel.isBordered = false; glanceEventsLabel.backgroundColor = .clear
        glanceCard.addSubview(glanceEventsLabel)
    }

    private func setupMediaBtn(_ btn: NSButton, title: String, action: Selector) {
        btn.title = title
        btn.font = dynamicFont(size: 11.5, weight: .bold)
        btn.isBordered = false; btn.wantsLayer = true
        btn.target = self; btn.action = action
        mediaCard.addSubview(btn)
    }

    private func buildPomoTab() {
        contentHost.addSubview(pomoContainer)

        pomoCard.wantsLayer = true
        pomoContainer.addSubview(pomoCard)

        pomoModeLabel.font = dynamicFont(size: 9.5, weight: .bold)
        pomoModeLabel.isEditable = false; pomoModeLabel.isBordered = false
        pomoModeLabel.drawsBackground = false; pomoModeLabel.backgroundColor = .clear
        pomoCard.addSubview(pomoModeLabel)

        let timerCell = CenteredTextFieldCell(textCell: "25:00")
        timerCell.alignment = .left
        timerCell.font = NSFont.monospacedDigitSystemFont(ofSize: 36, weight: .bold)
        pomoTimeLabel.cell = timerCell
        pomoTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 36, weight: .bold)
        pomoTimeLabel.alignment = .left
        pomoTimeLabel.isEditable = false; pomoTimeLabel.isBordered = false
        pomoTimeLabel.drawsBackground = false; pomoTimeLabel.backgroundColor = .clear
        pomoCard.addSubview(pomoTimeLabel)

        setupPomoBtn(pomoPreset25Btn, title: "25m", fontSize: 10, action: #selector(selectPomo25))
        setupPomoBtn(pomoPreset50Btn, title: "50m", fontSize: 10, action: #selector(selectPomo50))
        setupPomoBtn(pomoPreset5Btn, title: "5m", fontSize: 10, action: #selector(selectPomo5))
        setupPomoBtn(pomoStartBtn, title: "START", fontSize: 11, action: #selector(togglePomo))
        setupPomoBtn(pomoResetBtn, title: "RESET", fontSize: 10, action: #selector(resetPomo))

        updatePomoUI()
    }

    private func setupPomoBtn(_ btn: NSButton, title: String, fontSize: CGFloat, action: Selector) {
        btn.title = title
        btn.font = dynamicFont(size: fontSize, weight: .bold)
        btn.isBordered = false; btn.wantsLayer = true
        btn.target = self; btn.action = action
        pomoCard.addSubview(btn)
    }

    private func buildShelfTab() {
        contentHost.addSubview(shelfContainer)

        shelfDropBox.wantsLayer = true
        shelfContainer.addSubview(shelfDropBox)

        shelfEmptyLabel.stringValue = "DROP FILES HERE TO STAGE OR AIRDROP\nDrag files out anytime into any app"
        shelfEmptyLabel.font = dynamicFont(size: 10.5, weight: .bold)
        shelfEmptyLabel.alignment = .center
        shelfEmptyLabel.maximumNumberOfLines = 2
        shelfEmptyLabel.isEditable = false; shelfEmptyLabel.isBordered = false; shelfEmptyLabel.backgroundColor = .clear
        shelfDropBox.addSubview(shelfEmptyLabel)

        shelfScroll.hasHorizontalScroller = true
        shelfScroll.autohidesScrollers = true
        shelfScroll.drawsBackground = false
        shelfScroll.documentView = shelfContent
        shelfDropBox.addSubview(shelfScroll)

        airDropBtn.title = "AirDrop All"
        airDropBtn.font = dynamicFont(size: 10, weight: .bold)
        airDropBtn.isBordered = false; airDropBtn.wantsLayer = true
        airDropBtn.target = self; airDropBtn.action = #selector(airDropShelvedFiles)
        shelfContainer.addSubview(airDropBtn)

        clearShelfBtn.title = "Clear Shelf"
        clearShelfBtn.font = dynamicFont(size: 10, weight: .bold)
        clearShelfBtn.isBordered = false; clearShelfBtn.wantsLayer = true
        clearShelfBtn.target = self; clearShelfBtn.action = #selector(clearShelf)
        shelfContainer.addSubview(clearShelfBtn)
    }

    private var collapsedTargetState: NotchState {
        ((mediaSource != .none && isPlaying) || pomoRunning) ? .liveActivity : .idle
    }

    // MARK: - Notch Rect Calculations, Dynamic Window Sizing & Layout
    private func windowSize(for targetState: NotchState) -> NSSize {
        let hw = geometry.hardwareWidth
        let hh = geometry.hardwareHeight
        switch targetState {
        case .idle:
            // Strictly inside menu bar: 36px clickable strip flanking physical notch, 0px below menu bar
            return NSSize(width: hw + 72, height: ceil(hh))
        case .liveActivity:
            // Strictly inside the menu bar strip; 0px below menu bar
            let liveW = pomoRunning ? (hw + 112) : (hw + 86)
            return NSSize(width: liveW, height: ceil(hh))
        case .sneak:
            // Passive track/timer banner (ignoresMouseEvents = true while shown)
            return NSSize(width: max(hw + 140, 340) + 4, height: hh + 30)
        case .open:
            // Small outer margin so thick theme borders never clip on left/right/bottom
            return NSSize(width: openWidth + 4, height: openHeight + 4)
        }
    }

    private func windowFrame(for targetState: NotchState) -> NSRect {
        let sf = geometry.screenFrame
        let sz = windowSize(for: targetState)
        return NSRect(
            x: sf.midX - sz.width / 2.0,
            y: sf.maxY - sz.height,
            width: sz.width,
            height: sz.height
        )
    }

    private func rectForState(_ targetState: NotchState) -> (rect: NSRect, topR: CGFloat, bottomR: CGFloat) {
        let midX = bounds.width / 2.0
        let topY = bounds.height
        let hw = geometry.hardwareWidth
        let hh = geometry.hardwareHeight

        switch targetState {
        case .idle:
            let w = hw + 16 // includes 8px top concave ears flush with hardware notch
            return (NSRect(x: midX - w / 2, y: topY - hh, width: w, height: hh), 8, 10)
        case .liveActivity:
            let w = pomoRunning ? (hw + 112) : (hw + 86) // hardware notch + wings + ears
            return (NSRect(x: midX - w / 2, y: topY - hh, width: w, height: hh), 9, 12)
        case .sneak:
            let w = max(hw + 140, 340)
            let h = hh + 28
            return (NSRect(x: midX - w / 2, y: topY - h, width: w, height: h), 12, 16)
        case .open:
            return (NSRect(x: midX - openWidth / 2, y: topY - openHeight, width: openWidth, height: openHeight), 16, 22)
        }
    }

    private func applyState(_ newState: NotchState, animated: Bool) {
        let previousState = state
        state = newState
        if newState == .open && previousState != .open {
            lastOpenedAt = Date()
        }
        transitionGen += 1
        let myGen = transitionGen

        let targetWinFrame = windowFrame(for: newState)
        var translatedStartPath: CGPath? = shapeLayer.presentation()?.path ?? shapeLayer.path
        let startFill: CGColor = shapeLayer.presentation()?.fillColor ?? shapeLayer.fillColor ?? NSColor.black.cgColor
        let startStroke: CGColor = strokeLayer.presentation()?.strokeColor ?? strokeLayer.strokeColor ?? NSColor.clear.cgColor
        var needsDelayedShrink = false
        var shrinkDelay: TimeInterval = 0.45

        if let w = window {
            let oldFrame = w.frame
            let isGrowing = targetWinFrame.width > oldFrame.width + 0.5 || targetWinFrame.height > oldFrame.height + 0.5
            let isShrinking = targetWinFrame.width < oldFrame.width - 0.5 || targetWinFrame.height < oldFrame.height - 0.5

            if !animated {
                isAnimatingCollapse = false
                if isGrowing || isShrinking {
                    isTransitioningWindowFrame = true
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    w.setFrame(targetWinFrame, display: false)
                    CATransaction.commit()
                    isTransitioningWindowFrame = false
                }
                w.ignoresMouseEvents = (newState == .sneak)
            } else if isGrowing {
                // Grow NSWindow first so the spring morph has room, translating in-flight path to new local coords (0 flicker)
                isAnimatingCollapse = false
                let animSize = NSSize(
                    width: max(oldFrame.width, targetWinFrame.width),
                    height: max(oldFrame.height, targetWinFrame.height)
                )
                let animFrame = NSRect(
                    x: geometry.screenFrame.midX - animSize.width / 2.0,
                    y: geometry.screenFrame.maxY - animSize.height,
                    width: animSize.width,
                    height: animSize.height
                )
                if let live = translatedStartPath {
                    var t = CGAffineTransform(
                        translationX: oldFrame.minX - animFrame.minX,
                        y: oldFrame.minY - animFrame.minY
                    )
                    translatedStartPath = live.copy(using: &t) ?? live
                }
                isTransitioningWindowFrame = true
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                w.setFrame(animFrame, display: false)
                w.ignoresMouseEvents = (newState == .sneak)
                CATransaction.commit()
                isTransitioningWindowFrame = false
            } else if isShrinking {
                // Immediately let clicks pass straight through to apps underneath (0ms latency),
                // smoothly morph upward inside the current window, then shrink NSWindow tightly.
                w.ignoresMouseEvents = true
                isAnimatingCollapse = true
                needsDelayedShrink = true
            } else {
                isAnimatingCollapse = false
                w.ignoresMouseEvents = (newState == .sneak)
            }
        }

        let spec = rectForState(newState)
        currentNotchRect = spec.rect
        let newPath = NotchGeometry.makeNotchPath(in: spec.rect, topEarRadius: spec.topR, bottomRadius: spec.bottomR)

        // When idle/liveActivity/sneak: stay sleek black around physical camera cutout with themed rim.
        // When open: morph smoothly into the active CustomER theme background!
        let targetFill: CGColor = (newState == .open) ? kBg.cgColor : NSColor.black.cgColor
        let targetStroke: CGColor = (newState == .open)
            ? kBorder.cgColor
            : (newState == .idle ? NSColor.clear.cgColor : kAccent.withAlphaComponent(0.75).cgColor)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Keep a near-invisible alpha when settled in collapsed strip so WindowServer routes clicks cleanly,
        // but stay clear during animated collapse so the closing spring isn't backed by a faint tint.
        layer?.backgroundColor = ((newState == .idle || newState == .liveActivity) && !needsDelayedShrink)
            ? NSColor(white: 0, alpha: 0.004).cgColor
            : NSColor.clear.cgColor
        contentHost.frame = bounds
        shapeLayer.path = newPath
        shapeLayer.fillColor = targetFill
        strokeLayer.path = newPath
        strokeLayer.strokeColor = targetStroke
        strokeLayer.lineWidth = (newState == .open) ? max(1.0, kBorderWidth) : 1.0
        contentMaskLayer.path = newPath

        // Show subtle black hardware camera cap when expanded (and while collapsing) so light themes stay clean
        let capW = geometry.hardwareWidth + 12
        let capH = geometry.hardwareHeight
        let capRect = NSRect(x: bounds.width / 2 - capW / 2, y: bounds.height - capH, width: capW, height: capH)
        cameraCapLayer.path = NotchGeometry.makeNotchPath(in: capRect, topEarRadius: 7, bottomRadius: 10)
        cameraCapLayer.isHidden = (!geometry.hasPhysicalNotch || (newState != .open && !needsDelayedShrink))

        if animated, let fromPath = translatedStartPath {
            let pathAnim = CASpringAnimation(keyPath: "path")
            pathAnim.fromValue = fromPath
            pathAnim.toValue = newPath
            if needsDelayedShrink {
                pathAnim.damping = 30
                pathAnim.stiffness = 340
                pathAnim.mass = 0.85
            } else {
                pathAnim.damping = 24
                pathAnim.stiffness = 340
                pathAnim.mass = 0.85
            }
            pathAnim.duration = pathAnim.settlingDuration
            if needsDelayedShrink {
                shrinkDelay = min(max(pathAnim.settlingDuration, 0.38), 0.65)
            }

            shapeLayer.add(pathAnim, forKey: "notchPathMorph")
            strokeLayer.add(pathAnim, forKey: "notchStrokeMorph")
            contentMaskLayer.add(pathAnim, forKey: "notchMaskMorph")

            let fillAnim = CABasicAnimation(keyPath: "fillColor")
            fillAnim.fromValue = startFill
            fillAnim.toValue = targetFill
            fillAnim.duration = 0.22
            shapeLayer.add(fillAnim, forKey: "notchFill")

            let strokeAnim = CABasicAnimation(keyPath: "strokeColor")
            strokeAnim.fromValue = startStroke
            strokeAnim.toValue = targetStroke
            strokeAnim.duration = 0.22
            strokeLayer.add(strokeAnim, forKey: "notchStrokeColor")
        } else {
            shapeLayer.removeAllAnimations()
            strokeLayer.removeAllAnimations()
            contentMaskLayer.removeAllAnimations()
        }
        CATransaction.commit()

        lastLaidOutSize = bounds.size
        layoutSubviewsForCurrentState()
        updateTrackingRegion()

        let inCompactWing = (newState == .liveActivity || newState == .sneak)
        let hasPlayingMedia = (mediaSource != .none && isPlaying)
        let showMediaArt = inCompactWing && hasPlayingMedia
        let showMediaEq  = inCompactWing && hasPlayingMedia && !pomoRunning
        let showPomoTag  = inCompactWing && pomoRunning && !hasPlayingMedia
        let showPomoTime = inCompactWing && pomoRunning
        let showSneak = (newState == .sneak)
        let showOpen  = (newState == .open)
        let showHome  = showOpen && activeTab == .home
        let showPomo  = showOpen && activeTab == .pomo
        let showShelf = showOpen && activeTab == .shelf

        // Unhide incoming views immediately, and let outgoing views fade out before hiding
        if showMediaArt { compactArtView.isHidden = false }
        if showMediaEq  { compactEqView.isHidden = false }
        if showPomoTag  { compactPomoTag.isHidden = false }
        if showPomoTime { compactPomoTime.isHidden = false }
        if showSneak    { sneakLabel.isHidden = false }
        if showOpen     { headerContainer.isHidden = false }
        if showHome     { homeContainer.isHidden = false }
        if showPomo     { pomoContainer.isHidden = false }
        if showShelf    { shelfContainer.isHidden = false }

        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = showOpen ? 0.20 : 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                compactArtView.animator().alphaValue  = showMediaArt ? 1 : 0
                compactEqView.animator().alphaValue   = showMediaEq ? 1 : 0
                compactPomoTag.animator().alphaValue  = showPomoTag ? 1 : 0
                compactPomoTime.animator().alphaValue = showPomoTime ? 1 : 0
                sneakLabel.animator().alphaValue      = showSneak ? 1 : 0
                headerContainer.animator().alphaValue = showOpen ? 1 : 0
                homeContainer.animator().alphaValue   = showHome ? 1 : 0
                pomoContainer.animator().alphaValue   = showPomo ? 1 : 0
                shelfContainer.animator().alphaValue  = showShelf ? 1 : 0
            }, completionHandler: { [weak self] in
                guard let self = self, self.transitionGen == myGen else { return }
                self.compactArtView.isHidden  = !showMediaArt
                self.compactEqView.isHidden   = !showMediaEq
                self.compactPomoTag.isHidden  = !showPomoTag
                self.compactPomoTime.isHidden = !showPomoTime
                self.sneakLabel.isHidden      = !showSneak
                self.headerContainer.isHidden = !showOpen
                self.homeContainer.isHidden   = !showHome
                self.pomoContainer.isHidden   = !showPomo
                self.shelfContainer.isHidden  = !showShelf
            })
        } else {
            compactArtView.alphaValue  = showMediaArt ? 1 : 0
            compactEqView.alphaValue   = showMediaEq ? 1 : 0
            compactPomoTag.alphaValue  = showPomoTag ? 1 : 0
            compactPomoTime.alphaValue = showPomoTime ? 1 : 0
            sneakLabel.alphaValue      = showSneak ? 1 : 0
            headerContainer.alphaValue = showOpen ? 1 : 0
            homeContainer.alphaValue   = showHome ? 1 : 0
            pomoContainer.alphaValue   = showPomo ? 1 : 0
            shelfContainer.alphaValue  = showShelf ? 1 : 0

            compactArtView.isHidden  = !showMediaArt
            compactEqView.isHidden   = !showMediaEq
            compactPomoTag.isHidden  = !showPomoTag
            compactPomoTime.isHidden = !showPomoTime
            sneakLabel.isHidden      = !showSneak
            headerContainer.isHidden = !showOpen
            homeContainer.isHidden   = !showHome
            pomoContainer.isHidden   = !showPomo
            shelfContainer.isHidden  = !showShelf
        }

        if showOpen {
            refreshGlancePanel()
            updateBatteryBadge()
            startOpenWatchdog()
        } else {
            stopOpenWatchdog()
        }

        if needsDelayedShrink {
            DispatchQueue.main.asyncAfter(deadline: .now() + shrinkDelay) { [weak self] in
                guard let self = self, self.transitionGen == myGen, self.state == newState else { return }
                self.shrinkWindowToSettledState()
            }
        }
    }

    private func shrinkWindowToSettledState() {
        guard let w = window else {
            isAnimatingCollapse = false
            return
        }
        let targetFrame = windowFrame(for: state)
        isTransitioningWindowFrame = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.removeAllAnimations()
        strokeLayer.removeAllAnimations()
        contentMaskLayer.removeAllAnimations()

        if abs(w.frame.width - targetFrame.width) > 0.5 || abs(w.frame.height - targetFrame.height) > 0.5 ||
           abs(w.frame.minX - targetFrame.minX) > 0.5 || abs(w.frame.minY - targetFrame.minY) > 0.5 {
            w.setFrame(targetFrame, display: true)
        }

        layer?.backgroundColor = (state == .idle || state == .liveActivity)
            ? NSColor(white: 0, alpha: 0.004).cgColor
            : NSColor.clear.cgColor
        contentHost.frame = bounds
        let spec = rectForState(state)
        currentNotchRect = spec.rect
        let settledPath = NotchGeometry.makeNotchPath(in: spec.rect, topEarRadius: spec.topR, bottomRadius: spec.bottomR)
        shapeLayer.path = settledPath
        strokeLayer.path = settledPath
        contentMaskLayer.path = settledPath

        let capW = geometry.hardwareWidth + 12
        let capH = geometry.hardwareHeight
        let capRect = NSRect(x: bounds.width / 2 - capW / 2, y: bounds.height - capH, width: capW, height: capH)
        cameraCapLayer.path = NotchGeometry.makeNotchPath(in: capRect, topEarRadius: 7, bottomRadius: 10)
        cameraCapLayer.isHidden = (state != .open || !geometry.hasPhysicalNotch)

        lastLaidOutSize = bounds.size
        layoutSubviewsForCurrentState()
        updateTrackingRegion()
        w.ignoresMouseEvents = (state == .sneak)
        CATransaction.commit()
        isAnimatingCollapse = false
        isTransitioningWindowFrame = false
    }

    private func startOpenWatchdog() {
        guard openWatchdogTimer == nil else { return }
        openWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            guard let self = self, self.state == .open, !self.isPinned, !self.isDraggingFileOver,
                  let w = self.window else { return }
            if !w.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) {
                self.scheduleCollapse(delay: 0.12)
            }
        }
    }

    private func stopOpenWatchdog() {
        openWatchdogTimer?.invalidate()
        openWatchdogTimer = nil
    }

    private func layoutSubviewsForCurrentState() {
        contentHost.frame = bounds
        let midX = bounds.width / 2.0
        let topY = bounds.height
        let hw = geometry.hardwareWidth
        let hh = geometry.hardwareHeight

        // 1. Compact wings flanking the physical notch cutout
        let artDim: CGFloat = min(22, hh - 8)
        let wingY = topY - hh + (hh - artDim) / 2
        compactArtView.frame  = NSRect(x: midX - hw / 2 - artDim - 10, y: wingY, width: artDim, height: artDim)
        compactEqView.frame   = NSRect(x: midX + hw / 2 + 10, y: topY - hh + (hh - 14) / 2, width: 24, height: 14)
        compactPomoTag.frame  = NSRect(x: midX - hw / 2 - 48, y: topY - hh + (hh - 16) / 2, width: 40, height: 16)
        compactPomoTime.frame = NSRect(x: midX + hw / 2 + 8, y: topY - hh + (hh - 16) / 2, width: 42, height: 16)
        sneakLabel.frame      = NSRect(x: midX - 145, y: topY - hh - 22, width: 290, height: 18)

        guard state == .open || bounds.height >= openHeight else { return }

        // 2. Expanded panel bounds (inset past top concave ears)
        let openSpec = rectForState(.open)
        let innerX = openSpec.rect.minX + 26
        let innerW = openSpec.rect.width - 52
        let openBottom = openSpec.rect.minY

        // Top header bar sits left & right of the physical camera cap
        let headerH: CGFloat = max(28, hh)
        headerContainer.frame = NSRect(x: innerX, y: topY - headerH - 4, width: innerW, height: headerH)
        let hBtnY: CGFloat = (headerH - 20) / 2
        homeTabBtn.frame  = NSRect(x: 0, y: hBtnY, width: 46, height: 20)
        pomoTabBtn.frame  = NSRect(x: 50, y: hBtnY, width: 48, height: 20)
        shelfTabBtn.frame = NSRect(x: 102, y: hBtnY, width: 58, height: 20)

        themeBtn.frame     = NSRect(x: innerW - 50, y: hBtnY, width: 50, height: 20)
        pinBtn.frame       = NSRect(x: innerW - 90, y: hBtnY, width: 34, height: 20)
        batteryBadge.frame = NSRect(x: innerW - 158, y: hBtnY, width: 62, height: 20)

        let bodyY = openBottom + 14
        let bodyH = openHeight - headerH - 24

        // 3. Home Tab (58% Media Player | 42% Tasks & Glance)
        homeContainer.frame = NSRect(x: innerX, y: bodyY, width: innerW, height: bodyH)
        let gap: CGFloat = 10
        let mediaW = floor(innerW * 0.57)
        let glanceW = innerW - mediaW - gap
        mediaCard.frame  = NSRect(x: 0, y: 0, width: mediaW, height: bodyH)
        glanceCard.frame = NSRect(x: mediaW + gap, y: 0, width: glanceW, height: bodyH)

        // Media card internal layout
        let artSize: CGFloat = bodyH - 22
        artView.frame = NSRect(x: 11, y: 11, width: artSize, height: artSize)
        let infoX = artSize + 21
        let infoW = mediaW - infoX - 11
        playerSourceBadge.frame = NSRect(x: infoX, y: bodyH - 23, width: infoW - 30, height: 12)
        openEqView.frame        = NSRect(x: mediaW - 34, y: bodyH - 23, width: 22, height: 12)
        trackLabel.frame        = NSRect(x: infoX, y: bodyH - 44, width: infoW, height: 19)
        artistLabel.frame       = NSRect(x: infoX, y: bodyH - 61, width: infoW, height: 15)
        progressBar.frame       = NSRect(x: infoX, y: 48, width: infoW, height: 12)
        currTimeLabel.frame     = NSRect(x: infoX, y: 35, width: infoW / 2, height: 12)
        durTimeLabel.frame      = NSRect(x: infoX + infoW / 2, y: 35, width: infoW / 2, height: 12)
        let btnW: CGFloat = 38, btnH: CGFloat = 22, btnGap: CGFloat = 6
        prevBtn.frame = NSRect(x: infoX, y: 10, width: btnW, height: btnH)
        playBtn.frame = NSRect(x: infoX + btnW + btnGap, y: 10, width: btnW, height: btnH)
        nextBtn.frame = NSRect(x: infoX + (btnW + btnGap) * 2, y: 10, width: btnW, height: btnH)
        offlineLabel.frame = NSRect(x: 10, y: (bodyH - 36) / 2, width: mediaW - 20, height: 36)

        // Glance card internal layout
        glanceHeaderLabel.frame    = NSRect(x: 10, y: bodyH - 22, width: 80, height: 14)
        glanceDateLabel.frame      = NSRect(x: 84, y: bodyH - 22, width: glanceW - 94, height: 14)
        glanceTasksContainer.frame = NSRect(x: 8, y: 24, width: glanceW - 16, height: bodyH - 50)
        glanceEventsLabel.frame    = NSRect(x: 10, y: 6, width: glanceW - 20, height: 14)

        // 4. Pomodoro Tab layout
        pomoContainer.frame = NSRect(x: innerX, y: bodyY, width: innerW, height: bodyH)
        pomoCard.frame = pomoContainer.bounds
        pomoModeLabel.frame = NSRect(x: 18, y: bodyH - 30, width: 140, height: 16)
        pomoTimeLabel.frame = NSRect(x: 16, y: 20, width: 196, height: bodyH - 54)
        let pRightX: CGFloat = 226
        let pRightW = max(120, innerW - pRightX - 18)
        let pGap: CGFloat = 8
        let presetW = (pRightW - pGap * 2) / 3
        let presetY = bodyH - 52
        pomoPreset25Btn.frame = NSRect(x: pRightX, y: presetY, width: presetW, height: 28)
        pomoPreset50Btn.frame = NSRect(x: pRightX + presetW + pGap, y: presetY, width: presetW, height: 28)
        pomoPreset5Btn.frame  = NSRect(x: pRightX + (presetW + pGap) * 2, y: presetY, width: presetW, height: 28)
        let startW = floor((pRightW - pGap) * 0.62)
        let resetW = pRightW - pGap - startW
        pomoStartBtn.frame = NSRect(x: pRightX, y: 22, width: startW, height: 34)
        pomoResetBtn.frame = NSRect(x: pRightX + startW + pGap, y: 22, width: resetW, height: 34)

        // 5. Shelf Tab layout
        shelfContainer.frame = NSRect(x: innerX, y: bodyY, width: innerW, height: bodyH)
        let actionW: CGFloat = 96
        shelfDropBox.frame   = NSRect(x: 0, y: 0, width: innerW - actionW - 10, height: bodyH)
        shelfEmptyLabel.frame = NSRect(x: 10, y: (bodyH - 34) / 2, width: shelfDropBox.bounds.width - 20, height: 34)
        shelfScroll.frame    = shelfDropBox.bounds.insetBy(dx: 6, dy: 6)
        airDropBtn.frame     = NSRect(x: innerW - actionW, y: bodyH - 34, width: actionW, height: 28)
        clearShelfBtn.frame  = NSRect(x: innerW - actionW, y: bodyH - 68, width: actionW, height: 26)
        layoutShelfItems()
    }

    override func layout() {
        super.layout()
        guard !isTransitioningWindowFrame, !isAnimatingCollapse else { return }
        guard bounds.size != lastLaidOutSize else { return }
        lastLaidOutSize = bounds.size
        applyState(state, animated: false)
    }

    // MARK: - Theme Integration (Live Sync with CustomER ThemeManager)
    private func applyThemeColors() {
        let p = ThemeManager.shared.currentPreset
        let onAccent: NSColor = (p == .glass || p == .childish) ? .white : kSurface

        if state == .open {
            shapeLayer.fillColor = kBg.cgColor
            strokeLayer.strokeColor = kBorder.cgColor
            strokeLayer.lineWidth = max(1.0, kBorderWidth)
        } else if state != .idle {
            strokeLayer.strokeColor = kAccent.withAlphaComponent(0.75).cgColor
        }

        compactEqView.barColor = (p == .minimal) ? kBg : kAccent
        openEqView.barColor = kAccent
        compactPomoTag.textColor = kAccent
        compactPomoTime.textColor = .white

        // Header buttons
        styleHeaderButton(homeTabBtn, active: activeTab == .home, onAccent: onAccent)
        styleHeaderButton(pomoTabBtn, active: activeTab == .pomo, onAccent: onAccent)
        styleHeaderButton(shelfTabBtn, active: activeTab == .shelf, onAccent: onAccent)
        styleHeaderButton(pinBtn, active: isPinned, onAccent: onAccent)
        styleHeaderButton(themeBtn, active: false, onAccent: onAccent)

        batteryBadge.font = dynamicFont(size: 9.5, weight: .bold)
        batteryBadge.textColor = kText
        batteryBadge.layer?.backgroundColor = kSurface.cgColor
        batteryBadge.layer?.borderWidth = kBorderWidth
        batteryBadge.layer?.borderColor = kBorder.cgColor

        // Cards
        for card in [mediaCard, glanceCard, pomoCard, shelfDropBox] {
            card.layer?.backgroundColor = kSurface.cgColor
            card.layer?.borderWidth = kBorderWidth
            card.layer?.borderColor = kBorder.cgColor
            card.layer?.cornerRadius = kRadius / 2
        }

        // Pomodoro colors
        pomoModeLabel.textColor = kAccent
        pomoModeLabel.font = dynamicFont(size: 9.5, weight: .bold)
        pomoTimeLabel.textColor = kText
        styleHeaderButton(pomoPreset25Btn, active: !pomoIsBreak && pomoDurationSec == 25 * 60, onAccent: onAccent)
        styleHeaderButton(pomoPreset50Btn, active: !pomoIsBreak && pomoDurationSec == 50 * 60, onAccent: onAccent)
        styleHeaderButton(pomoPreset5Btn, active: pomoIsBreak && pomoDurationSec == 5 * 60, onAccent: onAccent)
        pomoStartBtn.font = dynamicFont(size: 11, weight: .bold)
        pomoStartBtn.layer?.borderWidth = kBorderWidth
        pomoStartBtn.layer?.borderColor = kBorder.cgColor
        pomoStartBtn.layer?.backgroundColor = kAccent.cgColor
        pomoStartBtn.contentTintColor = onAccent
        styleHeaderButton(pomoResetBtn, active: false, onAccent: onAccent)

        artView.layer?.borderWidth = kBorderWidth
        artView.layer?.borderColor = kBorder.cgColor

        playerSourceBadge.textColor = kAccent
        playerSourceBadge.font = dynamicFont(size: 8.5, weight: .bold)
        trackLabel.textColor = kText
        trackLabel.font = dynamicFont(size: 13, weight: .bold)
        artistLabel.textColor = kDim
        artistLabel.font = dynamicFont(size: 10.5, weight: .medium)
        currTimeLabel.textColor = kText
        currTimeLabel.font = dynamicFont(size: 9, weight: .bold)
        durTimeLabel.textColor = kDim
        durTimeLabel.font = dynamicFont(size: 9, weight: .bold)
        offlineLabel.textColor = kDim
        offlineLabel.font = dynamicFont(size: 11, weight: .bold)

        for btn in [prevBtn, playBtn, nextBtn] {
            btn.font = dynamicFont(size: 11.5, weight: .bold)
            btn.layer?.backgroundColor = kAccent.cgColor
            btn.layer?.borderWidth = kBorderWidth
            btn.layer?.borderColor = kBorder.cgColor
            btn.contentTintColor = onAccent
        }

        glanceHeaderLabel.textColor = kAccent
        glanceHeaderLabel.font = dynamicFont(size: 9.5, weight: .bold)
        glanceDateLabel.textColor = kDim
        glanceDateLabel.font = dynamicFont(size: 9, weight: .bold)
        glanceEventsLabel.textColor = kDim
        glanceEventsLabel.font = dynamicFont(size: 9, weight: .bold)

        shelfEmptyLabel.textColor = kDim
        shelfEmptyLabel.font = dynamicFont(size: 10.5, weight: .bold)

        airDropBtn.font = dynamicFont(size: 10, weight: .bold)
        airDropBtn.layer?.backgroundColor = kAddBg.cgColor
        airDropBtn.layer?.borderWidth = kBorderWidth
        airDropBtn.layer?.borderColor = kBorder.cgColor
        airDropBtn.contentTintColor = onAccent

        clearShelfBtn.font = dynamicFont(size: 10, weight: .bold)
        clearShelfBtn.layer?.backgroundColor = kSurface.cgColor
        clearShelfBtn.layer?.borderWidth = kBorderWidth
        clearShelfBtn.layer?.borderColor = kBorder.cgColor
        clearShelfBtn.contentTintColor = kText

        progressBar.needsDisplay = true
        refreshGlancePanel()
        rebuildShelfCards()
    }

    private func styleHeaderButton(_ btn: NSButton, active: Bool, onAccent: NSColor) {
        btn.font = dynamicFont(size: 9.5, weight: .bold)
        btn.layer?.borderWidth = kBorderWidth
        btn.layer?.borderColor = kBorder.cgColor
        btn.layer?.backgroundColor = active ? kAccent.cgColor : kSurface.cgColor
        btn.contentTintColor = active ? onAccent : kText
    }

    // MARK: - Hit Testing & Hover Mechanics (Click-Through Outside Active Notch)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if state == .idle || state == .liveActivity {
            let hit = local.x >= bounds.minX - 1 && local.x <= bounds.maxX + 1
                && local.y >= bounds.minY - 1 && local.y <= bounds.maxY + 2
            return hit ? self : nil
        }
        let r = currentNotchRect
        let inside = local.x >= r.minX && local.x <= r.maxX
            && local.y >= r.minY && local.y <= r.maxY + 2
        guard inside else { return nil }
        return super.hitTest(point)
    }

    private func updateTrackingRegion() {
        if let existing = currentTrackingArea {
            removeTrackingArea(existing)
        }
        let trackRect = bounds.intersection(currentNotchRect.insetBy(dx: -4, dy: -2))
        let area = NSTrackingArea(
            rect: trackRect.isEmpty ? bounds : trackRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        currentTrackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        hoverCloseWorkItem?.cancel()
    }

    override func mouseExited(with event: NSEvent) {
        guard state == .open, !isPinned, !isDraggingFileOver else { return }
        scheduleCollapse()
    }

    private func scheduleCollapse(delay: TimeInterval = 0.28) {
        hoverCloseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isPinned, !self.isDraggingFileOver else { return }
            self.applyState(self.collapsedTargetState, animated: true)
        }
        hoverCloseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    override func mouseDown(with event: NSEvent) {
        sneakDismissWorkItem?.cancel()
        if state != .open {
            applyState(.open, animated: true)
            return
        }
        let pt = convert(event.locationInWindow, from: nil)
        let hit = super.hitTest(pt)
        if hit is NSButton || hit is NotchProgressView || hit is ShelfItemView {
            super.mouseDown(with: event)
            return
        }
        if !isPinned && Date().timeIntervalSince(lastOpenedAt) > 0.25 {
            applyState(collapsedTargetState, animated: true)
        }
    }

    // MARK: - Drag-and-Drop Shelf (BoringNotch Style)
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
            return []
        }
        isDraggingFileOver = true
        hoverCloseWorkItem?.cancel()
        activeTab = .shelf
        applyThemeColors()
        if state != .open {
            applyState(.open, animated: true)
        } else {
            homeContainer.isHidden = true
            pomoContainer.isHidden = true
            shelfContainer.isHidden = false
            shelfContainer.alphaValue = 1
        }
        shelfDropBox.layer?.borderColor = kAccent.cgColor
        shelfDropBox.layer?.borderWidth = 2.0
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDraggingFileOver ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDraggingFileOver = false
        shelfDropBox.layer?.borderColor = kBorder.cgColor
        shelfDropBox.layer?.borderWidth = kBorderWidth
        scheduleCollapse(delay: 0.5)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        guard isDraggingFileOver else { return }
        isDraggingFileOver = false
        shelfDropBox.layer?.borderColor = kBorder.cgColor
        shelfDropBox.layer?.borderWidth = kBorderWidth
        if state == .open && !isPinned {
            scheduleCollapse(delay: 0.4)
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDraggingFileOver = false
        shelfDropBox.layer?.borderColor = kBorder.cgColor
        shelfDropBox.layer?.borderWidth = kBorderWidth
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return false }

        for u in urls where !shelfURLs.contains(u) {
            shelfURLs.append(u)
        }
        shelfTabBtn.title = shelfURLs.isEmpty ? "SHELF" : "SHELF (\(shelfURLs.count))"
        rebuildShelfCards()
        return true
    }

    private func rebuildShelfCards() {
        shelfContent.subviews.forEach { $0.removeFromSuperview() }
        shelfEmptyLabel.isHidden = !shelfURLs.isEmpty
        shelfScroll.isHidden = shelfURLs.isEmpty
        airDropBtn.isEnabled = !shelfURLs.isEmpty
        clearShelfBtn.isEnabled = !shelfURLs.isEmpty
        shelfTabBtn.title = shelfURLs.isEmpty ? "SHELF" : "SHELF (\(shelfURLs.count))"

        for u in shelfURLs {
            let card = ShelfItemView(url: u)
            card.onRemove = { [weak self] url in
                self?.shelfURLs.removeAll { $0 == url }
                self?.rebuildShelfCards()
            }
            shelfContent.addSubview(card)
        }
        layoutShelfItems()
    }

    private func layoutShelfItems() {
        let cardW: CGFloat = 78
        let cardH = max(72, shelfScroll.bounds.height - 6)
        let gap: CGFloat = 8
        let totalW = max(shelfScroll.bounds.width, CGFloat(shelfURLs.count) * (cardW + gap) + gap)
        shelfContent.frame = NSRect(x: 0, y: 0, width: totalW, height: shelfScroll.bounds.height)
        for (idx, v) in shelfContent.subviews.enumerated() {
            v.frame = NSRect(x: gap + CGFloat(idx) * (cardW + gap), y: 3, width: cardW, height: cardH)
        }
    }

    @objc private func airDropShelvedFiles() {
        guard !shelfURLs.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: shelfURLs)
    }

    @objc private func clearShelf() {
        shelfURLs.removeAll()
        rebuildShelfCards()
    }

    // MARK: - Header Actions & Pomodoro Timer
    @objc private func selectHomeTab() {
        activeTab = .home
        applyThemeColors()
        applyState(.open, animated: false)
    }

    @objc private func selectPomoTab() {
        activeTab = .pomo
        applyThemeColors()
        applyState(.open, animated: false)
    }

    @objc private func selectShelfTab() {
        activeTab = .shelf
        applyThemeColors()
        applyState(.open, animated: false)
    }

    @objc private func selectPomo25() { setPomoPreset(minutes: 25, isBreak: false) }
    @objc private func selectPomo50() { setPomoPreset(minutes: 50, isBreak: false) }
    @objc private func selectPomo5()  { setPomoPreset(minutes: 5, isBreak: true) }

    private func setPomoPreset(minutes: Int, isBreak: Bool) {
        pomoTimer?.invalidate()
        pomoTimer = nil
        pomoRunning = false
        pomoEndDate = nil
        pomoIsBreak = isBreak
        pomoDurationSec = minutes * 60
        pomoRemainingSec = pomoDurationSec
        updatePomoUI()
        applyThemeColors()
    }

    @objc private func togglePomo() {
        if pomoRunning {
            if let end = pomoEndDate {
                pomoRemainingSec = max(0, Int(ceil(end.timeIntervalSinceNow)))
            }
            pomoTimer?.invalidate()
            pomoTimer = nil
            pomoRunning = false
            pomoEndDate = nil
        } else {
            if pomoRemainingSec <= 0 { pomoRemainingSec = pomoDurationSec }
            pomoRunning = true
            pomoEndDate = Date().addingTimeInterval(TimeInterval(pomoRemainingSec))
            pomoTimer?.invalidate()
            pomoTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.tickPomo()
            }
        }
        updatePomoUI()
    }

    @objc private func resetPomo() {
        pomoTimer?.invalidate()
        pomoTimer = nil
        pomoRunning = false
        pomoEndDate = nil
        pomoRemainingSec = pomoDurationSec
        updatePomoUI()
    }

    private func tickPomo() {
        let rem = max(0, Int(ceil((pomoEndDate ?? Date()).timeIntervalSinceNow)))
        pomoRemainingSec = rem
        updatePomoUI()
        if rem == 0 {
            completePomo()
        }
    }

    private func completePomo() {
        pomoTimer?.invalidate()
        pomoTimer = nil
        pomoRunning = false
        pomoEndDate = nil
        NSSound(named: NSSound.Name("Glass"))?.play()

        let wasBreak = pomoIsBreak
        if !wasBreak {
            pomoIsBreak = true
            pomoDurationSec = 5 * 60
            pomoRemainingSec = 5 * 60
        } else {
            pomoIsBreak = false
            pomoDurationSec = 25 * 60
            pomoRemainingSec = 25 * 60
        }
        let bannerText = wasBreak ? "BREAK DONE - READY TO FOCUS" : "FOCUS DONE - 5m BREAK READY"
        updatePomoUI()
        applyThemeColors()

        if state != .open {
            sneakLabel.stringValue = bannerText
            applyState(.sneak, animated: true)
            sneakDismissWorkItem?.cancel()
            let dismiss = DispatchWorkItem { [weak self] in
                guard let self = self, self.state == .sneak else { return }
                self.applyState(self.collapsedTargetState, animated: true)
            }
            sneakDismissWorkItem = dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: dismiss)
        }
    }

    private func updatePomoUI() {
        let formatted = String(format: "%02d:%02d", pomoRemainingSec / 60, pomoRemainingSec % 60)
        pomoTimeLabel.stringValue = formatted
        compactPomoTime.stringValue = formatted
        pomoModeLabel.stringValue = pomoIsBreak ? "BREAK" : "FOCUS"
        compactPomoTag.stringValue = pomoIsBreak ? "BRK" : "FOC"
        pomoStartBtn.title = pomoRunning ? "PAUSE" : "START"
        pomoTabBtn.title = pomoRunning ? formatted : "POMO"
    }

    @objc private func togglePin() {
        isPinned.toggle()
        pinBtn.title = isPinned ? "PIN*" : "PIN"
        applyThemeColors()
    }

    @objc private func cycleThemePreset() {
        ThemeManager.shared.cyclePreset()
    }

    // MARK: - Glance Panel (Live Tasks & Calendar Integration)
    private func refreshGlancePanel() {
        let now = Date()
        glanceDateLabel.stringValue = AppDateFormatters.timeHHmm.string(from: now)

        glanceTasksContainer.subviews.forEach { $0.removeFromSuperview() }
        let activeTasks = ReminderStore.shared.items
            .filter { !$0.isCompleted }
            .sorted { a, b in (a.isStarred != b.isStarred) ? a.isStarred : (a.createdAt > b.createdAt) }

        let visibleTasks = Array(activeTasks.prefix(3))
        let w = max(120, glanceTasksContainer.bounds.width)
        let h = glanceTasksContainer.bounds.height

        if visibleTasks.isEmpty {
            let empty = NSTextField(labelWithString: "All tasks done!")
            empty.font = dynamicFont(size: 10, weight: .medium); empty.textColor = kDim; empty.alignment = .center
            empty.frame = NSRect(x: 0, y: (h - 16) / 2, width: w, height: 16)
            glanceTasksContainer.addSubview(empty)
        } else {
            let rowH: CGFloat = 22
            for (i, task) in visibleTasks.enumerated() {
                let y = h - CGFloat(i + 1) * (rowH + 3)
                let btn = NSButton(frame: NSRect(x: 0, y: y, width: w, height: rowH))
                btn.isBordered = false; btn.alignment = .left
                let prefix = task.isStarred ? "★ " : "☐ "
                btn.attributedTitle = NSAttributedString(string: prefix + task.title, attributes: [
                    .font: dynamicFont(size: 10.5, weight: task.isStarred ? .bold : .medium),
                    .foregroundColor: task.isStarred ? (NSColor(hex: "#F59E0B") ?? kAccent) : kText
                ])
                btn.lineBreakMode = .byTruncatingTail
                btn.target = self; btn.action = #selector(completeTaskFromNotch(_:))
                btn.identifier = NSUserInterfaceItemIdentifier(task.id.uuidString)
                glanceTasksContainer.addSubview(btn)
            }
        }

        let todayKey = HabitStore.currentCycleKey()
        let todayEvents = CalendarEventStore.shared.events(for: todayKey)
        if let firstEv = todayEvents.first {
            glanceEventsLabel.stringValue = "• \(firstEv.title)" + (todayEvents.count > 1 ? " (+\(todayEvents.count - 1))" : "")
        } else {
            glanceEventsLabel.stringValue = "\(activeTasks.count) active • \(AppDateFormatters.fullDate.string(from: now).prefix(14))"
        }
    }

    @objc private func completeTaskFromNotch(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        ReminderStore.shared.toggle(id: id)
        NotificationCenter.default.post(name: NSNotification.Name("com.user.tututodo.reload"), object: nil)
        refreshGlancePanel()
    }

    // MARK: - Live Battery Badge (Event-Driven IOKit)
    private func updateBatteryBadge() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        var pct = 100
        var charging = false
        for src in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, src).takeUnretainedValue() as? [String: Any] {
                pct = info[kIOPSCurrentCapacityKey] as? Int ?? 100
                charging = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                break
            }
        }
        batteryBadge.stringValue = charging ? "\(pct)% CHG" : "\(pct)%"
        batteryBadge.layer?.borderColor = charging ? (NSColor(hex: "#10B981") ?? kBorder).cgColor : kBorder.cgColor
    }

    // MARK: - Event-Driven Media Monitoring (Spotify + Apple Music, Zero Idle Polling)
    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onTasksReload), name: NSNotification.Name("com.user.tututodo.reload"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onScreenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)

        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onSpotifyChanged(_:)), name: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onAppleMusicChanged(_:)), name: Notification.Name("com.apple.Music.playerInfo"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onAppTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ptr in
            guard let ptr = ptr else { return }
            let view = Unmanaged<NotchWidgetView>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async { view.updateBatteryBadge() }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            powerRunLoopSource = src
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self,
                  (self.state == .idle || self.state == .liveActivity),
                  let w = self.window, w.isVisible else { return }
            let pt = NSEvent.mouseLocation
            let f = self.isAnimatingCollapse ? self.windowFrame(for: self.state) : w.frame
            let topLimit = max(f.maxY, self.geometry.screenFrame.maxY) + 2.0
            if pt.x >= f.minX && pt.x <= f.maxX && pt.y >= f.minY && pt.y <= topLimit {
                DispatchQueue.main.async { [self] in
                    if self.state != .open {
                        self.sneakDismissWorkItem?.cancel()
                        self.applyState(.open, animated: true)
                    }
                }
            }
        }
    }

    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            self.applyThemeColors()
            self.needsDisplay = true
        }
    }

    @objc private func onTasksReload() {
        DispatchQueue.main.async { self.refreshGlancePanel() }
    }

    @objc private func onScreenChanged() {
        geometry = NotchGeometry.current(for: window?.screen ?? NSScreen.main)
        repositionWindowToTopCenter()
        applyState(state, animated: false)
    }

    func repositionWindowToTopCenter() {
        guard let w = window else { return }
        geometry = NotchGeometry.current(for: w.screen ?? NSScreen.main)
        isTransitioningWindowFrame = true
        w.setFrame(windowFrame(for: state), display: true)
        isTransitioningWindowFrame = false
        lastLaidOutSize = .zero
        applyState(state, animated: false)
    }

    @objc private func onAppTerminated(_ notif: Notification) {
        guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if (app.bundleIdentifier == "com.spotify.client" && mediaSource == .spotify) ||
           (app.bundleIdentifier == "com.apple.Music" && mediaSource == .appleMusic) {
            DispatchQueue.main.async { self.setMediaOffline() }
        }
    }

    @objc private func onSpotifyChanged(_ notif: Notification) {
        // Use the notification payload directly. Never AppleScript here: Spotify posts this while
        // quitting and `tell application "Spotify"` at that instant relaunches it.
        guard let info = notif.userInfo else { return }
        let playerState = (info["Player State"] as? String) ?? ""
        if playerState == "Stopped" || playerState.isEmpty {
            if mediaSource == .spotify || mediaSource == .none { setMediaOffline() }
            return
        }
        let track = (info["Name"] as? String) ?? ""
        guard !track.isEmpty else { return }
        let artist = (info["Artist"] as? String) ?? ""
        let durMs = (info["Duration"] as? Double) ?? ((info["Duration"] as? Int).map(Double.init) ?? 0)
        let pos = (info["Playback Position"] as? Double) ?? ((info["Playback Position"] as? Int).map(Double.init) ?? currentPosition)
        let trackURI = (info["Track ID"] as? String) ?? ""
        let playing = (playerState == "Playing")
        let res = [track, artist, "", playing ? "true" : "false", String(pos), String(durMs / 1000.0)].joined(separator: "|||")
        handleMediaResult(res, source: .spotify)

        if !trackURI.isEmpty {
            SpotifyArtworkResolver.resolve(trackURI: trackURI) { [weak self] url in
                guard let self = self, let url = url, url != self.currentArtUrl, self.currentTrack == track else { return }
                self.currentArtUrl = url
                self.loadArt(urlStr: url)
            }
        }
    }

    @objc private func onAppleMusicChanged(_ notif: Notification) {
        let playerState = (notif.userInfo?["Player State"] as? String) ?? ""
        if playerState == "Stopped" {
            if mediaSource == .appleMusic || mediaSource == .none { setMediaOffline() }
            return
        }
        // Small delay so a quit-in-progress Music app is already gone before we check `is running`
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refreshAppleMusic()
        }
    }

    private func refreshMediaState() {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty {
            refreshSpotify()
        } else if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
            refreshAppleMusic()
        } else {
            setMediaOffline()
        }
    }

    private func refreshSpotify() {
        guard isAppRunning("com.spotify.client") else {
            setMediaOffline(); return
        }
        let body = """
            if player state is playing or player state is paused then
                set trackName to name of current track
                set artistName to artist of current track
                set artUrl to artwork url of current track
                set pState to (player state is playing)
                set pPos to player position
                set pDur to (duration of current track) / 1000.0
                return trackName & "|||" & artistName & "|||" & artUrl & "|||" & pState & "|||" & pPos & "|||" & pDur
            end if
        """
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let res = runGuardedAppScript(bundleID: "com.spotify.client", appName: "Spotify", body: body)
            DispatchQueue.main.async { self?.handleMediaResult(res, source: .spotify) }
        }
    }

    private func refreshAppleMusic() {
        guard isAppRunning("com.apple.Music") else {
            setMediaOffline(); return
        }
        let body = """
            if player state is playing or player state is paused then
                set trackName to name of current track
                set artistName to artist of current track
                set pState to (player state is playing)
                set pPos to player position
                set pDur to duration of current track
                return trackName & "|||" & artistName & "||||||" & pState & "|||" & pPos & "|||" & pDur
            end if
        """
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let res = runGuardedAppScript(bundleID: "com.apple.Music", appName: "Music", body: body)
            DispatchQueue.main.async { self?.handleMediaResult(res, source: .appleMusic) }
        }
    }

    private func setMediaOffline() {
        mediaSource = .none
        isPlaying = false
        compactEqView.isPlaying = false
        openEqView.isPlaying = false
        updateLocalTicker()
        setMediaControlsHidden(true)
        if state == .liveActivity || state == .sneak {
            applyState(collapsedTargetState, animated: true)
        }
    }

    private func setMediaControlsHidden(_ hidden: Bool) {
        artView.isHidden = hidden
        playerSourceBadge.isHidden = hidden
        trackLabel.isHidden = hidden
        artistLabel.isHidden = hidden
        progressBar.isHidden = hidden
        currTimeLabel.isHidden = hidden
        durTimeLabel.isHidden = hidden
        prevBtn.isHidden = hidden
        playBtn.isHidden = hidden
        nextBtn.isHidden = hidden
        openEqView.isHidden = hidden
        offlineLabel.isHidden = !hidden
    }

    private func handleMediaResult(_ res: String, source: MediaSource) {
        if res == "OFFLINE" || res.isEmpty {
            setMediaOffline()
            return
        }
        let p = res.components(separatedBy: "|||")
        guard p.count >= 6 else { return }

        let track = p[0], artist = p[1], artUrl = p[2]
        let playing = (p[3] == "true")
        let trackChanged = (track != currentTrack && !track.isEmpty)

        mediaSource = source
        currentTrack = track
        currentArtist = artist
        isPlaying = playing
        currentPosition = Double(p[4]) ?? 0
        currentDuration = max(1, Double(p[5]) ?? 1)

        playerSourceBadge.stringValue = (source == .spotify) ? "SPOTIFY" : "APPLE MUSIC"
        trackLabel.stringValue = track
        artistLabel.stringValue = artist
        playBtn.title = playing ? "⏸" : "▶"
        compactEqView.isPlaying = playing
        openEqView.isPlaying = playing
        currTimeLabel.stringValue = fmtTime(currentPosition)
        durTimeLabel.stringValue = fmtTime(currentDuration)
        progressBar.progress = CGFloat(currentPosition / currentDuration)
        setMediaControlsHidden(false)
        updateLocalTicker()

        if !artUrl.isEmpty && artUrl != currentArtUrl {
            currentArtUrl = artUrl
            loadArt(urlStr: artUrl)
        }

        // Trigger BoringNotch sneak-peek on new track when collapsed!
        if state != .open {
            if trackChanged && playing {
                sneakLabel.stringValue = "\(track) — \(artist)"
                applyState(.sneak, animated: true)
                sneakDismissWorkItem?.cancel()
                let dismiss = DispatchWorkItem { [weak self] in
                    guard let self = self, self.state == .sneak else { return }
                    self.applyState(self.collapsedTargetState, animated: true)
                }
                sneakDismissWorkItem = dismiss
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: dismiss)
            } else {
                let desired = collapsedTargetState
                if state != desired {
                    applyState(desired, animated: true)
                }
            }
        }
    }

    private func loadArt(urlStr: String) {
        artTask?.cancel()
        guard let url = URL(string: urlStr) else { return }
        artTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.artView.image = img
                self?.compactArtView.image = img
            }
        }
        artTask?.resume()
    }

    private func updateLocalTicker() {
        if isPlaying {
            guard localTickTimer == nil else { return }
            resyncCounter = 0
            localTickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self, self.isPlaying else { return }
                self.currentPosition = min(self.currentPosition + 1.0, self.currentDuration)
                self.currTimeLabel.stringValue = self.fmtTime(self.currentPosition)
                self.progressBar.progress = CGFloat(self.currentPosition / self.currentDuration)
                self.resyncCounter += 1
                if self.resyncCounter >= 20 {
                    self.resyncCounter = 0
                    self.refreshMediaState()
                }
            }
        } else {
            localTickTimer?.invalidate()
            localTickTimer = nil
        }
    }

    private func fmtTime(_ sec: Double) -> String {
        guard sec > 0 && !sec.isNaN && !sec.isInfinite else { return "0:00" }
        let t = Int(sec)
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private var mediaBundle: (id: String, name: String) {
        mediaSource == .appleMusic ? ("com.apple.Music", "Music") : ("com.spotify.client", "Spotify")
    }

    private func seekTo(fraction: CGFloat) {
        let targetSec = Double(fraction) * currentDuration
        currentPosition = targetSec
        currTimeLabel.stringValue = fmtTime(targetSec)
        let app = mediaBundle
        DispatchQueue.global(qos: .userInitiated).async {
            _ = runGuardedAppScript(bundleID: app.id, appName: app.name, body: "set player position to \(targetSec)")
        }
    }

    @objc private func onPrev() {
        let app = mediaBundle
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = runGuardedAppScript(bundleID: app.id, appName: app.name, body: "previous track")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.refreshMediaState() }
        }
    }

    @objc private func onPlayPause() {
        let app = mediaBundle
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = runGuardedAppScript(bundleID: app.id, appName: app.name, body: "playpause")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.refreshMediaState() }
        }
    }

    @objc private func onNext() {
        let app = mediaBundle
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = runGuardedAppScript(bundleID: app.id, appName: app.name, body: "next track")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.refreshMediaState() }
        }
    }
}
