import AppKit
import Foundation

// MARK: - 8. TRANSPARENT GIF WIDGET (Click to Play/Pause, Drag to Reposition)
class GifView: BaseWidgetView {
    private let imageView = NSImageView()
    private var localDragStart: NSPoint = .zero
    private var localWinOrigin: NSPoint = .zero
    private var dragMoved = false

    init(frame: NSRect) {
        super.init(frame: frame, widgetKey: "gif")
        allowWindowDrag = false
        build()
        loadGif()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        imageView.wantsLayer = true
        imageView.layer?.isOpaque = false
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        imageView.animates = false
        imageView.canDrawSubviewsIntoLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)
    }

    override func applyTheme(preset: ThemePreset) {
        // Keep GIF widget transparent regardless of theme changes
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    private func loadGif() {
        let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CustomERGifs")
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
           let firstGif = files.filter({ $0.pathExtension.lowercased() == "gif" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first,
           let img = NSImage(contentsOf: firstGif) {
            imageView.image = img
            imageView.animates = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        localDragStart = NSEvent.mouseLocation
        if let w = window { localWinOrigin = w.frame.origin }
        dragMoved = false
        window?.makeKey()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let w = window else { return }
        let c = NSEvent.mouseLocation
        let dx = c.x - localDragStart.x, dy = c.y - localDragStart.y
        if abs(dx) > 2 || abs(dy) > 2 {
            dragMoved = true
            w.setFrameOrigin(NSPoint(x: localWinOrigin.x + dx, y: localWinOrigin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !dragMoved {
            imageView.animates.toggle()
        } else if let w = window {
            PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin)
        }
    }
}
