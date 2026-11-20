import AppKit
import Foundation

// MARK: - Center Wallpaper Expansion Transition Manager
final class CenterWallpaperTransitionManager {
    static let shared = CenterWallpaperTransitionManager()
    private var transitionWindow: NSWindow?
    private var transitionImageView: NSView?
    private var isAnimating = false

    func animateAndSetWallpaper(url: URL, completion: (() -> Void)? = nil) {
        guard !isAnimating, let screen = NSScreen.main else {
            completion?()
            return
        }
        isAnimating = true
        let screenFrame = screen.frame

        DispatchQueue.global(qos: .userInitiated).async {
            guard let img = NSImage(contentsOf: url) else {
                self.setNativeWallpaper(url: url) {
                    DispatchQueue.main.async {
                        self.isAnimating = false
                        completion?()
                    }
                }
                return
            }

            DispatchQueue.main.async {
                self.runCenterExpandAnimation(url: url, img: img, screenFrame: screenFrame, completion: completion)
            }
        }
    }

    private func runCenterExpandAnimation(url: URL, img: NSImage, screenFrame: NSRect, completion: (() -> Void)?) {
        if transitionWindow == nil {
            let win = NSWindow(contentRect: screenFrame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            win.ignoresMouseEvents = true

            let iv = NSView(frame: screenFrame)
            iv.wantsLayer = true
            iv.layer?.contentsGravity = .resizeAspectFill
            win.contentView = iv

            transitionWindow = win
            transitionImageView = iv
        }

        guard let win = transitionWindow, let iv = transitionImageView else {
            isAnimating = false; completion?(); return
        }

        win.setFrame(screenFrame, display: false)
        let startW: CGFloat = 180, startH: CGFloat = 112
        let startFrame = NSRect(x: screenFrame.midX - startW / 2, y: screenFrame.midY - startH / 2, width: startW, height: startH)

        if let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            iv.layer?.contents = cgImg
        }
        iv.layer?.contentsGravity = .resizeAspectFill
        iv.alphaValue = 0.0
        iv.frame = startFrame
        iv.layer?.cornerRadius = 20
        iv.layer?.masksToBounds = true
        iv.layer?.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
        iv.layer?.borderWidth = 2.0

        win.orderFrontRegardless()
        win.display()
        completion?()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            iv.animator().frame = screenFrame
            iv.animator().layer?.cornerRadius = 0
            iv.animator().layer?.borderWidth = 0
            iv.animator().alphaValue = 1.0
        }, completionHandler: {
            self.setNativeWallpaper(url: url) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.40) {
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration = 0.65
                        ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        iv.animator().alphaValue = 0.0
                    }, completionHandler: {
                        win.orderOut(nil)
                        self.isAnimating = false
                    })
                }
            }
        })
    }

    private func setNativeWallpaper(url: URL, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            for screen in NSScreen.screens {
                try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            }
            completion?()
        }
    }
}

// MARK: - 13. WALLPAPER SWITCHER WIDGET (Option + W)
class WallpaperPickerView: BaseWidgetView {
    private let titleLabel      = NSTextField()
    private let pathLabel       = NSTextField()
    private let chooseFolderBtn = NSButton()
    private let randomBtn       = NSButton()
    private let scrollView      = NSScrollView()
    private let contentView     = NSView()

