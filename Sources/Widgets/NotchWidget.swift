import AppKit
import Foundation

// MARK: - 15. DYNAMIC ISLAND / NOTCH SPOTIFY WIDGET (Event-Driven)
class NotchEqualizerView: NSView {
    var isPlaying: Bool = false { didSet { isPlaying ? start() : stop() } }
    private var barHeights: [CGFloat] = [0.3, 0.6, 0.4, 0.8]
    private var animTimer: Timer?

    deinit { animTimer?.invalidate() }

    private func start() {
        guard animTimer == nil else { return }
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            self?.barHeights = (0..<4).map { _ in CGFloat.random(in: 0.2...1.0) }
            self?.needsDisplay = true
        }
    }

    private func stop() {
        animTimer?.invalidate(); animTimer = nil
        barHeights = [0.15, 0.15, 0.15, 0.15]
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let barCount = 4, gap: CGFloat = 2
        let barW = (bounds.width - CGFloat(barCount - 1) * gap) / CGFloat(barCount)
        let maxH = bounds.height
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        for i in 0..<barCount {
            let h = max(2.0, maxH * barHeights[i])
            let rect = CGRect(x: CGFloat(i) * (barW + gap), y: (maxH - h) / 2.0, width: barW, height: h)
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

class NotchProgressView: NSView {
    var progress: CGFloat = 0.0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let trackRect = bounds.insetBy(dx: 0, dy: (bounds.height - 3) / 2)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        NSBezierPath(roundedRect: trackRect, xRadius: 1.5, yRadius: 1.5).fill()
        let fillW = max(0, min(bounds.width * progress, bounds.width))
        if fillW > 0 {
            let fillRect = NSRect(x: 0, y: trackRect.minY, width: fillW, height: trackRect.height)
            ctx.setFillColor(NSColor.white.cgColor)
            NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

class NotchWidgetWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class NotchWidgetView: NSView {
    let widgetKey = "notch"
    private enum State { case collapsed, expanded }
    private var state: State = .collapsed

    private let collapsedW: CGFloat = 210, collapsedH: CGFloat = 34
    private let expandedW: CGFloat = 400, expandedH: CGFloat = 130

    private let container = NSView()
    private let eqView = NotchEqualizerView()
    private let artView = NSImageView()
    private let trackLabel = NSTextField()
    private let artistLabel = NSTextField()
    private let prevBtn = NSButton(), playBtn = NSButton(), nextBtn = NSButton()
    private let progressBar = NotchProgressView()
    private let offlineLabel = NSTextField()

    private var localTickTimer: Timer?
    private var currentPosition: Double = 0
    private var currentDuration: Double = 1
    private var currentArtUrl = ""
    private var isPlaying = false
    private var lastTrack = ""
    private var isOffline = true

    private var dragStartX: CGFloat = 0
    private var initialWinOrigin: NSPoint = .zero
    private var dragActive = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        setupObservers()
        checkSpotify()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        localTickTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func build() {
        wantsLayer = true; layer?.backgroundColor = NSColor.clear.cgColor

        container.wantsLayer = true; container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.borderWidth = 0.5; container.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        addSubview(container)

        container.addSubview(eqView)

        artView.wantsLayer = true; artView.layer?.cornerRadius = 10; artView.layer?.masksToBounds = true
        artView.imageScaling = .scaleAxesIndependently; container.addSubview(artView)

        trackLabel.font = dynamicFont(size: 14, weight: .bold); trackLabel.textColor = .white
        trackLabel.isEditable = false; trackLabel.isBordered = false; trackLabel.backgroundColor = .clear; trackLabel.lineBreakMode = .byTruncatingTail
        container.addSubview(trackLabel)

        artistLabel.font = dynamicFont(size: 11, weight: .medium); artistLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        artistLabel.isEditable = false; artistLabel.isBordered = false; artistLabel.backgroundColor = .clear; artistLabel.lineBreakMode = .byTruncatingTail
        container.addSubview(artistLabel)

        offlineLabel.stringValue = "Spotify Offline"; offlineLabel.font = dynamicFont(size: 13, weight: .bold)
        offlineLabel.textColor = NSColor.white.withAlphaComponent(0.4); offlineLabel.alignment = .center
        offlineLabel.isEditable = false; offlineLabel.isBordered = false; offlineLabel.backgroundColor = .clear
        container.addSubview(offlineLabel)

        setupControlBtn(prevBtn, title: "⏮", action: #selector(onPrev))
        setupControlBtn(playBtn, title: "▶", action: #selector(onPlayPause))
        setupControlBtn(nextBtn, title: "⏭", action: #selector(onNext))

        progressBar.wantsLayer = true; container.addSubview(progressBar)
        applyCollapsedLayout()
    }

    private func setupControlBtn(_ btn: NSButton, title: String, action: Selector) {
        btn.title = title; btn.font = dynamicFont(size: 12, weight: .bold); btn.isBordered = false; btn.wantsLayer = true
        btn.layer?.cornerRadius = 8; btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        btn.contentTintColor = .white; btn.target = self; btn.action = action; container.addSubview(btn)
    }

    private func applyCollapsedLayout() {
        let w = collapsedW, h = collapsedH
        container.frame = NSRect(x: (bounds.width - w) / 2, y: bounds.height - h, width: w, height: h)
        container.layer?.cornerRadius = 14.0
        eqView.isHidden = false; eqView.frame = NSRect(x: (w - 40) / 2, y: (h - 16) / 2, width: 40, height: 16)
        artView.isHidden = true; trackLabel.isHidden = true; artistLabel.isHidden = true
        prevBtn.isHidden = true; playBtn.isHidden = true; nextBtn.isHidden = true
        progressBar.isHidden = true; offlineLabel.isHidden = true
    }

    private func applyExpandedLayout() {
        let w = expandedW, h = expandedH
        container.frame = NSRect(x: (bounds.width - w) / 2, y: bounds.height - h, width: w, height: h)
        container.layer?.cornerRadius = 24.0
        eqView.isHidden = true

        if isOffline {
            artView.isHidden = true; trackLabel.isHidden = true; artistLabel.isHidden = true
            prevBtn.isHidden = true; playBtn.isHidden = true; nextBtn.isHidden = true; progressBar.isHidden = true
            offlineLabel.isHidden = false; offlineLabel.frame = NSRect(x: 0, y: (h - 24) / 2, width: w, height: 24)
            return
        }

        offlineLabel.isHidden = true
        let artSize: CGFloat = 72, margin: CGFloat = 18
        artView.isHidden = false; artView.frame = NSRect(x: margin, y: (h - artSize) / 2, width: artSize, height: artSize)
        let textX = artSize + margin + 12, textW = w - textX - margin
        trackLabel.isHidden = false; trackLabel.frame = NSRect(x: textX, y: h - 58, width: textW, height: 22)
        artistLabel.isHidden = false; artistLabel.frame = NSRect(x: textX, y: h - 80, width: textW, height: 16)
        progressBar.isHidden = false; progressBar.frame = NSRect(x: textX, y: 52, width: textW, height: 4)
        prevBtn.isHidden = false; playBtn.isHidden = false; nextBtn.isHidden = false
        prevBtn.frame = NSRect(x: textX, y: 16, width: 36, height: 28)
        playBtn.frame = NSRect(x: textX + 44, y: 16, width: 36, height: 28)
        nextBtn.frame = NSRect(x: textX + 88, y: 16, width: 36, height: 28)
    }

    override func layout() {
        super.layout()
        if state == .collapsed { applyCollapsedLayout() } else { applyExpandedLayout() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: nil)
        let containerPoint = convert(local, to: container)
        return container.bounds.contains(containerPoint) ? super.hitTest(point) : nil
    }

    private func setupObservers() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(onPlaybackNotification(_:)),
            name: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(onAppTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    @objc private func onAppTerminated(_ notif: Notification) {
        if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == "com.spotify.client" {
            DispatchQueue.main.async { self.handleResult("OFFLINE") }
        }
    }

    @objc private func onPlaybackNotification(_ notif: Notification) {
        checkSpotify()
    }

    private func updateLocalTicker() {
        if isPlaying {
            guard localTickTimer == nil else { return }
            localTickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self, self.isPlaying else { return }
                self.currentPosition = min(self.currentPosition + 1.0, self.currentDuration)
                self.progressBar.progress = self.currentDuration > 0 ? CGFloat(self.currentPosition / self.currentDuration) : 0
            }
        } else {
            localTickTimer?.invalidate()
            localTickTimer = nil
        }
    }

    private func checkSpotify() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else {
            DispatchQueue.main.async { self.handleResult("OFFLINE") }
            return
        }
        let sc = """
        tell application "Spotify"
            if player state is playing or player state is paused then
                set trackName to name of current track
                set artistName to artist of current track
                set artUrl to artwork url of current track
                set pState to (player state is playing)
                set pPos to player position
                set pDur to (duration of current track) / 1000.0
                return trackName & "|||" & artistName & "|||" & artUrl & "|||" & pState & "|||" & pPos & "|||" & pDur
            end if
        end tell
        return "OFFLINE"
        """
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let res = runScript(sc)
            DispatchQueue.main.async { self?.handleResult(res) }
        }
    }

    private func handleResult(_ res: String) {
        if res == "OFFLINE" || res.isEmpty {
            let wasOffline = isOffline
            isOffline = true; isPlaying = false; eqView.isPlaying = false
            updateLocalTicker()
            if state == .expanded && !wasOffline { applyExpandedLayout() }
            return
        }
        isOffline = false
        let p = res.components(separatedBy: "|||")
        guard p.count >= 6 else { return }

        let track = p[0], artist = p[1], artUrl = p[2]
        let playing = (p[3] == "true")
        currentPosition = Double(p[4]) ?? 0
        currentDuration = max(1, Double(p[5]) ?? 1)
        isPlaying = playing
        playBtn.title = playing ? "⏸" : "▶"
        eqView.isPlaying = playing
        updateLocalTicker()

        if track != lastTrack {
            lastTrack = track; trackLabel.stringValue = track; artistLabel.stringValue = artist
            if artUrl != currentArtUrl && !artUrl.isEmpty { currentArtUrl = artUrl; loadArt(url: artUrl) }
            if state == .expanded { applyExpandedLayout() }
        }
        progressBar.progress = CGFloat(currentPosition / currentDuration)
    }

    private func loadArt(url: String) {
        guard let u = URL(string: url) else { return }
        URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
            guard let data = data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.artView.image = img }
        }.resume()
    }

    private func animateTo(_ newState: State) {
        guard state != newState else { return }
        state = newState
        let isExpanded = (newState == .expanded)
        let targetW = isExpanded ? expandedW : collapsedW
        let targetH = isExpanded ? expandedH : collapsedH

        if let w = window, let screen = w.screen ?? NSScreen.main {
            let newFrame = NSRect(x: w.frame.midX - targetW / 2.0, y: screen.frame.maxY - targetH, width: targetW, height: targetH)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                w.animator().setFrame(newFrame, display: true)
                self.layout()
            }, completionHandler: { [weak self] in
                if self?.state == .collapsed { self?.applyCollapsedLayout() }
            })
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if hitTest(pt) is NSButton { super.mouseDown(with: event); return }
        animateTo(state == .collapsed ? .expanded : .collapsed)
        dragStartX = NSEvent.mouseLocation.x
        if let w = window { initialWinOrigin = w.frame.origin }
        dragActive = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { return }
        w.setFrameOrigin(NSPoint(x: initialWinOrigin.x + (NSEvent.mouseLocation.x - dragStartX), y: w.frame.origin.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragActive = false
        if let w = window { PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin) }
    }

    @objc private func onPrev() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = runScript("tell application \"Spotify\" to previous track")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.checkSpotify() }
        }
    }
    @objc private func onPlayPause() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = runScript("tell application \"Spotify\" to playpause")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.checkSpotify() }
        }
    }
    @objc private func onNext() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = runScript("tell application \"Spotify\" to next track")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.checkSpotify() }
        }
    }
}
