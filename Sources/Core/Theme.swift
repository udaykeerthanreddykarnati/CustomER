import AppKit
import Foundation

// MARK: - Global Theme Presets (Dynamic Colors, Fonts & Shapes)
enum ThemePreset: String, CaseIterable {
    case minimal
    case glass
    case childish

    var name: String { rawValue.uppercased() }

    var bgColor: NSColor {
        switch self {
        case .minimal:  return NSColor(hex: "#FEF9C3")! // Pastel Butter
        case .glass:    return NSColor(hex: "#090D16")! // Deep Midnight
        case .childish: return NSColor(hex: "#FFE3F1")! // Cotton Candy Pink
        }
    }

    var surfaceColor: NSColor {
        switch self {
        case .minimal:  return NSColor(hex: "#FEFCE8")! // Soft Cream
        case .glass:    return NSColor(hex: "#151D2A")! // Frosted Dark Glass Card Surface
        case .childish: return NSColor(hex: "#FFF6FA")! // Marshmallow Cream
        }
    }

    var textColor: NSColor {
        switch self {
        case .minimal:  return NSColor(hex: "#800020")! // Rich Burgundy
        case .glass:    return NSColor(hex: "#F1F5F9")! // Crystal White
        case .childish: return NSColor(hex: "#FF4FA0")! // Bubblegum Pink
        }
    }

    var accentColor: NSColor {
        switch self {
        case .minimal:  return NSColor(hex: "#800020")! // Rich Burgundy
        case .glass:    return NSColor(hex: "#6366F1")! // Electric Indigo
        case .childish: return NSColor(hex: "#FF4FA0")! // Bubblegum Pink
        }
    }

    var addBgColor: NSColor {
        switch self {
        case .minimal:  return NSColor(hex: "#800020")! // Rich Burgundy
        case .glass:    return NSColor(hex: "#10B981")! // Emerald Green
        case .childish: return NSColor(hex: "#FF4FA0")! // Bubblegum Pink
        }
    }

    var borderColor: NSColor {
        switch self {
        case .minimal:  return NSColor.black
        case .glass:    return NSColor(hex: "#263346")! // Slate Glass Border
        case .childish: return NSColor.black
        }
    }

    var borderWidth: CGFloat {
        switch self {
        case .minimal:  return 1.0
        case .glass:    return 1.0
        case .childish: return 2.0
        }
    }

    var dimColor: NSColor {
        switch self {
        case .minimal:  return NSColor(hex: "#595940")! // Muted Olive
        case .glass:    return NSColor(hex: "#64748B")! // Steel Slate
        case .childish: return NSColor(hex: "#8C6B9E")! // Dusty Lavender
        }
    }

    var cornerRadius: CGFloat { 0.0 }

    var fontDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .minimal:  return .default
        case .glass:    return .monospaced
        case .childish: return .rounded
        }
    }

    func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(fontDesign) {
            return NSFont(descriptor: descriptor, size: size) ?? base
        }
        return base
    }
}

var kBg: NSColor          { ThemeManager.shared.currentBgColor }
var kSurface: NSColor     { ThemeManager.shared.currentPreset.surfaceColor }
var kText: NSColor        { ThemeManager.shared.currentTextColor }
var kBlue: NSColor        { ThemeManager.shared.currentAccentColor }
var kAccent: NSColor      { ThemeManager.shared.currentAccentColor }
var kAddBg: NSColor       { ThemeManager.shared.currentPreset.addBgColor }
var kDim: NSColor         { ThemeManager.shared.currentPreset.dimColor }
var kBorder: NSColor      { ThemeManager.shared.currentPreset.borderColor }
var kRadius: CGFloat      { ThemeManager.shared.currentPreset.cornerRadius }
var kBorderWidth: CGFloat { ThemeManager.shared.currentPreset.borderWidth }

func dynamicFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    if let customName = ThemeManager.shared.customFontName,
       !customName.isEmpty,
       !customName.hasPrefix("."),
       !customName.contains("System Font") {
        let isBold = (weight == .bold || weight == .heavy || weight == .black || weight == .semibold)
        let fontTraits: NSFontTraitMask = isBold ? .boldFontMask : []

        if let font = NSFont(name: customName, size: size) {
            return isBold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
        }
        if let font = NSFontManager.shared.font(withFamily: customName, traits: fontTraits, weight: isBold ? 9 : 5, size: size) {
            return font
        }
        if let members = NSFontManager.shared.availableMembers(ofFontFamily: customName),
           let firstMember = members.first,
           let psName = firstMember[0] as? String,
           let font = NSFont(name: psName, size: size) {
            return isBold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
        }
    }
    return ThemeManager.shared.currentPreset.font(size: size, weight: weight)
}

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

    func toHex() -> String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FEF9C3" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension NSView {
    func updateThemeRecursively(preset: ThemePreset) {
        let activeText = ThemeManager.shared.currentTextColor
        if let tf = self as? NSTextField {
            if tf.tag == 99 {
                tf.textColor = ThemeManager.shared.currentPreset.dimColor
            } else if tf.tag == 100 {
                // Keep custom badge/card text color intact
            } else if tf.backgroundColor == .clear || tf.backgroundColor == nil {
                tf.textColor = activeText
            }
            if let currentFont = tf.font {
                let name = currentFont.fontName.lowercased()
                let isBold = currentFont.fontDescriptor.symbolicTraits.contains(.bold) || name.contains("bold") || name.contains("heavy") || name.contains("black")
                let weight: NSFont.Weight = isBold ? .bold : .regular
                tf.font = dynamicFont(size: currentFont.pointSize, weight: weight)
            }
            tf.cell?.usesSingleLineMode = true
            tf.cell?.lineBreakMode = .byTruncatingTail
        } else if let btn = self as? NSButton {
            if btn.tag != 100 {
                btn.contentTintColor = activeText
            }
            if let currentFont = btn.font {
                let name = currentFont.fontName.lowercased()
                let isBold = currentFont.fontDescriptor.symbolicTraits.contains(.bold) || name.contains("bold")
                btn.font = dynamicFont(size: currentFont.pointSize, weight: isBold ? .bold : .medium)
            }
        }
        for sub in subviews {
            sub.updateThemeRecursively(preset: preset)
        }
    }
}

extension NSImage {
    static func downsampledImage(at url: URL, targetSize: NSSize) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let maxDimension = max(targetSize.width, targetSize.height) * 2.0
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

class CenteredTextFieldCell: NSTextFieldCell {
    var opticalCapCenter: Bool = true

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let raw = attributedStringValue
        guard raw.length > 0 else { return }

