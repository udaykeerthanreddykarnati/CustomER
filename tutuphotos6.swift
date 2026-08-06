import AppKit
import Foundation

// MARK: - Colors
let kDim = NSColor(red: 0.35, green: 0.35, blue: 0.25, alpha: 1.00)

extension NSImage {
    func cropToSquare() -> NSImage {
        guard size.width > 0 && size.height > 0 else { return self }
        let squareSide = min(size.width, size.height)
        let xOffset = (size.width - squareSide) / 2.0
        let yOffset = (size.height - squareSide) / 2.0
        let cropRect = NSRect(x: xOffset, y: yOffset, width: squareSide, height: squareSide)

        let cropped = NSImage(size: NSSize(width: squareSide, height: squareSide))
        cropped.lockFocus()
        self.draw(in: NSRect(x: 0, y: 0, width: squareSide, height: squareSide),
                  from: cropRect,
                  operation: .copy,
                  fraction: 1.0)
        cropped.unlockFocus()
        return cropped
    }
}

class PhotosWindow6: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

class PhotosView6: NSView {
    private let imageView = NSImageView()
    private let placeholderLabel = NSTextField()

    private var dragStart: NSPoint = .zero
    private var dragActive = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        loadPhoto()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0

        // Image View Container
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 0
        imageView.layer?.borderWidth = 0
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)

        // Placeholder notice if empty
        placeholderLabel.stringValue = "📁 Place 1 photo in:\n~/Pictures/CustomERPhotos6"
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

    private func loadPhoto() {
        let photosDir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CustomERPhotos6")

        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

        let ext = ["jpg", "jpeg", "png", "heic", "webp"]
        if let files = try? FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil),
           let firstPhoto = files.filter({ ext.contains($0.pathExtension.lowercased()) }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first,
           let img = NSImage(contentsOf: firstPhoto) {
            imageView.image = img.cropToSquare()
            imageView.isHidden = false
            placeholderLabel.isHidden = true
        } else {
            imageView.isHidden = true
            placeholderLabel.isHidden = false
        }
    }

    // Dragging
    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        dragActive = true
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { super.mouseDragged(with: event); return }
        let c = event.locationInWindow
        w.setFrameOrigin(NSPoint(x: w.frame.origin.x + c.x - dragStart.x,
                                  y: w.frame.origin.y + c.y - dragStart.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragActive = false
        super.mouseUp(with: event)
    }
}

class AppDelegate6: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 535, y: 366, width: 196, height: 196)
        window = PhotosWindow6(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: -1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hasShadow = false
        window.contentView = PhotosView6(frame: rect)
        window.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate6()
app.delegate = delegate
app.run()
