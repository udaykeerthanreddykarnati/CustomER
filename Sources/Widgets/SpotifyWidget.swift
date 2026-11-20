import AppKit
import Foundation

// MARK: - 7. SPOTIFY LIVE PLAYER WIDGET (Event-Driven, Zero Idle osascript Polling)
class AudioEqualizerView: NSView {
    var isPlaying: Bool = false { didSet { isPlaying ? startAnimation() : stopAnimation() } }
    private var barHeights: [CGFloat] = [0.3, 0.6, 0.4, 0.8]
    private var animTimer: Timer?

    deinit { animTimer?.invalidate() }

    private func startAnimation() {
        guard animTimer == nil else { return }
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.barHeights = (0..<4).map { _ in CGFloat.random(in: 0.25...1.0) }
            self?.needsDisplay = true
        }
    }

    private func stopAnimation() {
        animTimer?.invalidate(); animTimer = nil
        barHeights = [0.15, 0.15, 0.15, 0.15]
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let barCount = 4, gap: CGFloat = 3
        let barW = (bounds.width - CGFloat(barCount - 1) * gap) / CGFloat(barCount)
        let maxH = bounds.height
        ctx.setFillColor(kAccent.cgColor)
        for i in 0..<barCount {
            let h = max(3.0, maxH * barHeights[i])
            ctx.fill(CGRect(x: CGFloat(i) * (barW + gap), y: (maxH - h) / 2.0, width: barW, height: h))
        }
    }
}

class ProgressBarView: NSView {
    var progress: CGFloat = 0.0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(kSurface.cgColor); ctx.fill(bounds)
        ctx.setStrokeColor(kBorder.cgColor); ctx.setLineWidth(kBorderWidth); ctx.stroke(bounds)
        let fillW = max(0, min(bounds.width * progress, bounds.width))
        if fillW > 0 {
            ctx.setFillColor(kAccent.cgColor); ctx.fill(NSRect(x: 0, y: 0, width: fillW, height: bounds.height))
            let r: CGFloat = 4.0, c = CGPoint(x: fillW, y: bounds.midY)
            ctx.setFillColor(kText.cgColor); ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)); ctx.fillPath()
            ctx.setStrokeColor(kBorder.cgColor); ctx.setLineWidth(1.0); ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)); ctx.strokePath()
        }
    }
}

class SpotifyView: BaseWidgetView {
    private let eqView = AudioEqualizerView()
    private let artImageView = NSImageView()
    private let trackLabel = NSTextField(), artistLabel = NSTextField()
    private let progressBar = ProgressBarView(), currTimeLabel = NSTextField(), durTimeLabel = NSTextField()
    private let prevBtn = NSButton(), playBtn = NSButton(), nextBtn = NSButton(), statusLabel = NSTextField()

    private var localTickTimer: Timer?
    private var resyncTickCounter = 0
    private var currentArtUrl = ""
    private var currentTrackURI = ""
    private var isPlaying = false
    private var currentPosition: Double = 0.0
    private var currentDuration: Double = 1.0
    private var artTask: URLSessionDataTask?

    init(frame: NSRect) {
        super.init(frame: frame, widgetKey: "spotify")
        build()
        setupSpotifyObservers()
        querySpotifyFullState()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        localTickTimer?.invalidate()
        artTask?.cancel()
    }