        let font = (raw.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            ?? self.font
            ?? NSFont.systemFont(ofSize: 12)
        let color = (raw.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
            ?? self.textColor
            ?? .labelColor

        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = lineBreakMode

        let styled = NSMutableAttributedString(attributedString: raw)
        let fullRange = NSRange(location: 0, length: styled.length)
        styled.addAttribute(.paragraphStyle, value: para, range: fullRange)
        styled.addAttribute(.foregroundColor, value: color, range: fullRange)
        styled.addAttribute(.font, value: font, range: fullRange)

        let textSize = styled.size()
        let y: CGFloat
        if opticalCapCenter {
            // Position uppercase/digit visual cap-height center directly on cellFrame.midY
            let visualMidFromTop = (font.ascender - font.capHeight) + (font.capHeight / 2.0)
            y = cellFrame.minY + (cellFrame.height / 2.0) - visualMidFromTop
        } else {
            y = cellFrame.minY + (cellFrame.height - textSize.height) / 2.0
        }

        let drawRect = NSRect(
            x: cellFrame.minX,
            y: round(y * 2.0) / 2.0,
            width: cellFrame.width,
            height: ceil(textSize.height) + 2.0
        )
        styled.draw(with: drawRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

class MasterWidgetWindow: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Color & Font Panel Delegates
class ColorPanelDelegate: NSObject {
    static let shared = ColorPanelDelegate()
    enum TargetColor { case text, bg, accent }
    private var currentTarget: TargetColor = .text

    func openColorWheel(for target: TargetColor, initialColor: NSColor) {
        currentTarget = target
        let panel = NSColorPanel.shared
        panel.color = initialColor
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.isContinuous = false
        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        let selectedColor = sender.color
        switch currentTarget {
        case .text:   ThemeManager.shared.customTextColor = selectedColor
        case .bg:     ThemeManager.shared.customBgColor = selectedColor
        case .accent: ThemeManager.shared.customAccentColor = selectedColor
        }
    }
}

class FontPanelDelegate: NSObject {
    static let shared = FontPanelDelegate()

    func openFontPicker() {
        let fontManager = NSFontManager.shared
        fontManager.target = self
        fontManager.action = #selector(changeFont(_:))
        let panel = fontManager.fontPanel(true)
        panel?.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func changeFont(_ sender: Any?) {
        guard let fontManager = sender as? NSFontManager else { return }
        let currentFont = dynamicFont(size: 12, weight: .regular)
        let selectedFont = fontManager.convert(currentFont)
        let fontName = selectedFont.fontName
        let familyName = selectedFont.familyName ?? fontName

        if !fontName.hasPrefix(".") && fontName != "System Font" && !familyName.hasPrefix(".") {
            ThemeManager.shared.customFontName = fontName
        }
    }
}

// MARK: - ThemeManager
final class ThemeManager {
    static let shared = ThemeManager()
    static let notifName = NSNotification.Name("com.user.CustomER.themeChanged")

    private var _customTextColorHex: String?
    private var _customBgColorHex: String?
    private var _customAccentColorHex: String?
    private var _customFontName: String?

    var currentPreset: ThemePreset = .minimal {
        didSet {
            UserDefaults.standard.set(currentPreset.rawValue, forKey: "current_theme_preset")
            notifyThemeChange()
        }
    }

    func cyclePreset() {
        let all = ThemePreset.allCases
        if let idx = all.firstIndex(of: currentPreset) {
            currentPreset = all[(idx + 1) % all.count]
        }
    }

    var customTextColor: NSColor? {
        get { _customTextColorHex.flatMap { NSColor(hex: $0) } }
        set {
            _customTextColorHex = newValue?.toHex()
            UserDefaults.standard.set(_customTextColorHex, forKey: "custom_text_color_hex")
            notifyThemeChange()
        }
    }

    var customBgColor: NSColor? {
        get { _customBgColorHex.flatMap { NSColor(hex: $0) } }
        set {
            _customBgColorHex = newValue?.toHex()
            UserDefaults.standard.set(_customBgColorHex, forKey: "custom_bg_color_hex")
            notifyThemeChange()
        }
    }

    var customAccentColor: NSColor? {
        get { _customAccentColorHex.flatMap { NSColor(hex: $0) } }
        set {
            _customAccentColorHex = newValue?.toHex()
            UserDefaults.standard.set(_customAccentColorHex, forKey: "custom_accent_color_hex")
            notifyThemeChange()
        }
    }

    var customFontName: String? {
        get { _customFontName }
        set {
            _customFontName = newValue
            UserDefaults.standard.set(_customFontName, forKey: "custom_font_name")
            notifyThemeChange()
        }
    }

    var currentTextColor: NSColor   { customTextColor ?? currentPreset.textColor }
    var currentBgColor: NSColor     { customBgColor ?? currentPreset.bgColor }
    var currentAccentColor: NSColor { customAccentColor ?? currentPreset.accentColor }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: "current_theme_preset"), let p = ThemePreset(rawValue: raw) {
            currentPreset = p
        }
        _customTextColorHex = UserDefaults.standard.string(forKey: "custom_text_color_hex")
        _customBgColorHex = UserDefaults.standard.string(forKey: "custom_bg_color_hex")
        _customAccentColorHex = UserDefaults.standard.string(forKey: "custom_accent_color_hex")
        _customFontName = UserDefaults.standard.string(forKey: "custom_font_name")
    }

    private var notifyDebounceWorkItem: DispatchWorkItem?
    private var folderIconDebounceWorkItem: DispatchWorkItem?

    func notifyThemeChange() {
        notifyDebounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard self != nil else { return }
            NotificationCenter.default.post(name: ThemeManager.notifName, object: nil)
            DistributedNotificationCenter.default().postNotificationName(ThemeManager.notifName, object: nil, userInfo: nil, deliverImmediately: true)
        }
        notifyDebounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)

        folderIconDebounceWorkItem?.cancel()
        let bg = currentBgColor
        let accent = currentAccentColor
        let iconItem = DispatchWorkItem {
            FolderIconManager.updateDesktopFolderIcons(bgColor: bg, accentColor: accent)
        }
        folderIconDebounceWorkItem = iconItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: iconItem)
    }

    func resetCustomStyles() {
        _customTextColorHex = nil
        _customBgColorHex = nil
        _customAccentColorHex = nil
        _customFontName = nil
        UserDefaults.standard.removeObject(forKey: "custom_text_color_hex")
        UserDefaults.standard.removeObject(forKey: "custom_bg_color_hex")
        UserDefaults.standard.removeObject(forKey: "custom_accent_color_hex")
        UserDefaults.standard.removeObject(forKey: "custom_font_name")
        notifyThemeChange()
    }
}

// MARK: - Desktop Folder Icon Tinter (Strictly Serialized on Main Thread + Zero-Overhead kqueue Watcher)
enum FolderIconManager {
    private static var generation: Int = 0
    private static var isApplying: Bool = false
    private static var pendingQueue: [URL] = []
    private static var activeBg: NSColor = ThemeManager.shared.currentBgColor
    private static var activeAccent: NSColor = ThemeManager.shared.currentAccentColor
    private static var knownFolderNames: Set<String> = []
    private static var desktopWatchFD: Int32 = -1
    private static var desktopWatchSource: DispatchSourceFileSystemObject?
    private static var desktopWatchDebounce: DispatchWorkItem?