    private var wallpaperFolderURL: URL = {
        if let savedPath = UserDefaults.standard.string(forKey: "customER_wallpaper_folder"),
           FileManager.default.fileExists(atPath: savedPath) {
            return URL(fileURLWithPath: savedPath)
        }
        let defaultWalls = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Wallpapers")
        if FileManager.default.fileExists(atPath: defaultWalls.path) {
            return defaultWalls
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
    }()

    private var imageURLs: [URL] = []
    private var activeWallpaperURL: URL?
    private let thumbnailCache = NSCache<NSURL, NSImage>()
    private var folderWatcher: DispatchSourceFileSystemObject?
    private var lastRenderedBoundsSize: NSSize = .zero
    private var lastRenderedURLsCount: Int = 0

    init(frame: NSRect) {
        super.init(frame: frame, widgetKey: "wallpaper_switcher")
        build()
        loadWallpapers()
        startWatchingFolder()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { stopWatchingFolder() }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow != nil { loadWallpapers() }
    }

    private func startWatchingFolder() {
        stopWatchingFolder()
        let fd = open(wallpaperFolderURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .link, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.loadWallpapers() }
        // Close fd exclusively in cancel handler (fixes double-close bug!)
        source.setCancelHandler { close(fd) }
        folderWatcher = source
        source.resume()
    }

    private func stopWatchingFolder() {
        folderWatcher?.cancel()
        folderWatcher = nil
    }

    private func build() {
        titleLabel.stringValue = "WALLPAPER SWITCHER"
        titleLabel.font = dynamicFont(size: 13, weight: .bold); titleLabel.textColor = kText
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        pathLabel.stringValue = ""; pathLabel.font = dynamicFont(size: 10, weight: .bold); pathLabel.textColor = kDim; pathLabel.tag = 99
        pathLabel.alignment = .right; pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.isEditable = false; pathLabel.isBordered = false; pathLabel.backgroundColor = .clear
        addSubview(pathLabel)

        setupBtn(chooseFolderBtn, title: "Choose Folder", action: #selector(onChooseFolder))
        setupBtn(randomBtn, title: "Random Wallpaper", action: #selector(onRandomWallpaper))

        scrollView.hasVerticalScroller = true; scrollView.drawsBackground = false; scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = kRadius / 2; scrollView.layer?.backgroundColor = kSurface.cgColor
        scrollView.layer?.borderWidth = kBorderWidth; scrollView.layer?.borderColor = kBorder.cgColor

        contentView.wantsLayer = true; contentView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.documentView = contentView
        addSubview(scrollView)
    }

    private func setupBtn(_ btn: NSButton, title: String, action: Selector) {
        btn.title = title; btn.font = dynamicFont(size: 10, weight: .bold); btn.isBordered = false; btn.wantsLayer = true; btn.tag = 100
        btn.layer?.cornerRadius = kRadius / 2; btn.layer?.backgroundColor = kAccent.cgColor
        btn.layer?.borderWidth = kBorderWidth; btn.layer?.borderColor = kBorder.cgColor
        btn.contentTintColor = (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish) ? .white : kSurface
        btn.target = self; btn.action = action; addSubview(btn)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleLabel.frame = NSRect(x: 12, y: h - 28, width: 180, height: 18)
        pathLabel.frame = NSRect(x: 200, y: h - 28, width: w - 212, height: 18)

        let btnW: CGFloat = 125, btnH: CGFloat = 24
        chooseFolderBtn.frame = NSRect(x: 12, y: h - 58, width: btnW, height: btnH)
        randomBtn.frame = NSRect(x: 12 + btnW + 8, y: h - 58, width: 135, height: btnH)
        scrollView.frame = NSRect(x: 12, y: 12, width: w - 24, height: h - 78)

        if bounds.size != lastRenderedBoundsSize || imageURLs.count != lastRenderedURLsCount {
            lastRenderedBoundsSize = bounds.size
            lastRenderedURLsCount = imageURLs.count
            renderGrid()
        }
    }

    private func loadWallpapers() {
        if let screen = NSScreen.main {
            activeWallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen)
        }
        let exts = Set(["jpg", "jpeg", "png", "heic", "webp", "avif"])
        if let files = try? FileManager.default.contentsOfDirectory(at: wallpaperFolderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            imageURLs = files.filter { exts.contains($0.pathExtension.lowercased()) }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        } else {
            imageURLs = []
        }
        pathLabel.stringValue = "\(wallpaperFolderURL.lastPathComponent) (\(imageURLs.count) wallpapers)"
        renderGrid()
    }

    private func renderGrid() {
        for sub in contentView.subviews { sub.removeFromSuperview() }
        let gridW = scrollView.bounds.width > 0 ? scrollView.bounds.width - 16 : 640.0
        let itemW: CGFloat = 150, itemH: CGFloat = 95, gap: CGFloat = 10
        let cols = max(1, Int((gridW + gap) / (itemW + gap)))
        let rows = Int(ceil(Double(imageURLs.count) / Double(cols)))
        let contentH = max(scrollView.bounds.height, CGFloat(rows) * (itemH + gap) + gap)
        contentView.frame = NSRect(x: 0, y: 0, width: gridW, height: contentH)

        for (idx, url) in imageURLs.enumerated() {
            let r = idx / cols, c = idx % cols
            let x = gap + CGFloat(c) * (itemW + gap)
            let y = contentH - CGFloat(r + 1) * (itemH + gap)

            let card = NSButton(frame: NSRect(x: x, y: y, width: itemW, height: itemH))
            card.title = ""; card.isBordered = false; card.wantsLayer = true; card.layer?.cornerRadius = kRadius / 2
            card.layer?.masksToBounds = true; card.layer?.backgroundColor = kSurface.cgColor

            let isCurrent = (url.path == activeWallpaperURL?.path)
            card.layer?.borderWidth = isCurrent ? 3.0 : kBorderWidth
            card.layer?.borderColor = isCurrent ? kAccent.cgColor : kBorder.cgColor

            let iv = NSImageView(frame: NSRect(x: 0, y: 0, width: itemW, height: itemH))
            iv.imageScaling = .scaleAxesIndependently
            card.addSubview(iv)

            let nsURL = url as NSURL
            if let cached = thumbnailCache.object(forKey: nsURL) {
                iv.image = cached
            } else {
                DispatchQueue.global(qos: .userInitiated).async { [weak self, weak iv] in
                    if let img = NSImage.downsampledImage(at: url, targetSize: NSSize(width: itemW * 1.5, height: itemH * 1.5)) {
                        self?.thumbnailCache.setObject(img, forKey: nsURL)
                        DispatchQueue.main.async { iv?.image = img }
                    }
                }
            }

            if isCurrent {
                let activeBadge = NSTextField(frame: NSRect(x: 6, y: itemH - 20, width: 54, height: 14))
                activeBadge.stringValue = "ACTIVE"; activeBadge.font = dynamicFont(size: 8, weight: .bold)
                activeBadge.textColor = .white; activeBadge.alignment = .center; activeBadge.tag = 100
                activeBadge.isEditable = false; activeBadge.isBordered = false; activeBadge.wantsLayer = true
                activeBadge.layer?.cornerRadius = 3; activeBadge.layer?.backgroundColor = kAccent.cgColor
                card.addSubview(activeBadge)
            }

            card.tag = idx; card.target = self; card.action = #selector(onWallpaperSelected(_:))
            contentView.addSubview(card)
        }
    }

    @objc private func onWallpaperSelected(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < imageURLs.count else { return }
        let url = imageURLs[sender.tag]
        activeWallpaperURL = url
        let win = self.window
        CenterWallpaperTransitionManager.shared.animateAndSetWallpaper(url: url) { [weak self] in
            win?.orderOut(nil)
            DispatchQueue.main.async { self?.renderGrid() }
        }
    }

    @objc private func onChooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Select Wallpaper Folder"; panel.directoryURL = wallpaperFolderURL
        panel.begin { [weak self] result in
            if result == .OK, let selectedURL = panel.url {
                self?.wallpaperFolderURL = selectedURL
                UserDefaults.standard.set(selectedURL.path, forKey: "customER_wallpaper_folder")
                self?.loadWallpapers()
                self?.startWatchingFolder()
            }
        }
    }

    @objc private func onRandomWallpaper() {
        guard !imageURLs.isEmpty else { return }
        let targetURL = imageURLs[Int.random(in: 0..<imageURLs.count)]
        activeWallpaperURL = targetURL
        let win = self.window
        CenterWallpaperTransitionManager.shared.animateAndSetWallpaper(url: targetURL) { [weak self] in
            win?.orderOut(nil)
            DispatchQueue.main.async { self?.renderGrid() }
        }
    }

    override func applyTheme(preset: ThemePreset) {
        scrollView.layer?.cornerRadius = preset.cornerRadius / 2
        scrollView.layer?.backgroundColor = preset.surfaceColor.cgColor
        scrollView.layer?.borderColor = preset.borderColor.cgColor
        scrollView.layer?.borderWidth = preset.borderWidth
        for btn in [chooseFolderBtn, randomBtn] {
            btn.layer?.cornerRadius = preset.cornerRadius / 2
            btn.layer?.backgroundColor = kAccent.cgColor
            btn.layer?.borderColor = preset.borderColor.cgColor
            btn.layer?.borderWidth = preset.borderWidth
            btn.contentTintColor = (preset == .glass || preset == .childish) ? .white : kSurface
        }
        updateThemeRecursively(preset: preset)
        renderGrid()
    }
}