    private func build() {
        addSubview(eqView)

        artImageView.wantsLayer = true; artImageView.layer?.cornerRadius = 0.0
        artImageView.layer?.borderWidth = kBorderWidth; artImageView.layer?.borderColor = kBorder.cgColor
        artImageView.imageScaling = .scaleAxesIndependently; artImageView.imageAlignment = .alignCenter
        addSubview(artImageView)

        trackLabel.font = dynamicFont(size: 13, weight: .bold); trackLabel.textColor = kText
        trackLabel.isEditable = false; trackLabel.isBordered = false; trackLabel.backgroundColor = .clear; trackLabel.lineBreakMode = .byTruncatingTail
        addSubview(trackLabel)

        artistLabel.font = dynamicFont(size: 11, weight: .bold); artistLabel.textColor = kDim; artistLabel.tag = 99
        artistLabel.isEditable = false; artistLabel.isBordered = false; artistLabel.backgroundColor = .clear; artistLabel.lineBreakMode = .byTruncatingTail
        addSubview(artistLabel)

        progressBar.wantsLayer = true; addSubview(progressBar)

        currTimeLabel.font = dynamicFont(size: 10, weight: .bold); currTimeLabel.textColor = kText
        currTimeLabel.isEditable = false; currTimeLabel.isBordered = false; currTimeLabel.backgroundColor = .clear
        addSubview(currTimeLabel)

        durTimeLabel.font = dynamicFont(size: 10, weight: .bold); durTimeLabel.textColor = kDim; durTimeLabel.tag = 99
        durTimeLabel.isEditable = false; durTimeLabel.isBordered = false; durTimeLabel.backgroundColor = .clear; durTimeLabel.alignment = .right
        addSubview(durTimeLabel)

        setupBtn(prevBtn, title: "⏮", action: #selector(onPrev))
        setupBtn(playBtn, title: "▶", action: #selector(onPlayPause))
        setupBtn(nextBtn, title: "⏭", action: #selector(onNext))

        statusLabel.stringValue = "Spotify Offline"; statusLabel.font = dynamicFont(size: 12, weight: .bold); statusLabel.textColor = kDim; statusLabel.tag = 99
        statusLabel.alignment = .center; statusLabel.isEditable = false; statusLabel.isBordered = false; statusLabel.backgroundColor = .clear; statusLabel.isHidden = true
        addSubview(statusLabel)
    }

    private func setupBtn(_ btn: NSButton, title: String, action: Selector) {
        btn.title = title; btn.font = dynamicFont(size: 12, weight: .bold); btn.isBordered = false; btn.wantsLayer = true; btn.tag = 100
        btn.layer?.cornerRadius = kRadius / 2; btn.layer?.backgroundColor = kAccent.cgColor; btn.layer?.borderWidth = kBorderWidth; btn.layer?.borderColor = kBorder.cgColor
        btn.contentTintColor = (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish) ? .white : kSurface
        btn.target = self; btn.action = action; addSubview(btn)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height, artSize: CGFloat = 96
        eqView.frame = NSRect(x: w - 44, y: h - 22, width: 32, height: 14)
        artImageView.frame = NSRect(x: 12, y: 12, width: artSize, height: artSize)
        let infoX = artSize + 22, infoW = w - infoX - 12
        trackLabel.frame  = NSRect(x: infoX, y: h - 42, width: infoW - 36, height: 20)
        artistLabel.frame = NSRect(x: infoX, y: h - 58, width: infoW, height: 16)
        progressBar.frame   = NSRect(x: infoX, y: 46, width: infoW, height: 6)
        currTimeLabel.frame = NSRect(x: infoX, y: 28, width: infoW / 2, height: 14)
        durTimeLabel.frame  = NSRect(x: infoX + infoW / 2, y: 28, width: infoW / 2, height: 14)
        let btnW: CGFloat = 38, btnH: CGFloat = 20, gap: CGFloat = 6
        prevBtn.frame = NSRect(x: infoX, y: 6, width: btnW, height: btnH)
        playBtn.frame = NSRect(x: infoX + btnW + gap, y: 6, width: btnW, height: btnH)
        nextBtn.frame = NSRect(x: infoX + (btnW + gap) * 2, y: 6, width: btnW, height: btnH)
        statusLabel.frame = NSRect(x: 10, y: (h - 30) / 2, width: w - 20, height: 30)
    }

    // MARK: - Event-Driven Spotify Notifications (Zero Polling When Idle)
    private func setupSpotifyObservers() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(onSpotifyPlaybackNotification(_:)),
            name: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(onAppTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(onAppLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
    }

    @objc private func onAppLaunched(_ notif: Notification) {
        if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == "com.spotify.client" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.querySpotifyFullState()
            }
        }
    }

    @objc private func onAppTerminated(_ notif: Notification) {
        if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == "com.spotify.client" {
            DispatchQueue.main.async { self.showOfflineState() }
        }
    }

    @objc private func onSpotifyPlaybackNotification(_ notif: Notification) {
        // Never respond to a playback notification with AppleScript: Spotify posts one while it is
        // quitting, and a `tell application "Spotify"` at that moment relaunches it.
        // Everything we need is already in the notification payload.
        guard let info = notif.userInfo else { return }
        let playerState = (info["Player State"] as? String) ?? ""
        if playerState == "Stopped" || playerState.isEmpty {
            DispatchQueue.main.async { self.showOfflineState() }
            return
        }
        let track = (info["Name"] as? String) ?? ""
        let artist = (info["Artist"] as? String) ?? ""
        let durationMs = (info["Duration"] as? Double) ?? ((info["Duration"] as? Int).map(Double.init) ?? 0)
        let position = (info["Playback Position"] as? Double) ?? ((info["Playback Position"] as? Int).map(Double.init))
        let trackURI = (info["Track ID"] as? String) ?? ""
        let playing = (playerState == "Playing")

        DispatchQueue.main.async {
            guard !track.isEmpty else { return }
            self.trackLabel.stringValue = track
            self.artistLabel.stringValue = artist
            if durationMs > 0 { self.currentDuration = durationMs / 1000.0 }
            if let pos = position { self.currentPosition = pos }
            self.isPlaying = playing
            self.playBtn.title = playing ? "⏸" : "▶"
            self.eqView.isPlaying = playing
            self.currTimeLabel.stringValue = self.fmtTime(self.currentPosition)
            self.durTimeLabel.stringValue = self.fmtTime(self.currentDuration)
            self.progressBar.progress = self.currentDuration > 0 ? CGFloat(self.currentPosition / self.currentDuration) : 0.0
            self.setControlsHidden(false)
            self.updateLocalTicker()

            if !trackURI.isEmpty && trackURI != self.currentTrackURI {
                self.currentTrackURI = trackURI
                SpotifyArtworkResolver.resolve(trackURI: trackURI) { [weak self] url in
                    guard let self = self, let url = url, url != self.currentArtUrl else { return }
                    self.currentArtUrl = url
                    self.loadArtwork(from: url)
                }
            }
        }
    }

    private func isSpotifyRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
    }

    private func updateLocalTicker() {
        if isPlaying {
            guard localTickTimer == nil else { return }
            resyncTickCounter = 0
            localTickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self, self.isPlaying else { return }
                self.currentPosition = min(self.currentPosition + 1.0, self.currentDuration)
                self.currTimeLabel.stringValue = self.fmtTime(self.currentPosition)
                self.durTimeLabel.stringValue = self.fmtTime(self.currentDuration)
                self.progressBar.progress = self.currentDuration > 0 ? CGFloat(self.currentPosition / self.currentDuration) : 0.0
                self.resyncTickCounter += 1
                // Resync drift only once every 20s while actively playing (instead of every 1s!)
                if self.resyncTickCounter >= 20 {
                    self.resyncTickCounter = 0
                    self.querySpotifyFullState()
                }
            }
        } else {
            localTickTimer?.invalidate()
            localTickTimer = nil
        }
    }

