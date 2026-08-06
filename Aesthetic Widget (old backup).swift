// Native macOS Swift Aesthetic Widget Code Backup
// Preserved by Antigravity

import AppKit
import Foundation

class DraggableContainerView: NSVisualEffectView {
    var initialLocation: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        initialLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        let currentLocation = event.locationInWindow
        let newOrigin = NSPoint(
            x: window.frame.origin.x + (currentLocation.x - initialLocation.x),
            y: window.frame.origin.y + (currentLocation.y - initialLocation.y)
        )
        window.setFrameOrigin(newOrigin)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var imageView: NSImageView!
    var clockLabel: NSTextField!
    var dateLabel: NSTextField!
    var timer: Timer?
    var images: [URL] = []
    var currentIndex: Int = 0
    var statusItem: NSStatusItem!
    let widgetDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/AestheticWidget1")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 80, y: 520, width: 440, height: 248)
        window = NSWindow(contentRect: rect,
                          styleMask: [.borderless, .resizable],
                          backing: .buffered,
                          defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        
        // Sub-normal level -1 (Covered by app windows, directly draggable on desktop)
        window.level = NSWindow.Level(rawValue: -1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = true
        window.aspectRatio = NSSize(width: 16, height: 9)

        let containerView = DraggableContainerView(frame: window.contentView!.bounds)
        containerView.autoresizingMask = [.width, .height]
        containerView.material = .hudWindow
        containerView.blendingMode = .withinWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 24
        containerView.layer?.masksToBounds = true
        window.contentView?.addSubview(containerView)

        imageView = NSImageView(frame: containerView.bounds)
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 24
        imageView.layer?.masksToBounds = true
        containerView.addSubview(imageView)

        clockLabel = NSTextField(labelWithString: "00:00")
        clockLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 30, weight: .bold)
        clockLabel.textColor = .white
        clockLabel.frame = NSRect(x: 22, y: 38, width: 280, height: 38)
        clockLabel.autoresizingMask = [.maxXMargin, .minYMargin]
        
        let textShadow = NSShadow()
        textShadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        textShadow.shadowOffset = NSSize(width: 0, height: -2)
        textShadow.shadowBlurRadius = 4
        clockLabel.shadow = textShadow
        containerView.addSubview(clockLabel)

        dateLabel = NSTextField(labelWithString: "Loading...")
        dateLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        dateLabel.textColor = NSColor.white.withAlphaComponent(0.9)
        dateLabel.frame = NSRect(x: 22, y: 15, width: 280, height: 22)
        dateLabel.autoresizingMask = [.maxXMargin, .minYMargin]
        dateLabel.shadow = textShadow
        containerView.addSubview(dateLabel)

        setupStatusItem()
        loadImages()
        updateClock()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateClock()
        }

        window.orderFront(nil)
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.title = "🖼️"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "📸 Next Photo", action: #selector(nextImage), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "📁 Open Photos Folder...", action: #selector(openFolder), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "🔄 Reload Images", action: #selector(loadImages), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "❌ Quit Widget", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc func loadImages() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: widgetDir, includingPropertiesForKeys: nil)
            images = files.filter { ["jpg", "jpeg", "png", "webp"].contains($0.pathExtension.lowercased()) }
        } catch {
            images = []
        }
        if !images.isEmpty {
            currentIndex = 0
            displayImage()
        }
    }

    @objc func nextImage() {
        guard !images.isEmpty else { return }
        currentIndex = (currentIndex + 1) % images.count
        displayImage()
    }

    func displayImage() {
        guard currentIndex < images.count else { return }
        let url = images[currentIndex]
        if let img = NSImage(contentsOf: url) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                self.imageView.animator().image = img
            }
        }
    }

    @objc func updateClock() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        clockLabel.stringValue = formatter.string(from: Date())

        formatter.dateFormat = "EEEE, MMMM d"
        dateLabel.stringValue = formatter.string(from: Date())
    }

    @objc func openFolder() {
        NSWorkspace.shared.open(widgetDir)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
