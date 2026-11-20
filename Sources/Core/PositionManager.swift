import AppKit
import Foundation

// MARK: - Widget Position Persistence & Multi-Monitor Clamping
final class PositionManager {
    static let shared = PositionManager()
    private let url = AppPaths.file("positions.json")
    private var posDict: [String: [CGFloat]] = [:]

    private init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: [CGFloat]].self, from: data) else { return }
        posDict = dict
    }

    func savePosition(key: String, origin: NSPoint) {
        posDict[key] = [origin.x, origin.y]
        if let data = try? JSONEncoder().encode(posDict) {
            AppPaths.writeAtomically(data, to: url)
        }
    }

    func getPosition(key: String, defaultOrigin: NSPoint, size: NSSize = NSSize(width: 280, height: 120)) -> NSPoint {
        let rawOrigin: NSPoint
        if let arr = posDict[key], arr.count == 2 {
            rawOrigin = NSPoint(x: arr[0], y: arr[1])
        } else {
            rawOrigin = defaultOrigin
        }
        return clampToScreens(origin: rawOrigin, size: size)
    }

    /// Ensures a widget window is never stranded off-screen when displays change or disconnect.
    func clampToScreens(origin: NSPoint, size: NSSize) -> NSPoint {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return origin }

        let widgetRect = NSRect(origin: origin, size: size)
        // If at least 40x40 of the widget intersects any connected screen, keep its saved origin.
        for screen in screens {
            let inter = screen.visibleFrame.intersection(widgetRect)
            if !inter.isNull && inter.width >= 40 && inter.height >= 40 {
                return origin
            }
        }

        // Otherwise clamp onto the main screen's visible frame.
        let target = (NSScreen.main ?? screens[0]).visibleFrame
        let clampedX = max(target.minX + 8, min(origin.x, target.maxX - size.width - 8))
        let clampedY = max(target.minY + 8, min(origin.y, target.maxY - size.height - 8))
        return NSPoint(x: clampedX, y: clampedY)
    }
}