    private func fmtTime(_ sec: Double) -> String {
        guard sec > 0 && !sec.isNaN && !sec.isInfinite else { return "0:00" }
        let t = Int(sec); return String(format: "%d:%02d", t / 60, t % 60)
    }

    private func querySpotifyFullState() {
        guard isSpotifyRunning() else {
            DispatchQueue.main.async { self.showOfflineState() }
            return
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
            DispatchQueue.main.async { self?.handleSpotifyResult(res) }
        }
    }

    private func showOfflineState() {
        isPlaying = false
        eqView.isPlaying = false
        updateLocalTicker()
        setControlsHidden(true)
        statusLabel.stringValue = "Spotify Offline"
    }

    private func setControlsHidden(_ hidden: Bool) {
        eqView.isHidden = hidden
        artImageView.isHidden = hidden
        trackLabel.isHidden = hidden
        artistLabel.isHidden = hidden
        progressBar.isHidden = hidden
        currTimeLabel.isHidden = hidden
        durTimeLabel.isHidden = hidden
        prevBtn.isHidden = hidden
        playBtn.isHidden = hidden
        nextBtn.isHidden = hidden
        statusLabel.isHidden = !hidden
    }

    private func handleSpotifyResult(_ res: String) {
        if res == "OFFLINE" || res.isEmpty {
            showOfflineState()
            return
        }
        let p = res.components(separatedBy: "|||")
        guard p.count >= 6 else { return }
        trackLabel.stringValue = p[0]
        artistLabel.stringValue = p[1]
        isPlaying = (p[3] == "true")
        playBtn.title = isPlaying ? "⏸" : "▶"
        eqView.isPlaying = isPlaying
        currentPosition = Double(p[4]) ?? 0.0
        currentDuration = max(1.0, Double(p[5]) ?? 1.0)
        currTimeLabel.stringValue = fmtTime(currentPosition)
        durTimeLabel.stringValue = fmtTime(currentDuration)
        progressBar.progress = CGFloat(currentPosition / currentDuration)
        setControlsHidden(false)
        updateLocalTicker()

        if p[2] != currentArtUrl && !p[2].isEmpty {
            currentArtUrl = p[2]
            loadArtwork(from: p[2])
        }
    }

    private func loadArtwork(from urlStr: String) {
        artTask?.cancel()
        guard let url = URL(string: urlStr) else { return }
        artTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard error == nil, let data = data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.artImageView.image = img }
        }
        artTask?.resume()
    }

    @objc private func onPrev() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = runGuardedAppScript(bundleID: "com.spotify.client", appName: "Spotify", body: "previous track")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.querySpotifyFullState() }
        }
    }

    @objc private func onPlayPause() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = runGuardedAppScript(bundleID: "com.spotify.client", appName: "Spotify", body: "playpause")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.querySpotifyFullState() }
        }
    }

    @objc private func onNext() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = runGuardedAppScript(bundleID: "com.spotify.client", appName: "Spotify", body: "next track")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.querySpotifyFullState() }
        }
    }

    override func applyTheme(preset: ThemePreset) {
        artImageView.layer?.borderColor = preset.borderColor.cgColor
        artImageView.layer?.borderWidth = preset.borderWidth
        for btn in [prevBtn, playBtn, nextBtn] {
            btn.layer?.cornerRadius = preset.cornerRadius / 2
            btn.layer?.backgroundColor = kAccent.cgColor
            btn.layer?.borderColor = preset.borderColor.cgColor
            btn.layer?.borderWidth = preset.borderWidth
            btn.contentTintColor = (preset == .glass || preset == .childish) ? .white : kSurface
            btn.font = dynamicFont(size: 12, weight: .bold)
        }
        updateThemeRecursively(preset: preset)
        progressBar.needsDisplay = true
        eqView.needsDisplay = true
    }
}
