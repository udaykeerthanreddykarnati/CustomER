import AppKit
import Foundation

// MARK: - Colors (Matching Theme)
let kBg     = NSColor(red: 254/255.0, green: 249/255.0, blue: 195/255.0, alpha: 1.00) // #FEF9C3 Pastel Butter
let kText   = NSColor(red: 128/255.0, green: 0/255.0, blue: 32/255.0, alpha: 1.00)       // #800020 Rich Burgundy
let kAccent = NSColor(red: 128/255.0, green: 0/255.0, blue: 32/255.0, alpha: 1.00)       // #800020 Rich Burgundy
let kDim    = NSColor(red: 0.35, green: 0.35, blue: 0.25, alpha: 1.00)                 // Muted text
let kBorder = NSColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.00)                 // Black outline

extension NSColor {
    convenience init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6, let val = UInt64(str, radix: 16) else { return nil }
        let r = CGFloat((val & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((val & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(val & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

class ThemeManager {
    static let shared = ThemeManager()
    static let notifName = NSNotification.Name("com.user.CustomER.themeChanged")
    private let themeFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CustomER", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("theme.json")
    }()
    var currentBgColor: NSColor {
        if let data = try? Data(contentsOf: themeFileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let hex = json["bgHex"],
           let color = NSColor(hex: hex) {
            return color
        }
        return kBg
    }
}

// MARK: - Animated Equalizer View
class AudioEqualizerView: NSView {
    var isPlaying: Bool = false {
        didSet {
            if isPlaying {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }

    private var barHeights: [CGFloat] = [0.3, 0.6, 0.4, 0.8]
    private var animTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func startAnimation() {
        guard animTimer == nil else { return }
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.barHeights = (0..<4).map { _ in CGFloat.random(in: 0.25...1.0) }
            self?.needsDisplay = true
        }
    }

    private func stopAnimation() {
        animTimer?.invalidate()
        animTimer = nil
        barHeights = [0.15, 0.15, 0.15, 0.15]
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let barCount = 4
        let gap: CGFloat = 3
        let totalW = bounds.width
        let barW = (totalW - CGFloat(barCount - 1) * gap) / CGFloat(barCount)
        let maxH = bounds.height

        ctx.setFillColor(kAccent.cgColor)

        for i in 0..<barCount {
            let h = max(3.0, maxH * barHeights[i])
            let x = CGFloat(i) * (barW + gap)
            let y = (maxH - h) / 2.0
            let rect = CGRect(x: x, y: y, width: barW, height: h)
            ctx.fill(rect)
        }
    }
}

// MARK: - Progress Bar View
class ProgressBarView: NSView {
    var progress: CGFloat = 0.0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Track background
        let trackRect = bounds
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.12).cgColor)
        ctx.fill(trackRect)

        ctx.setStrokeColor(kBorder.cgColor)
        ctx.setLineWidth(1.0)
        ctx.stroke(trackRect)

        // Progress fill
        let fillW = max(0, min(bounds.width * progress, bounds.width))
        if fillW > 0 {
            let fillRect = NSRect(x: 0, y: 0, width: fillW, height: bounds.height)
            ctx.setFillColor(kAccent.cgColor)
            ctx.fill(fillRect)

            // Playhead dot
            let dotRadius: CGFloat = 4.0
            let dotCenter = CGPoint(x: fillW, y: bounds.midY)
            ctx.setFillColor(kText.cgColor)
            ctx.addEllipse(in: CGRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
            ctx.fillPath()
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.0)
            ctx.addEllipse(in: CGRect(x: dotCenter.x - dotRadius, y: dotCenter.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
            ctx.strokePath()
        }
    }
}

class SpotifyWindow: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

class SpotifyView: NSView {
    private let eqView       = AudioEqualizerView()
    private let artImageView = NSImageView()

    private let trackLabel  = NSTextField()
    private let artistLabel = NSTextField()

    private let progressBar   = ProgressBarView()
    private let currTimeLabel = NSTextField()
    private let durTimeLabel  = NSTextField()

    private let prevBtn = NSButton()
    private let playBtn = NSButton()
    private let nextBtn = NSButton()

    private let statusLabel = NSTextField()
    private var timer: Timer?

    private var currentArtUrl: String = ""
    private var isPlaying: Bool = false

    private var dragStart: NSPoint = .zero
    private var dragActive = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        updateSpotifyInfo()
        startTimer()
        listenForThemeChanges()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        layer?.borderWidth = 0

        // Equalizer View
        addSubview(eqView)

        // Static Album Cover Song Icon (Square)
        artImageView.wantsLayer = true
        artImageView.layer?.cornerRadius = 0
        artImageView.layer?.borderWidth = 1.5
        artImageView.layer?.borderColor = kBorder.cgColor
        artImageView.imageScaling = .scaleAxesIndependently
        artImageView.imageAlignment = .alignCenter
        addSubview(artImageView)

        // Track Name
        trackLabel.font = NSFont.systemFont(ofSize: 13, weight: .black)
        trackLabel.textColor = kText
        trackLabel.isEditable = false; trackLabel.isBordered = false; trackLabel.backgroundColor = .clear
        trackLabel.lineBreakMode = .byTruncatingTail
        addSubview(trackLabel)

        // Artist Name
        artistLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        artistLabel.textColor = kDim
        artistLabel.isEditable = false; artistLabel.isBordered = false; artistLabel.backgroundColor = .clear
        artistLabel.lineBreakMode = .byTruncatingTail
        addSubview(artistLabel)

        // Progress Bar
        progressBar.wantsLayer = true
        addSubview(progressBar)

        // Current Time Label
        currTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        currTimeLabel.textColor = kText
        currTimeLabel.isEditable = false; currTimeLabel.isBordered = false; currTimeLabel.backgroundColor = .clear
        currTimeLabel.alignment = .left
        addSubview(currTimeLabel)

        // Duration Label
        durTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        durTimeLabel.textColor = kDim
        durTimeLabel.isEditable = false; durTimeLabel.isBordered = false; durTimeLabel.backgroundColor = .clear
        durTimeLabel.alignment = .right
        addSubview(durTimeLabel)

        // Control Buttons
        setupButton(prevBtn, title: "⏮", action: #selector(onPrev))
        setupButton(playBtn, title: "▶", action: #selector(onPlayPause))
        setupButton(nextBtn, title: "⏭", action: #selector(onNext))

        // Status Label when offline
        statusLabel.stringValue = "🎵 Spotify Offline"
        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        statusLabel.textColor = kDim
        statusLabel.alignment = .center
        statusLabel.isEditable = false; statusLabel.isBordered = false; statusLabel.backgroundColor = .clear
        statusLabel.isHidden = true
        addSubview(statusLabel)
    }

    private func setupButton(_ btn: NSButton, title: String, action: Selector) {
        btn.title = title
        btn.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 0
        btn.layer?.backgroundColor = kText.cgColor
        btn.layer?.borderWidth = 1
        btn.layer?.borderColor = kBorder.cgColor
        btn.contentTintColor = .white
        btn.target = self
        btn.action = action
        addSubview(btn)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let artSize: CGFloat = 96

        // Top Header
        eqView.frame = NSRect(x: w - 44, y: h - 22, width: 32, height: 14)

        artImageView.frame = NSRect(x: 12, y: 12, width: artSize, height: artSize)

        let infoX = artSize + 22
        let infoW = w - infoX - 12

        trackLabel.frame  = NSRect(x: infoX, y: h - 42, width: infoW - 36, height: 20)
        artistLabel.frame = NSRect(x: infoX, y: h - 58, width: infoW, height: 16)

        // Progress bar & times
        progressBar.frame   = NSRect(x: infoX, y: 46, width: infoW, height: 6)
        currTimeLabel.frame = NSRect(x: infoX, y: 28, width: infoW / 2, height: 14)
        durTimeLabel.frame  = NSRect(x: infoX + infoW / 2, y: 28, width: infoW / 2, height: 14)

        // Buttons
        let btnW: CGFloat = 38, btnH: CGFloat = 20, gap: CGFloat = 6
        prevBtn.frame = NSRect(x: infoX, y: 6, width: btnW, height: btnH)
        playBtn.frame = NSRect(x: infoX + btnW + gap, y: 6, width: btnW, height: btnH)
        nextBtn.frame = NSRect(x: infoX + (btnW + gap) * 2, y: 6, width: btnW, height: btnH)

        statusLabel.frame = NSRect(x: 10, y: (h - 30)/2, width: w - 20, height: 30)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateSpotifyInfo()
        }
    }

    private func runAppleScript(_ code: String) -> String {
        var error: NSDictionary?
        if let script = NSAppleScript(source: code) {
            let output = script.executeAndReturnError(&error)
            return output.stringValue ?? ""
        }
        return ""
    }

    private func formatTime(_ sec: Double) -> String {
        guard sec > 0 && !sec.isNaN && !sec.isInfinite else { return "0:00" }
        let total = Int(sec)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    @objc private func updateSpotifyInfo() {
        let script = """
        tell application "System Events"
            set isRunning to (name of processes) contains "Spotify"
        end tell
        if isRunning then
            tell application "Spotify"
                if player state is playing or player state is paused then
                    set trackName to name of current track
                    set artistName to artist of current track
                    set artworkUrl to artwork url of current track
                    set pState to (player state is playing)
                    set pPos to player position
                    set pDur to (duration of current track) / 1000.0
                    return trackName & "|||" & artistName & "|||" & artworkUrl & "|||" & pState & "|||" & pPos & "|||" & pDur
                end if
            end tell
        end if
        return "OFFLINE"
        """

        let result = runAppleScript(script)
        if result == "OFFLINE" || result.isEmpty {
            eqView.isPlaying = false
            eqView.isHidden = true
            artImageView.isHidden = true
            trackLabel.isHidden = true
            artistLabel.isHidden = true
            progressBar.isHidden = true
            currTimeLabel.isHidden = true
            durTimeLabel.isHidden = true
            prevBtn.isHidden = true
            playBtn.isHidden = true
            nextBtn.isHidden = true
            statusLabel.stringValue = "🎵 Spotify Offline"
            statusLabel.isHidden = false
        } else {
            let parts = result.components(separatedBy: "|||")
            if parts.count >= 6 {
                let track = parts[0]
                let artist = parts[1]
                let artUrl = parts[2]
                let playing = (parts[3] == "true")
                let pos = Double(parts[4]) ?? 0.0
                let dur = Double(parts[5]) ?? 1.0

                trackLabel.stringValue = track
                artistLabel.stringValue = artist
                isPlaying = playing
                playBtn.title = isPlaying ? "⏸" : "▶"

                eqView.isPlaying = isPlaying

                currTimeLabel.stringValue = formatTime(pos)
                durTimeLabel.stringValue = formatTime(dur)
                progressBar.progress = dur > 0 ? CGFloat(pos / dur) : 0.0

                statusLabel.isHidden = true
                eqView.isHidden = false
                artImageView.isHidden = false
                trackLabel.isHidden = false
                artistLabel.isHidden = false
                progressBar.isHidden = false
                currTimeLabel.isHidden = false
                durTimeLabel.isHidden = false
                prevBtn.isHidden = false
                playBtn.isHidden = false
                nextBtn.isHidden = false

                if artUrl != currentArtUrl && !artUrl.isEmpty {
                    currentArtUrl = artUrl
                    loadArtwork(from: artUrl)
                }
            }
        }
    }

    private func loadArtwork(from urlStr: String) {
        guard let url = URL(string: urlStr) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            if let data = data, let img = NSImage(data: data) {
                DispatchQueue.main.async {
                    self?.artImageView.image = img
                }
            }
        }.resume()
    }

    // Actions
    @objc private func onPrev() {
        _ = runAppleScript("tell application \"Spotify\" to previous track")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.updateSpotifyInfo() }
    }

    @objc private func onPlayPause() {
        _ = runAppleScript("tell application \"Spotify\" to playpause")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.updateSpotifyInfo() }
    }

    @objc private func onNext() {
        _ = runAppleScript("tell application \"Spotify\" to next track")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.updateSpotifyInfo() }
    }

    // Theme changes
    private func listenForThemeChanges() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(onThemeChanged),
            name: ThemeManager.notifName,
            object: nil
        )
    }

    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            }
        }
    }

    // Dragging
    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow; dragActive = true; window?.makeKey()
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { super.mouseDragged(with: event); return }
        let c = event.locationInWindow
        w.setFrameOrigin(NSPoint(x: w.frame.origin.x + c.x - dragStart.x,
                                  y: w.frame.origin.y + c.y - dragStart.y))
    }

    override func mouseUp(with event: NSEvent) { dragActive = false; super.mouseUp(with: event) }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 320, y: 440, width: 280, height: 130)
        window = SpotifyWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: -1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false
        window.contentView = SpotifyView(frame: rect)
        window.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
