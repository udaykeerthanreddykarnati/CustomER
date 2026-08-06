import AppKit
import Foundation

let kDim = NSColor(red: 0.35, green: 0.35, blue: 0.25, alpha: 1.00)

class GifWindow: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

class GifView: NSView {
    private let imageView = NSImageView()
    private let placeholderLabel = NSTextField()

    private var dragStart: NSPoint = .zero
    private var dragActive = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        loadGif()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0

        imageView.wantsLayer = true
        imageView.layer?.isOpaque = false
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        imageView.layer?.borderWidth = 0
        imageView.animates = true
        imageView.canDrawSubviewsIntoLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)

        placeholderLabel.stringValue = "📁 Place GIF in:\n~/Pictures/CustomERGifs"
        placeholderLabel.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        placeholderLabel.textColor = kDim
        placeholderLabel.alignment = .center
        placeholderLabel.isEditable = false; placeholderLabel.isBordered = false; placeholderLabel.backgroundColor = .clear
        addSubview(placeholderLabel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        imageView.frame = NSRect(x: 0, y: 0, width: w, height: h)
        placeholderLabel.frame = NSRect(x: 10, y: (h - 44)/2, width: w - 20, height: 44)
    }

    private func loadGif() {
        let gifDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CustomERGifs")

        try? FileManager.default.createDirectory(at: gifDir, withIntermediateDirectories: true)

        let ext = ["gif"]
        if let files = try? FileManager.default.contentsOfDirectory(at: gifDir, includingPropertiesForKeys: nil),
           let firstGif = files.filter({ ext.contains($0.pathExtension.lowercased()) }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first,
           let img = NSImage(contentsOf: firstGif) {
            imageView.image = img
            imageView.animates = true
            imageView.isHidden = false
            placeholderLabel.isHidden = true
        } else {
            imageView.isHidden = true
            placeholderLabel.isHidden = false
        }
    }

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
        let rect = NSRect(x: 1000, y: 350, width: 196, height: 196)
        window = GifWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: -1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false
        window.contentView = GifView(frame: rect)
        window.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