    private static func listDesktopFolders() -> [URL] {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: desktop,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                && isDir.boolValue
                && url.pathExtension != "app"
        }
    }

    static func updateDesktopFolderIcons(bgColor: NSColor, accentColor: NSColor = ThemeManager.shared.currentAccentColor) {
        DispatchQueue.main.async {
            generation += 1
            let myGen = generation
            activeBg = bgColor
            activeAccent = accentColor

            let folders = listDesktopFolders()
            knownFolderNames = Set(folders.map { $0.lastPathComponent })
            pendingQueue = folders
            isApplying = false
            drainNext(myGen: myGen)
        }
    }

    static func startWatchingDesktop() {
        DispatchQueue.main.async {
            guard desktopWatchSource == nil else { return }
            if knownFolderNames.isEmpty {
                knownFolderNames = Set(listDesktopFolders().map { $0.lastPathComponent })
            }
            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            let fd = open(desktop.path, O_EVTONLY)
            guard fd >= 0 else { return }

            desktopWatchFD = fd
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            source.setEventHandler {
                scheduleDesktopDiffCheck()
            }
            source.setCancelHandler {
                if desktopWatchFD >= 0 {
                    close(desktopWatchFD)
                    desktopWatchFD = -1
                }
            }
            desktopWatchSource = source
            source.resume()
        }
    }

    private static func scheduleDesktopDiffCheck() {
        desktopWatchDebounce?.cancel()
        let work = DispatchWorkItem {
            handleDesktopChange()
        }
        desktopWatchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private static func handleDesktopChange() {
        let folders = listDesktopFolders()
        let currentNames = Set(folders.map { $0.lastPathComponent })
        let added = folders.filter { !knownFolderNames.contains($0.lastPathComponent) }
        knownFolderNames = currentNames
        guard !added.isEmpty else { return }

        if !isApplying {
            activeBg = ThemeManager.shared.currentBgColor
            activeAccent = ThemeManager.shared.currentAccentColor
        }
        let existingPaths = Set(pendingQueue.map(\.path))
        for url in added where !existingPaths.contains(url.path) {
            pendingQueue.append(url)
        }
        if !isApplying {
            drainNext(myGen: generation)
        }
    }

    // Apply one folder per run-loop hop on main thread inside autoreleasepool so
    // NSWorkspace.setIcon (Carbon Resource Manager) never races and temporary bitmaps free immediately.
    private static func drainNext(myGen: Int) {
        guard myGen == generation else { return }
        guard !pendingQueue.isEmpty else {
            isApplying = false
            return
        }
        isApplying = true
        let url = pendingQueue.removeFirst()
        autoreleasepool {
            if FileManager.default.fileExists(atPath: url.path) {
                let icon = generateFolderIcon(folderName: url.lastPathComponent, bgColor: activeBg, accentColor: activeAccent)
                NSWorkspace.shared.setIcon(icon, forFile: url.path, options: [])
            }
        }
        if pendingQueue.isEmpty {
            isApplying = false
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                drainNext(myGen: myGen)
            }
        }
    }

    private static func generateFolderIcon(folderName: String, bgColor: NSColor, accentColor: NSColor) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { _ in
            let tabPath = NSBezierPath(roundedRect: NSRect(x: 72, y: 310, width: 180, height: 90), xRadius: 18, yRadius: 18)
            bgColor.setFill(); tabPath.fill()
            NSColor.black.setStroke(); tabPath.lineWidth = 10; tabPath.stroke()

            let bodyPath = NSBezierPath(roundedRect: NSRect(x: 56, y: 96, width: 400, height: 260), xRadius: 28, yRadius: 28)
            bgColor.setFill(); bodyPath.fill()
            NSColor.black.setStroke(); bodyPath.lineWidth = 10; bodyPath.stroke()

            let bannerPath = NSBezierPath(roundedRect: NSRect(x: 56, y: 300, width: 400, height: 56), xRadius: 14, yRadius: 14)
            accentColor.setFill(); bannerPath.fill()
            NSColor.black.setStroke(); bannerPath.lineWidth = 8; bannerPath.stroke()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 42, weight: .black),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]
            folderName.draw(in: NSRect(x: 72, y: 180, width: 368, height: 60), withAttributes: attrs)
            return true
        }
    }
}
