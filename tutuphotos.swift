import AppKit
import Foundation

// MARK: - Colors
let kDim = NSColor(red: 0.35, green: 0.35, blue: 0.25, alpha: 1.00)

extension NSImage {
    static func downsampledImage(at url: URL, targetSize: NSSize) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let maxDimension = max(targetSize.width, targetSize.height) * 2.0 // 2x Retina
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: targetSize)
    }
}

struct PhotoSlot {
    let id: Int
    let folderName: String
    let rect: NSRect
}

class PhotosWindow: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

class PhotosView: NSView {
    private let imageView = NSImageView()
    private let placeholderLabel = NSTextField()
    private let folderName: String

    private var dragStart: NSPoint = .zero
    private var dragActive = false

    init(frame: NSRect, folderName: String) {
        self.folderName = folderName
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

        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 0
        imageView.layer?.borderWidth = 0
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)

        placeholderLabel.stringValue = "📁 Place 1 photo in:\n~/Pictures/\(folderName)"
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
            .appendingPathComponent(folderName)

        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

        let ext = ["jpg", "jpeg", "png", "heic", "webp"]
        if let files = try? FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil),
           let firstPhoto = files.filter({ ext.contains($0.pathExtension.lowercased()) }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first,
           let img = NSImage.downsampledImage(at: firstPhoto, targetSize: NSSize(width: 196, height: 196)) {
            imageView.image = img
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
    var windows: [NSWindow] = []

    let slots: [PhotoSlot] = [
        // Row 1 (Top, y = 578)
        PhotoSlot(id: 1,  folderName: "CustomERPhotos",   rect: NSRect(x: 421,  y: 578, width: 196, height: 196)),
        PhotoSlot(id: 2,  folderName: "CustomERPhotos2",  rect: NSRect(x: 633,  y: 578, width: 196, height: 196)),
        PhotoSlot(id: 3,  folderName: "CustomERPhotos3",  rect: NSRect(x: 845,  y: 578, width: 196, height: 196)),
        PhotoSlot(id: 4,  folderName: "CustomERPhotos4",  rect: NSRect(x: 1057, y: 578, width: 196, height: 196)),

        // Row 2 (Middle, y = 366)
        PhotoSlot(id: 5,  folderName: "CustomERPhotos5",  rect: NSRect(x: 323,  y: 366, width: 196, height: 196)),
        PhotoSlot(id: 6,  folderName: "CustomERPhotos6",  rect: NSRect(x: 535,  y: 366, width: 196, height: 196)),
        PhotoSlot(id: 7,  folderName: "CustomERPhotos7",  rect: NSRect(x: 747,  y: 366, width: 196, height: 196)),
        PhotoSlot(id: 8,  folderName: "CustomERPhotos8",  rect: NSRect(x: 959,  y: 366, width: 196, height: 196)),
        PhotoSlot(id: 13, folderName: "CustomERPhotos13", rect: NSRect(x: 1171, y: 366, width: 196, height: 196)),

        // Row 3 (Bottom, y = 154)
        PhotoSlot(id: 9,  folderName: "CustomERPhotos9",  rect: NSRect(x: 421,  y: 154, width: 196, height: 196)),
        PhotoSlot(id: 10, folderName: "CustomERPhotos10", rect: NSRect(x: 633,  y: 154, width: 196, height: 196)),
        PhotoSlot(id: 11, folderName: "CustomERPhotos11", rect: NSRect(x: 845,  y: 154, width: 196, height: 196)),
        PhotoSlot(id: 12, folderName: "CustomERPhotos12", rect: NSRect(x: 1057, y: 154, width: 196, height: 196))
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        for slot in slots {
            let window = PhotosWindow(contentRect: slot.rect, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear
            window.level = NSWindow.Level(rawValue: -1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.hasShadow = false
            window.contentView = PhotosView(frame: slot.rect, folderName: slot.folderName)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
