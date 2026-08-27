import AppKit
import Foundation
import IOKit.pwr_mgt
import IOKit.ps
import Carbon
import IOBluetooth

// MARK: - Global Theme Presets (Dynamic Colors, Fonts & Shapes)
enum ThemePreset: String {
    case minimal
    case glass
    case childish

    var name: String { rawValue.uppercased() }

    var bgColor: NSColor {
        switch self {
        case .minimal:  return NSColor(hex: "#FEF9C3")! // Pastel Butter (Original Default)
        case .glass:    return NSColor(hex: "#090D16")! // Deep Cyber Midnight
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
        case .minimal:  return NSColor(hex: "#800020")! // Maroon / Rich Burgundy
        case .glass:    return NSColor(hex: "#F1F5F9")! // Crystal White
        case .childish: return NSColor(hex: "#FF4FA0")! // Bubblegum Pop Pink
        }
    }

    var accentColor: NSColor {
        switch self {
        case .minimal:  return NSColor(hex: "#800020")! // Rich Burgundy
        case .glass:    return NSColor(hex: "#6366F1")! // Electric Indigo
        case .childish: return NSColor(hex: "#FF4FA0")! // Bubblegum Pop Pink
        }
    }

    var addBgColor: NSColor {
        switch self {
        case .minimal:  return NSColor(hex: "#800020")! // Rich Burgundy
        case .glass:    return NSColor(hex: "#10B981")! // Emerald Cyber Green
        case .childish: return NSColor(hex: "#FF4FA0")! // Bubblegum Pop Pink
        }
    }

    var borderColor: NSColor {
        switch self {
        case .minimal:  return NSColor.black
        case .glass:    return NSColor(hex: "#263346")! // Slate Glass Border
        case .childish: return NSColor.black            // Thick Black Cartoon Border
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

    var cornerRadius: CGFloat {
        return 0.0
    }

    var fontDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .minimal:  return .default      // Minimal: Standard Clean Sans-Serif Font
        case .glass:    return .monospaced   // Glass: Modern Monospaced Tech Font
        case .childish: return .rounded      // Childish: Bubbly Playful Rounded Font
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
        
        // 1. Direct PostScript name lookup
        if let font = NSFont(name: customName, size: size) {
            if isBold {
                return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            return font
        }
        // 2. NSFontManager family lookup
        if let font = NSFontManager.shared.font(withFamily: customName, traits: fontTraits, weight: isBold ? 9 : 5, size: size) {
            return font
        }
        // 3. Fallback: match first available font face in family
        if let members = NSFontManager.shared.availableMembers(ofFontFamily: customName),
           let firstMember = members.first,
           let psName = firstMember[0] as? String,
           let font = NSFont(name: psName, size: size) {
            if isBold {
                return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            return font
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
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
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

// MARK: - COLOR PANEL DELEGATE (Color Wheel Support)
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
        case .text:
            ThemeManager.shared.customTextColor = selectedColor
        case .bg:
            ThemeManager.shared.customBgColor = selectedColor
        case .accent:
            ThemeManager.shared.customAccentColor = selectedColor
        }
    }
}

// MARK: - FONT PANEL DELEGATE (System Font Picker Support)
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

class ThemeManager {
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

    var customTextColor: NSColor? {
        get {
            guard let hex = _customTextColorHex else { return nil }
            return NSColor(hex: hex)
        }
        set {
            _customTextColorHex = newValue?.toHex()
            UserDefaults.standard.set(_customTextColorHex, forKey: "custom_text_color_hex")
            notifyThemeChange()
        }
    }

    var customBgColor: NSColor? {
        get {
            guard let hex = _customBgColorHex else { return nil }
            return NSColor(hex: hex)
        }
        set {
            _customBgColorHex = newValue?.toHex()
            UserDefaults.standard.set(_customBgColorHex, forKey: "custom_bg_color_hex")
            notifyThemeChange()
        }
    }

    var customAccentColor: NSColor? {
        get {
            guard let hex = _customAccentColorHex else { return nil }
            return NSColor(hex: hex)
        }
        set {
            _customAccentColorHex = newValue?.toHex()
            UserDefaults.standard.set(_customAccentColorHex, forKey: "custom_accent_color_hex")
            notifyThemeChange()
        }
    }

    var customFontName: String? {
        get { return _customFontName }
        set {
            _customFontName = newValue
            UserDefaults.standard.set(_customFontName, forKey: "custom_font_name")
            notifyThemeChange()
        }
    }

    var currentTextColor: NSColor {
        return customTextColor ?? currentPreset.textColor
    }

    var currentBgColor: NSColor {
        return customBgColor ?? currentPreset.bgColor
    }

    var currentAccentColor: NSColor {
        return customAccentColor ?? currentPreset.accentColor
    }

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

    func notifyThemeChange() {
        notifyDebounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            FolderIconManager.updateDesktopFolderIcons(bgColor: self.currentBgColor)
            NotificationCenter.default.post(name: ThemeManager.notifName, object: nil)
        }
        notifyDebounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
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

class FolderIconManager {
    static func updateDesktopFolderIcons(bgColor: NSColor) {
        DispatchQueue.global(qos: .userInitiated).async {
            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            guard let files = try? FileManager.default.contentsOfDirectory(at: desktop, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            
            let accent = ThemeManager.shared.currentPreset.accentColor
            
            for url in files {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue, url.pathExtension != "app" {
                    let icon = generateFolderIcon(folderName: url.lastPathComponent, bgColor: bgColor, accentColor: accent)
                    NSWorkspace.shared.setIcon(icon, forFile: url.path, options: [])
                }
            }
        }
    }

    private static func generateFolderIcon(folderName: String, bgColor: NSColor, accentColor: NSColor) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let img = NSImage(size: size)
        img.lockFocus()
        
        // Draw back tab
        let tabPath = NSBezierPath(roundedRect: NSRect(x: 72, y: 310, width: 180, height: 90), xRadius: 18, yRadius: 18)
        bgColor.setFill()
        tabPath.fill()
        NSColor.black.setStroke()
        tabPath.lineWidth = 10
        tabPath.stroke()
        
        // Draw front folder body
        let bodyPath = NSBezierPath(roundedRect: NSRect(x: 56, y: 96, width: 400, height: 260), xRadius: 28, yRadius: 28)
        bgColor.setFill()
        bodyPath.fill()
        NSColor.black.setStroke()
        bodyPath.lineWidth = 10
        bodyPath.stroke()
        
        // Draw top accent banner
        let bannerPath = NSBezierPath(roundedRect: NSRect(x: 56, y: 300, width: 400, height: 56), xRadius: 14, yRadius: 14)
        accentColor.setFill()
        bannerPath.fill()
        NSColor.black.setStroke()
        bannerPath.lineWidth = 8
        bannerPath.stroke()
        
        // Draw label text
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42, weight: .black),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        let textRect = NSRect(x: 72, y: 180, width: 368, height: 60)
        folderName.draw(in: textRect, withAttributes: attrs)
        
        img.unlockFocus()
        return img
    }
}

class PositionManager {
    static let shared = PositionManager()
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("tututodoWidget")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("positions.json")
    }()

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
            try? data.write(to: url)
        }
    }

    func getPosition(key: String, defaultOrigin: NSPoint) -> NSPoint {
        if let arr = posDict[key], arr.count == 2 {
            return NSPoint(x: arr[0], y: arr[1])
        }
        return defaultOrigin
    }
}

class CenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let newRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        let heightDelta = newRect.height - textSize.height
        if heightDelta > 0 {
            return NSRect(x: newRect.origin.x, y: newRect.origin.y + (heightDelta / 2.0), width: newRect.width, height: textSize.height)
        }
        return newRect
    }
}

class MasterWidgetWindow: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Helper AppleScript & Shell Runner
func runScript(_ code: String) -> String {
    let proc = Process()
    let pipe = Pipe()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    proc.arguments = ["-e", code]
    proc.standardOutput = pipe
    proc.standardError = Pipe()
    do {
        try proc.run()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.5) {
            if proc.isRunning { proc.terminate() }
        }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    } catch {
        return ""
    }
}

func shellRun(_ command: String) -> String {
    let proc = Process()
    let pipe = Pipe()
    proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
    proc.arguments = ["-c", "export PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"; \(command)"]
    proc.standardOutput = pipe
    proc.standardError = pipe
    do {
        try proc.run()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.5) {
            if proc.isRunning { proc.terminate() }
        }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    } catch {
        return ""
    }
}

// MARK: - 1. REMINDERS WIDGET (tututodo)
struct Reminder: Codable {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var isStarred: Bool
    var createdAt: Date

    init(title: String, isStarred: Bool = false) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
        self.isStarred = isStarred
        self.createdAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case id, title, isCompleted, isStarred, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        isStarred = try container.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

class ReminderStore {
    static let shared = ReminderStore()
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("tututodoWidget")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("reminders.json")
    }()
    private(set) var items: [Reminder] = []
    private init() { load() }
    func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Reminder].self, from: data) else { return }
        items = decoded
    }
    func save() { try? JSONEncoder().encode(items).write(to: url) }
    func add(_ r: Reminder) { items.append(r); save() }
    func toggle(id: UUID) { if let i = items.firstIndex(where: { $0.id == id }) { items[i].isCompleted.toggle(); save() } }
    func toggleStar(id: UUID) { if let i = items.firstIndex(where: { $0.id == id }) { items[i].isStarred.toggle(); save() } }
    func delete(id: UUID) { items.removeAll { $0.id == id }; save() }
    func clearCompleted() { items.removeAll { $0.isCompleted }; save() }
    func updateTitle(id: UUID, title: String) { if let i = items.firstIndex(where: { $0.id == id }) { items[i].title = title; save() } }
}

class ReminderRowView: NSView {
    var reminder: Reminder {
        didSet { updateUI() }
    }
    var onToggle:     ((UUID) -> Void)?
    var onStarToggle: ((UUID) -> Void)?
    var onDelete:     ((UUID) -> Void)?
    var onEdit:       ((UUID, String) -> Void)?

    private let check   = NSButton()
    private let label   = NSTextField()
    private let starBtn = NSButton()
    private let del     = NSButton()

    init(_ reminder: Reminder) {
        self.reminder = reminder
        super.init(frame: .zero); build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius / 2; layer?.backgroundColor = kSurface.cgColor
        layer?.borderWidth = 0.0

        check.isBordered = false; check.bezelStyle = .regularSquare; check.setButtonType(.momentaryChange)
        check.wantsLayer = true; check.layer?.cornerRadius = 4; check.layer?.borderWidth = kBorderWidth; check.layer?.borderColor = kBorder.cgColor
        check.target = self; check.action = #selector(toggleTapped); addSubview(check)

        label.isBordered = false; label.backgroundColor = .clear; label.isEditable = false
        label.lineBreakMode = .byTruncatingTail
        let dclick = NSClickGestureRecognizer(target: self, action: #selector(editTapped))
        dclick.numberOfClicksRequired = 2
        label.addGestureRecognizer(dclick)
        addSubview(label)

        starBtn.isBordered = false; starBtn.wantsLayer = true; starBtn.layer?.cornerRadius = 5
        starBtn.layer?.borderWidth = kBorderWidth; starBtn.layer?.borderColor = kBorder.cgColor
        starBtn.target = self; starBtn.action = #selector(starTapped)
        addSubview(starBtn)

        del.title = "✕"; del.font = dynamicFont(size: 10); del.isBordered = false
        del.contentTintColor = kDim; del.target = self; del.action = #selector(deleteTapped); del.alphaValue = 0
        addSubview(del)

        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)

        updateUI()
    }

    func updateUI() {
        check.layer?.backgroundColor = reminder.isCompleted ? kBorder.cgColor : NSColor.clear.cgColor
        if reminder.isCompleted {
            check.attributedTitle = NSAttributedString(string: "✓", attributes: [.font: dynamicFont(size: 10, weight: .bold), .foregroundColor: NSColor.white])
        } else { check.title = "" }

        if reminder.isCompleted {
            let s = NSMutableAttributedString(string: reminder.title)
            let r = NSRange(location: 0, length: reminder.title.count)
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            s.addAttribute(.foregroundColor, value: kDim, range: r)
            label.attributedStringValue = s
            layer?.borderWidth = 0.0
            layer?.borderColor = NSColor.clear.cgColor
            starBtn.layer?.backgroundColor = NSColor.clear.cgColor
            starBtn.layer?.borderColor = kBorder.withAlphaComponent(0.3).cgColor
            starBtn.attributedTitle = NSAttributedString(string: "★", attributes: [.font: dynamicFont(size: 12, weight: .bold), .foregroundColor: kDim.withAlphaComponent(0.4)])
            starBtn.alphaValue = 0.4
        } else if reminder.isStarred {
            let starAmber = NSColor(hex: "#F59E0B")!
            label.stringValue = reminder.title
            label.textColor = starAmber
            label.font = dynamicFont(size: 13, weight: .bold)
            layer?.borderWidth = kBorderWidth + 0.5
            layer?.borderColor = starAmber.withAlphaComponent(0.6).cgColor
            starBtn.layer?.backgroundColor = starAmber.cgColor
            starBtn.layer?.borderColor = NSColor(hex: "#D97706")!.cgColor
            starBtn.attributedTitle = NSAttributedString(string: "★", attributes: [.font: dynamicFont(size: 13, weight: .bold), .foregroundColor: NSColor.white])
            starBtn.alphaValue = 1.0
        } else {
            label.stringValue = reminder.title
            label.textColor = kText
            label.font = dynamicFont(size: 13, weight: .medium)
            layer?.borderWidth = 0.0
            layer?.borderColor = NSColor.clear.cgColor
            starBtn.layer?.backgroundColor = NSColor.clear.cgColor
            starBtn.layer?.borderColor = kBorder.cgColor
            starBtn.attributedTitle = NSAttributedString(string: "★", attributes: [.font: dynamicFont(size: 12, weight: .bold), .foregroundColor: kDim.withAlphaComponent(0.6)])
            starBtn.alphaValue = 0.6
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height, w = bounds.width
        check.frame   = NSRect(x: 10, y: (h-18)/2, width: 18, height: 18)
        starBtn.frame = NSRect(x: w - 52, y: (h-24)/2, width: 24, height: 24)
        del.frame     = NSRect(x: w - 24, y: (h-18)/2, width: 18, height: 18)
        label.frame   = NSRect(x: 34, y: (h-18)/2, width: w - 90, height: 18)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10; del.animator().alphaValue = 0.9
            if !reminder.isStarred && !reminder.isCompleted {
                starBtn.animator().alphaValue = 0.9
            }
            if !reminder.isStarred {
                layer?.borderWidth = kBorderWidth
                layer?.borderColor = kBorder.cgColor
            }
            layer?.backgroundColor = kSurface.withAlphaComponent(0.85).cgColor
        }
    }
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10; del.animator().alphaValue = 0
            if !reminder.isStarred && !reminder.isCompleted {
                starBtn.animator().alphaValue = 0.5
            }
            if !reminder.isStarred {
                layer?.borderWidth = 0.0
            }
            layer?.backgroundColor = kSurface.cgColor
        }
    }

    @objc func toggleTapped() { onToggle?(reminder.id) }
    @objc func starTapped()   { onStarToggle?(reminder.id) }
    @objc func deleteTapped()  { onDelete?(reminder.id) }
    @objc func editTapped() {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "Edit todo"
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        tf.stringValue = reminder.title
        alert.accessoryView = tf
        alert.beginSheetModal(for: window) { [weak self] r in
            guard let self = self else { return }
            if r == .alertFirstButtonReturn {
                let t = tf.stringValue.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { self.onEdit?(self.reminder.id, t) }
            }
        }
        DispatchQueue.main.async { tf.becomeFirstResponder() }
    }
}

class AddPanel: NSView {
    var onAdd:    ((Reminder) -> Void)?
    var onCancel: (() -> Void)?

    private let titleField = NSTextField()
    private let addBtn     = NSButton()
    private let cancelBtn  = NSButton()

    override init(frame: NSRect) { super.init(frame: frame); build() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.backgroundColor = kBg.cgColor
        layer?.borderWidth = kBorderWidth; layer?.borderColor = kBorder.cgColor

        titleField.drawsBackground = true; titleField.backgroundColor = kSurface; titleField.textColor = kText
        titleField.font = dynamicFont(size: 14, weight: .bold); titleField.focusRingType = .none
        titleField.isBordered = true; titleField.bezelStyle = .squareBezel; titleField.wantsLayer = true
        titleField.layer?.cornerRadius = kRadius / 2; titleField.layer?.borderWidth = kBorderWidth; titleField.layer?.borderColor = kBorder.cgColor

        let pAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: kDim, .font: dynamicFont(size: 13, weight: .medium)]
        titleField.placeholderAttributedString = NSAttributedString(string: "What to do?", attributes: pAttrs)
        addSubview(titleField)

        styleBtn(addBtn, primary: true, title: "Add")
        addBtn.target = self; addBtn.action = #selector(addTapped); addSubview(addBtn)

        styleBtn(cancelBtn, primary: false, title: "Cancel")
        cancelBtn.target = self; cancelBtn.action = #selector(cancelTapped); addSubview(cancelBtn)
    }

    private func styleBtn(_ b: NSButton, primary: Bool, title: String) {
        b.title = title; b.isBordered = false; b.wantsLayer = true; b.layer?.cornerRadius = kRadius / 2
        b.layer?.borderWidth = kBorderWidth; b.layer?.borderColor = kBorder.cgColor; b.font = dynamicFont(size: 12, weight: .bold)
        b.layer?.backgroundColor = primary ? kAddBg.cgColor : kSurface.cgColor
        b.contentTintColor = primary ? (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish ? .white : kSurface) : kText
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleField.frame  = NSRect(x: 14, y: h - 54, width: w - 28, height: 34)
        cancelBtn.frame   = NSRect(x: 14, y: 14, width: (w - 36) / 2, height: 32)
        addBtn.frame      = NSRect(x: 22 + (w - 36) / 2, y: 14, width: (w - 36) / 2, height: 32)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { self.titleField.becomeFirstResponder() }
    }

    func clear() { titleField.stringValue = "" }

    @objc func addTapped() {
        let t = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else {
            titleField.layer?.borderColor = NSColor.red.cgColor; titleField.layer?.borderWidth = 2; return
        }
        onAdd?(Reminder(title: t))
    }
    @objc func cancelTapped() { onCancel?() }
}

class TodoView: NSView {
    let widgetKey = "reminders"
    private var rows: [UUID: ReminderRowView] = [:]
    private var filterIdx = 0
    private var panelShown = false

    private var dragStart: NSPoint = .zero, initialWinOrigin: NSPoint = .zero
    private var dragActive = false

    private let scroll       = NSScrollView()
    private let list         = NSView()
    private let panel        = AddPanel()
    private let header       = NSTextField()
    private let badge        = NSTextField()
    private let addBtn       = NSButton()
    private let clearBtn     = NSButton()
    private let activeTabBtn = NSButton()
    private let doneTabBtn   = NSButton()

    override init(frame: NSRect) { super.init(frame: frame); build(); reload(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.borderWidth = 0; layer?.borderColor = NSColor.clear.cgColor
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor

        header.stringValue = "tututodo"
        header.font = dynamicFont(size: 17, weight: .bold); header.textColor = kText
        header.isEditable = false; header.isBordered = false; header.backgroundColor = .clear
        addSubview(header)

        badge.font = dynamicFont(size: 10, weight: .bold); badge.textColor = kText; badge.alignment = .center
        badge.isEditable = false; badge.isBordered = false; badge.backgroundColor = .clear; badge.wantsLayer = true
        badge.layer?.cornerRadius = kRadius / 2; badge.layer?.borderWidth = kBorderWidth; badge.layer?.borderColor = kBorder.cgColor
        badge.layer?.backgroundColor = kSurface.cgColor
        addSubview(badge)

        activeTabBtn.target = self; activeTabBtn.action = #selector(activeTabTapped); addSubview(activeTabBtn)
        doneTabBtn.target   = self; doneTabBtn.action   = #selector(doneTabTapped); addSubview(doneTabBtn)
        updateTabStyles()

        addBtn.title = "+ Add"; addBtn.font = dynamicFont(size: 12, weight: .bold); addBtn.isBordered = false
        addBtn.wantsLayer = true; addBtn.layer?.cornerRadius = kRadius / 2; addBtn.layer?.borderWidth = kBorderWidth; addBtn.layer?.borderColor = kBorder.cgColor
        addBtn.layer?.backgroundColor = kAddBg.cgColor
        addBtn.contentTintColor = (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish) ? .white : kSurface
        addBtn.target = self; addBtn.action = #selector(showPanel); addSubview(addBtn)

        clearBtn.title = "Clear Done"; clearBtn.font = dynamicFont(size: 11, weight: .medium)
        clearBtn.isBordered = false; clearBtn.contentTintColor = kText; clearBtn.target = self; clearBtn.action = #selector(clearDone); addSubview(clearBtn)

        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false; scroll.documentView = list; addSubview(scroll)

        panel.isHidden = true; panel.alphaValue = 0
        panel.onAdd    = { [weak self] r in self?.doAdd(r) }
        panel.onCancel = { [weak self] in self?.hidePanel() }
        addSubview(panel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        header.frame    = NSRect(x: 16, y: h - 42, width: 120, height: 24)
        badge.frame     = NSRect(x: 140, y: h - 37, width: 26, height: 18)
        addBtn.frame    = NSRect(x: w - 78, y: h - 40, width: 64, height: 24)

        let tabW = (w - 28) / 2
        activeTabBtn.frame = NSRect(x: 14, y: h - 72, width: tabW, height: 24)
        doneTabBtn.frame   = NSRect(x: 14 + tabW, y: h - 72, width: tabW, height: 24)

        clearBtn.frame  = NSRect(x: 14, y: 10, width: 82, height: 18)
        scroll.frame    = NSRect(x: 10, y: 34, width: w - 20, height: h - 112)
        panel.frame     = NSRect(x: 10, y: h/2 - 78, width: w - 20, height: 156)
        relayoutList()
    }

    @objc func activeTabTapped() { filterIdx = 0; updateTabStyles(); reload() }
    @objc func doneTabTapped()   { filterIdx = 1; updateTabStyles(); reload() }

    private func updateTabStyles() {
        styleTabButton(activeTabBtn, title: "Active", isActive: filterIdx == 0)
        styleTabButton(doneTabBtn, title: "Done", isActive: filterIdx == 1)
    }
    private func styleTabButton(_ btn: NSButton, title: String, isActive: Bool) {
        btn.isBordered = false; btn.wantsLayer = true; btn.layer?.cornerRadius = kRadius / 2
        btn.layer?.borderWidth = kBorderWidth
        btn.layer?.borderColor = kBorder.cgColor
        btn.layer?.backgroundColor = isActive ? kSurface.cgColor : NSColor.clear.cgColor
        btn.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: dynamicFont(size: 11, weight: isActive ? .bold : .medium),
            .foregroundColor: kText
        ])
    }

    private func filtered() -> [Reminder] {
        let raw = filterIdx == 1 ? ReminderStore.shared.items.filter { $0.isCompleted } : ReminderStore.shared.items.filter { !$0.isCompleted }
        return raw.sorted { a, b in
            if a.isStarred != b.isStarred {
                return a.isStarred && !b.isStarred
            }
            return a.createdAt > b.createdAt
        }
    }

    func reload() {
        let store = ReminderStore.shared
        let pending = store.items.filter { !$0.isCompleted }.count
        badge.stringValue = "\(pending)"
        badge.isHidden = pending == 0

        let filterList = filtered()
        let currentIDs = Set(filterList.map { $0.id })
        for (id, v) in rows where !currentIDs.contains(id) { v.removeFromSuperview(); rows.removeValue(forKey: id) }

        for r in filterList {
            if let existing = rows[r.id] {
                existing.reminder = r
            } else {
                let row = ReminderRowView(r)
                row.onToggle     = { [weak self] id in self?.doToggle(id) }
                row.onStarToggle = { [weak self] id in self?.doStarToggle(id) }
                row.onDelete     = { [weak self] id in self?.doDelete(id) }
                row.onEdit       = { [weak self] id, t in self?.doEdit(id, t) }
                list.addSubview(row)
                rows[r.id] = row
            }
        }
        relayoutList()
    }

    private func relayoutList() {
        let filterList = filtered()
        let rowH: CGFloat = 34, gap: CGFloat = 4, totalH = CGFloat(filterList.count) * (rowH + gap)
        let w = scroll.bounds.width
        list.frame = NSRect(x: 0, y: 0, width: w, height: max(totalH, scroll.bounds.height))

        for (i, r) in filterList.enumerated() {
            if let row = rows[r.id] {
                let y = list.frame.height - CGFloat(i + 1) * (rowH + gap)
                row.frame = NSRect(x: 0, y: y, width: w, height: rowH)
            }
        }
    }

    @objc func showPanel() {
        guard !panelShown else { return }
        panelShown = true; panel.clear(); panel.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18; panel.animator().alphaValue = 1
        }
    }

    func hidePanel() {
        guard panelShown else { return }
        panelShown = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15; panel.animator().alphaValue = 0
        }, completionHandler: { self.panel.isHidden = true })
    }

    private func doAdd(_ r: Reminder) { ReminderStore.shared.add(r); hidePanel(); reload() }
    private func doToggle(_ id: UUID) { ReminderStore.shared.toggle(id: id); reload() }
    private func doStarToggle(_ id: UUID) { ReminderStore.shared.toggleStar(id: id); reload() }
    private func doDelete(_ id: UUID) { ReminderStore.shared.delete(id: id); reload() }
    private func doEdit(_ id: UUID, _ title: String) { ReminderStore.shared.updateTitle(id: id, title: title); reload() }
    @objc func clearDone() { ReminderStore.shared.clearCompleted(); reload() }

    private func listenForThemeChanges() {
        NotificationCenter.default.addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
    }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let p = ThemeManager.shared.currentPreset
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            self.layer?.cornerRadius = p.cornerRadius
            self.layer?.borderColor = NSColor.clear.cgColor
            self.layer?.borderWidth = 0
            self.updateThemeRecursively(preset: p)
            CATransaction.commit()
            self.reload()
            self.needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) { dragStart = NSEvent.mouseLocation; if let w = window { initialWinOrigin = w.frame.origin }; dragActive = true; window?.makeKey() }
    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { return }
        let c = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: initialWinOrigin.x + (c.x - dragStart.x), y: initialWinOrigin.y + (c.y - dragStart.y)))
    }
    override func mouseUp(with event: NSEvent) {
        dragActive = false
        if let w = window { PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin) }
    }
}

// MARK: - CALENDAR EVENT STORE
struct CalendarEvent: Codable {
    var id: UUID
    var dateKey: String // "YYYY-MM-DD"
    var title: String
    var createdAt: Date

    init(id: UUID = UUID(), dateKey: String, title: String, createdAt: Date = Date()) {
        self.id = id
        self.dateKey = dateKey
        self.title = title
        self.createdAt = createdAt
    }
}

class CalendarEventStore {
    static let shared = CalendarEventStore()
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("tututodoWidget")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("calendar_events.json")
    }()
    private(set) var events: [CalendarEvent] = []
    private init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CalendarEvent].self, from: data) else { return }
        events = decoded
    }
    func save() {
        try? JSONEncoder().encode(events).write(to: url)
    }
    func events(for dateKey: String) -> [CalendarEvent] {
        return events.filter { $0.dateKey == dateKey }
    }
    func hasEvents(for dateKey: String) -> Bool {
        return events.contains { $0.dateKey == dateKey }
    }
    func add(_ ev: CalendarEvent) {
        events.append(ev)
        save()
    }
    func updateTitle(id: UUID, title: String) {
        if let idx = events.firstIndex(where: { $0.id == id }) {
            events[idx].title = title
            save()
        }
    }
    func delete(id: UUID) {
        events.removeAll { $0.id == id }
        save()
    }
}

// MARK: - 2. MONTHLY CALENDAR WIDGET (tutucalendar)
class CalendarView: NSView {
    let widgetKey = "calendar"
    private let titleLabel = NSTextField()
    private let legendLabel = NSTextField()
    private var dayViews: [NSTextField] = []
    private var dragStart: NSPoint = .zero, initialWinOrigin: NSPoint = .zero, dragActive = false

    override init(frame: NSRect) { super.init(frame: frame); build(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.borderWidth = 0; layer?.borderColor = NSColor.clear.cgColor
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor

        titleLabel.font = dynamicFont(size: 13, weight: .bold); titleLabel.textColor = kText
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear; addSubview(titleLabel)

        let legendCell = CenteredTextFieldCell(textCell: "MON/THU: GIVE LAUNDRY  •  WED/SAT: TAKE LAUNDRY")
        legendCell.alignment = .center
        legendLabel.cell = legendCell
        legendLabel.font = dynamicFont(size: 8.5, weight: .bold)
        legendLabel.textColor = kDim
        legendLabel.isEditable = false; legendLabel.isBordered = false; legendLabel.backgroundColor = .clear; addSubview(legendLabel)

        let headers = ["S", "M", "T", "W", "T", "F", "S"]
        for (idx, h) in headers.enumerated() {
            let lbl = NSTextField(labelWithString: h); lbl.font = dynamicFont(size: 10, weight: .bold); lbl.textColor = kDim; lbl.alignment = .center
            if idx == 1 || idx == 4 { // Mon & Thu
                lbl.textColor = NSColor(hex: "#F59E0B") ?? kAccent
            } else if idx == 3 || idx == 6 { // Wed & Sat
                lbl.textColor = NSColor(hex: "#10B981") ?? kAccent
            }
            addSubview(lbl); dayViews.append(lbl)
        }

        for _ in 0..<42 {
            let lbl = NSTextField(); lbl.font = dynamicFont(size: 11, weight: .bold); lbl.alignment = .center
            lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear; lbl.wantsLayer = true; lbl.layer?.cornerRadius = 6
            let dclick = NSClickGestureRecognizer(target: self, action: #selector(dayDoubleClicked(_:)))
            dclick.numberOfClicksRequired = 2
            lbl.addGestureRecognizer(dclick)
            addSubview(lbl); dayViews.append(lbl)
        }
        updateCalendar()
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleLabel.frame = NSRect(x: 12, y: h - 28, width: w - 24, height: 18)
        legendLabel.frame = NSRect(x: 12, y: 6, width: w - 24, height: 14)

        let gridX: CGFloat = 12, gridY: CGFloat = 24, colW = (w - 24) / 7.0, rowH = (h - 56) / 7.0
        for i in 0..<7 { dayViews[i].frame = NSRect(x: gridX + CGFloat(i) * colW, y: gridY + 6 * rowH, width: colW, height: rowH) }
        for r in 0..<6 {
            for c in 0..<7 {
                let idx = 7 + r * 7 + c
                dayViews[idx].frame = NSRect(x: gridX + CGFloat(c) * colW, y: gridY + CGFloat(5 - r) * rowH, width: colW, height: rowH)
            }
        }
    }

    private func updateCalendar() {
        let cal = Calendar.current, now = Date(), comp = cal.dateComponents([.year, .month, .day], from: now)
        let year = comp.year!, month = comp.month!, today = comp.day!
        let df = DateFormatter(); df.dateFormat = "MMMM yyyy"; titleLabel.stringValue = df.string(from: now).uppercased()

        var fComp = DateComponents(); fComp.year = year; fComp.month = month; fComp.day = 1
        let fDate = cal.date(from: fComp)!, fWeekday = cal.component(.weekday, from: fDate) - 1
        let numDays = cal.range(of: .day, in: .month, for: now)!.count

        for i in 0..<42 {
            let lbl = dayViews[7 + i], dNum = i - fWeekday + 1
            let c = i % 7 // Column 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat

            if dNum >= 1 && dNum <= numDays {
                lbl.tag = dNum
                let dateKey = String(format: "%04d-%02d-%02d", year, month, dNum)
                let hasEv = CalendarEventStore.shared.hasEvents(for: dateKey)
                let evDot = hasEv ? " •" : ""

                lbl.stringValue = "\(dNum)\(evDot)"
                if dNum == today {
                    lbl.backgroundColor = kAccent
                    lbl.textColor = (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish) ? .white : kSurface
                    lbl.font = dynamicFont(size: 11, weight: .bold)
                    lbl.layer?.borderWidth = 2.0
                    if c == 1 || c == 4 { // Give Laundry
                        lbl.layer?.borderColor = (NSColor(hex: "#F59E0B") ?? kAccent).cgColor
                    } else if c == 3 || c == 6 { // Take Laundry
                        lbl.layer?.borderColor = (NSColor(hex: "#10B981") ?? kAccent).cgColor
                    } else {
                        lbl.layer?.borderColor = NSColor.clear.cgColor
                    }
                } else if hasEv {
                    lbl.font = dynamicFont(size: 11, weight: .bold)
                    lbl.backgroundColor = (NSColor(hex: "#8B5CF6") ?? kAccent).withAlphaComponent(0.25)
                    lbl.textColor = (ThemeManager.shared.currentPreset == .glass) ? (NSColor(hex: "#C4B5FD") ?? kText) : (NSColor(hex: "#6D28D9") ?? kText)
                    lbl.layer?.borderWidth = 1.5
                    lbl.layer?.borderColor = (NSColor(hex: "#8B5CF6") ?? kAccent).withAlphaComponent(0.6).cgColor
                } else {
                    lbl.font = dynamicFont(size: 11, weight: .medium)
                    if c == 1 || c == 4 { // Give Laundry (Mon / Thu)
                        lbl.backgroundColor = (NSColor(hex: "#F59E0B") ?? kAccent).withAlphaComponent(0.22)
                        lbl.textColor = (ThemeManager.shared.currentPreset == .glass) ? (NSColor(hex: "#FBBF24") ?? kText) : (NSColor(hex: "#D97706") ?? kText)
                        lbl.layer?.borderWidth = 1.0
                        lbl.layer?.borderColor = (NSColor(hex: "#F59E0B") ?? kAccent).withAlphaComponent(0.45).cgColor
                    } else if c == 3 || c == 6 { // Take Laundry (Wed / Sat)
                        lbl.backgroundColor = (NSColor(hex: "#10B981") ?? kAccent).withAlphaComponent(0.22)
                        lbl.textColor = (ThemeManager.shared.currentPreset == .glass) ? (NSColor(hex: "#34D399") ?? kText) : (NSColor(hex: "#059669") ?? kText)
                        lbl.layer?.borderWidth = 1.0
                        lbl.layer?.borderColor = (NSColor(hex: "#10B981") ?? kAccent).withAlphaComponent(0.45).cgColor
                    } else {
                        lbl.backgroundColor = .clear
                        lbl.textColor = kText
                        lbl.layer?.borderWidth = 0
                        lbl.layer?.borderColor = NSColor.clear.cgColor
                    }
                }
            } else {
                lbl.tag = 0
                lbl.stringValue = ""
                lbl.backgroundColor = .clear
                lbl.layer?.borderWidth = 0
                lbl.layer?.borderColor = NSColor.clear.cgColor
            }
        }
    }

    @objc private func dayDoubleClicked(_ sender: NSClickGestureRecognizer) {
        guard let lbl = sender.view as? NSTextField, lbl.tag > 0 else { return }
        let day = lbl.tag

        let cal = Calendar.current, now = Date()
        let comp = cal.dateComponents([.year, .month], from: now)
        let year = comp.year!, month = comp.month!
        let dateKey = String(format: "%04d-%02d-%02d", year, month, day)

        manageEvents(for: dateKey, day: day, month: month, year: year)
    }

    private func manageEvents(for dateKey: String, day: Int, month: Int, year: Int) {
        guard let window = self.window else { return }
        let evList = CalendarEventStore.shared.events(for: dateKey)

        var dateComp = DateComponents(); dateComp.year = year; dateComp.month = month; dateComp.day = day
        let dateObj = Calendar.current.date(from: dateComp) ?? Date()
        let df = DateFormatter(); df.dateFormat = "MMMM d, yyyy"
        let dateTitle = df.string(from: dateObj)

        let alert = NSAlert()
        alert.messageText = "Events for \(dateTitle)"

        if evList.isEmpty {
            alert.informativeText = "No events scheduled for this day."
        } else {
            let evLines = evList.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "\n")
            alert.informativeText = "Scheduled Events (\(evList.count)):\n\(evLines)"
        }

        alert.addButton(withTitle: "+ Add Event")
        if !evList.isEmpty {
            alert.addButton(withTitle: "Edit Event")
            alert.addButton(withTitle: "Delete Event")
        }
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { [weak self] resp in
            guard let self = self else { return }
            if resp == .alertFirstButtonReturn {
                self.promptAddEvent(dateKey: dateKey, dateTitle: dateTitle)
            } else if resp == .alertSecondButtonReturn && !evList.isEmpty {
                self.promptEditEvent(dateKey: dateKey, dateTitle: dateTitle, events: evList)
            } else if resp == .alertThirdButtonReturn && !evList.isEmpty {
                self.promptDeleteEvent(dateKey: dateKey, dateTitle: dateTitle, events: evList)
            }
        }
    }

    private func promptAddEvent(dateKey: String, dateTitle: String) {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "Add Event for \(dateTitle)"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        let pAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: kDim, .font: dynamicFont(size: 12, weight: .medium)]
        tf.placeholderAttributedString = NSAttributedString(string: "Event title (e.g. Meeting @ 3PM)", attributes: pAttrs)
        alert.accessoryView = tf

        alert.beginSheetModal(for: window) { [weak self] resp in
            if resp == .alertFirstButtonReturn {
                let t = tf.stringValue.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty {
                    CalendarEventStore.shared.add(CalendarEvent(dateKey: dateKey, title: t))
                    self?.updateCalendar()
                }
            }
        }
        DispatchQueue.main.async { tf.becomeFirstResponder() }
    }

    private func promptEditEvent(dateKey: String, dateTitle: String, events: [CalendarEvent]) {
        guard let window = self.window else { return }
        if events.count == 1 {
            let ev = events[0]
            promptSingleEdit(ev: ev, dateTitle: dateTitle)
        } else {
            let alert = NSAlert()
            alert.messageText = "Select Event to Edit (\(dateTitle))"
            alert.addButton(withTitle: "Edit Selected")
            alert.addButton(withTitle: "Cancel")

            let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
            for ev in events {
                pop.addItem(withTitle: ev.title)
            }
            alert.accessoryView = pop

            alert.beginSheetModal(for: window) { [weak self] resp in
                guard let self = self else { return }
                if resp == .alertFirstButtonReturn {
                    let idx = pop.indexOfSelectedItem
                    if idx >= 0 && idx < events.count {
                        self.promptSingleEdit(ev: events[idx], dateTitle: dateTitle)
                    }
                }
            }
        }
    }

    private func promptSingleEdit(ev: CalendarEvent, dateTitle: String) {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "Edit Event (\(dateTitle))"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        tf.stringValue = ev.title
        alert.accessoryView = tf

        alert.beginSheetModal(for: window) { [weak self] resp in
            if resp == .alertFirstButtonReturn {
                let newT = tf.stringValue.trimmingCharacters(in: .whitespaces)
                if !newT.isEmpty {
                    CalendarEventStore.shared.updateTitle(id: ev.id, title: newT)
                    self?.updateCalendar()
                }
            }
        }
        DispatchQueue.main.async { tf.becomeFirstResponder() }
    }

    private func promptDeleteEvent(dateKey: String, dateTitle: String, events: [CalendarEvent]) {
        guard let window = self.window else { return }
        if events.count == 1 {
            CalendarEventStore.shared.delete(id: events[0].id)
            self.updateCalendar()
        } else {
            let alert = NSAlert()
            alert.messageText = "Select Event to Delete (\(dateTitle))"
            alert.addButton(withTitle: "Delete Selected")
            alert.addButton(withTitle: "Cancel")

            let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
            for ev in events {
                pop.addItem(withTitle: ev.title)
            }
            alert.accessoryView = pop

            alert.beginSheetModal(for: window) { [weak self] resp in
                if resp == .alertFirstButtonReturn {
                    let idx = pop.indexOfSelectedItem
                    if idx >= 0 && idx < events.count {
                        CalendarEventStore.shared.delete(id: events[idx].id)
                        self?.updateCalendar()
                    }
                }
            }
        }
    }

    private func listenForThemeChanges() {
        NotificationCenter.default.addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
    }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let p = ThemeManager.shared.currentPreset
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            self.layer?.cornerRadius = p.cornerRadius
            self.layer?.borderColor = NSColor.clear.cgColor
            self.layer?.borderWidth = 0
            self.updateThemeRecursively(preset: p)
            self.updateCalendar()
            CATransaction.commit()
            self.needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) { dragStart = NSEvent.mouseLocation; if let w = window { initialWinOrigin = w.frame.origin }; dragActive = true; window?.makeKey() }
    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { return }
        let c = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: initialWinOrigin.x + (c.x - dragStart.x), y: initialWinOrigin.y + (c.y - dragStart.y)))
    }
    override func mouseUp(with event: NSEvent) {
        dragActive = false
        if let w = window { PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin) }
    }
}

// MARK: - 3. BATTERY & DEVICES WIDGET (tutubattery)
class BatteryView: NSView {
    let widgetKey = "battery"
    private let macCard = NSView()
    private let macPctLabel = NSTextField()
    private let macStatusLabel = NSTextField()
    private let macProgressBar = NSView()
    private let macProgressFill = NSView()

    private let btHeaderLabel = NSTextField()
    private let btListContainer = NSView()

    private var timer: Timer?
    private var isFetching = false
    private var lastDevices: [(name: String, battery: Int?)] = []
    private var dragStart: NSPoint = .zero, initialWinOrigin: NSPoint = .zero, dragActive = false

    override init(frame: NSRect) { super.init(frame: frame); build(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.borderWidth = 0; layer?.borderColor = NSColor.clear.cgColor
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor

        macCard.wantsLayer = true; macCard.layer?.cornerRadius = kRadius / 2; macCard.layer?.backgroundColor = kSurface.cgColor
        macCard.layer?.borderWidth = kBorderWidth; macCard.layer?.borderColor = kBorder.cgColor; addSubview(macCard)

        macPctLabel.font = dynamicFont(size: 32, weight: .bold); macPctLabel.textColor = kText
        macPctLabel.isEditable = false; macPctLabel.isBordered = false; macPctLabel.backgroundColor = .clear; macCard.addSubview(macPctLabel)

        let statusCell = CenteredTextFieldCell(textCell: "")
        statusCell.alignment = .center; statusCell.font = dynamicFont(size: 11, weight: .bold); statusCell.textColor = .white
        macStatusLabel.cell = statusCell; macStatusLabel.isEditable = false; macStatusLabel.isBordered = false
        macStatusLabel.wantsLayer = true; macStatusLabel.layer?.cornerRadius = kRadius / 2; macStatusLabel.layer?.backgroundColor = kAccent.cgColor
        macStatusLabel.layer?.borderWidth = kBorderWidth; macStatusLabel.layer?.borderColor = kBorder.cgColor; macCard.addSubview(macStatusLabel)

        macProgressBar.wantsLayer = true; macProgressBar.layer?.cornerRadius = kRadius / 2; macProgressBar.layer?.backgroundColor = kSurface.cgColor
        macProgressBar.layer?.borderWidth = kBorderWidth; macProgressBar.layer?.borderColor = kBorder.cgColor; macCard.addSubview(macProgressBar)

        macProgressFill.wantsLayer = true; macProgressFill.layer?.cornerRadius = kRadius / 2; macProgressFill.layer?.backgroundColor = kAccent.cgColor; macProgressBar.addSubview(macProgressFill)

        btHeaderLabel.stringValue = "BLUETOOTH DEVICES"
        btHeaderLabel.font = dynamicFont(size: 10, weight: .bold); btHeaderLabel.textColor = kDim
        btHeaderLabel.isEditable = false; btHeaderLabel.isBordered = false; btHeaderLabel.backgroundColor = .clear; addSubview(btHeaderLabel)

        addSubview(btListContainer)
        updateBattery()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in self?.updateBattery() }
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        macCard.frame = NSRect(x: 12, y: h - 100, width: w - 24, height: 88)
        macPctLabel.frame = NSRect(x: 12, y: 40, width: 120, height: 38)
        macStatusLabel.frame = NSRect(x: w - 136, y: 46, width: 98, height: 26)
        macProgressBar.frame = NSRect(x: 12, y: 14, width: w - 48, height: 18)

        btHeaderLabel.frame = NSRect(x: 14, y: h - 124, width: w - 28, height: 16)
        btListContainer.frame = NSRect(x: 12, y: 12, width: w - 24, height: h - 142)
    }

    private func updateBattery() {
        let (pct, charging) = getMacBatteryInfo()
        macPctLabel.stringValue = "\(pct)%"
        if charging {
            macStatusLabel.isHidden = false; macStatusLabel.stringValue = "CHARGING"
        } else {
            macStatusLabel.isHidden = true
        }
        let fillW = (macProgressBar.bounds.width) * (CGFloat(pct) / 100.0)
        macProgressFill.frame = NSRect(x: 0, y: 0, width: fillW, height: macProgressBar.bounds.height)

        fetchBTDevicesAsync()
    }

    private func getMacBatteryInfo() -> (percent: Int, isCharging: Bool) {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for src in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, src).takeUnretainedValue() as? [String: Any] {
                let capacity = info[kIOPSCurrentCapacityKey] as? Int ?? 100
                let isCharging = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                return (capacity, isCharging)
            }
        }
        return (100, false)
    }

    private func fetchBTDevicesAsync() {
        guard !isFetching else { return }
        isFetching = true
        DispatchQueue.global(qos: .background).async { [weak self] in
            let devices = self?.getBTDevicesBackground() ?? []
            DispatchQueue.main.async { self?.isFetching = false; self?.renderBTDevices(devices) }
        }
    }

    private func getBTDevicesBackground() -> [(name: String, battery: Int?)] {
        var list: [(name: String, battery: Int?)] = []
        if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for d in devices where d.isConnected() {
                let name = d.nameOrAddress ?? "Bluetooth Device"
                var bat: Int? = nil
                let keys = ["batteryPercentSingle", "batteryPercentCombined", "batteryPercentLeft", "batteryPercentRight", "batteryPercentCase"]
                for k in keys {
                    if let num = d.value(forKey: k) as? Int, num > 0 && num <= 100 {
                        bat = max(bat ?? 0, num)
                    }
                }
                list.append((name: name, battery: bat))
            }
        }
        if list.isEmpty {
            let pipe = Pipe(), proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            proc.arguments = ["SPBluetoothDataType"]; proc.standardOutput = pipe
            try? proc.run(); proc.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8) ?? ""

            if let connRange = str.range(of: "Connected:") {
                let sub = str[connRange.upperBound...]
                let connSection: String
                if let notConnRange = sub.range(of: "Not Connected:") { connSection = String(sub[..<notConnRange.lowerBound]) }
                else { connSection = String(sub) }

                let lines = connSection.components(separatedBy: .newlines)
                var currentName: String?
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if line.hasPrefix("          ") && !line.hasPrefix("              ") {
                        let name = trimmed.replacingOccurrences(of: ":", with: "")
                        if !name.isEmpty { currentName = name }
                    } else if line.contains("Battery Level:"), let name = currentName {
                        if let range = line.range(of: "(\\d+)%", options: .regularExpression) {
                            let numStr = line[range].replacingOccurrences(of: "%", with: "")
                            list.append((name: name, battery: Int(numStr)))
                            currentName = nil
                        }
                    }
                }
                if let name = currentName, !list.contains(where: { $0.name == name }) { list.append((name: name, battery: nil)) }
            }
        }
        return list
    }

    private func renderBTDevices(_ devices: [(name: String, battery: Int?)]) {
        let changed = devices.map { "\($0.name):\($0.battery ?? -1)" } != lastDevices.map { "\($0.name):\($0.battery ?? -1)" }
        guard changed || btListContainer.subviews.isEmpty else { return }
        lastDevices = devices
        for sub in btListContainer.subviews { sub.removeFromSuperview() }

        if devices.isEmpty {
            let noDevLabel = NSTextField(labelWithString: "No Bluetooth devices connected")
            noDevLabel.font = dynamicFont(size: 11, weight: .medium); noDevLabel.textColor = kDim; noDevLabel.alignment = .center
            noDevLabel.frame = NSRect(x: 0, y: (btListContainer.bounds.height - 20)/2, width: btListContainer.bounds.width, height: 20)
            btListContainer.addSubview(noDevLabel)
            return
        }

        let containerW = btListContainer.bounds.width, itemH: CGFloat = 40, gap: CGFloat = 6
        for (i, dev) in devices.enumerated() {
            let y = btListContainer.bounds.height - CGFloat(i + 1) * (itemH + gap)
            let devCard = NSView(frame: NSRect(x: 0, y: y, width: containerW, height: itemH))
            devCard.wantsLayer = true; devCard.layer?.cornerRadius = kRadius / 2; devCard.layer?.backgroundColor = kSurface.cgColor
            devCard.layer?.borderWidth = kBorderWidth; devCard.layer?.borderColor = kBorder.cgColor

            let nameTF = NSTextField()
            let nameCell = CenteredTextFieldCell(textCell: dev.name)
            nameCell.font = dynamicFont(size: 12, weight: .bold); nameCell.textColor = kText; nameCell.lineBreakMode = .byTruncatingTail
            nameTF.cell = nameCell; nameTF.stringValue = dev.name
            nameTF.isEditable = false; nameTF.isBordered = false; nameTF.backgroundColor = .clear
            nameTF.frame = NSRect(x: 10, y: 8, width: containerW - 74, height: 24)
            devCard.addSubview(nameTF)

            let batText = dev.battery != nil ? "\(dev.battery!)%" : "N/A"
            let badgeTF = NSTextField()
            let badgeCell = CenteredTextFieldCell(textCell: batText)
            badgeCell.alignment = .center; badgeCell.font = dynamicFont(size: 11, weight: .bold)
            badgeCell.textColor = (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish) ? .white : kSurface
            badgeTF.cell = badgeCell; badgeTF.stringValue = batText
            badgeTF.isEditable = false; badgeTF.isBordered = false
            badgeTF.wantsLayer = true; badgeTF.layer?.cornerRadius = kRadius / 2; badgeTF.layer?.backgroundColor = kAccent.cgColor
            badgeTF.layer?.borderWidth = kBorderWidth; badgeTF.layer?.borderColor = kBorder.cgColor
            badgeTF.frame = NSRect(x: containerW - 60, y: 8, width: 48, height: 24)
            devCard.addSubview(badgeTF)

            btListContainer.addSubview(devCard)
        }
    }

    private func listenForThemeChanges() {
        NotificationCenter.default.addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
    }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let p = ThemeManager.shared.currentPreset
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            self.layer?.cornerRadius = p.cornerRadius
            self.layer?.borderColor = NSColor.clear.cgColor
            self.layer?.borderWidth = 0
            self.updateThemeRecursively(preset: p)
            self.updateBattery()
            CATransaction.commit()
            self.needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) { dragStart = NSEvent.mouseLocation; if let w = window { initialWinOrigin = w.frame.origin }; dragActive = true; window?.makeKey() }
    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { return }
        let c = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: initialWinOrigin.x + (c.x - dragStart.x), y: initialWinOrigin.y + (c.y - dragStart.y)))
    }
    override func mouseUp(with event: NSEvent) {
        dragActive = false
        if let w = window { PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin) }
    }
}

// (Standalone LaundryView removed in favor of direct CalendarView integration)

// MARK: - 4. DIGITAL CLOCK WIDGET (tutuclock)
class DigitalClockView: NSView {
    let widgetKey = "digital_clock"
    private let timeLabel = NSTextField()
    private let dateLabel = NSTextField()
    private var timer: Timer?
    private var dragStart: NSPoint = .zero, initialWinOrigin: NSPoint = .zero, dragActive = false

    override init(frame: NSRect) { super.init(frame: frame); build(); updateTime(); startTimer(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.borderWidth = 0; layer?.borderColor = NSColor.clear.cgColor
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor

        timeLabel.font = dynamicFont(size: 42, weight: .bold); timeLabel.textColor = kText; timeLabel.alignment = .center
        timeLabel.isEditable = false; timeLabel.isBordered = false; timeLabel.backgroundColor = .clear; addSubview(timeLabel)

        dateLabel.font = dynamicFont(size: 12, weight: .bold); dateLabel.textColor = kDim; dateLabel.alignment = .center
        dateLabel.isEditable = false; dateLabel.isBordered = false; dateLabel.backgroundColor = .clear; addSubview(dateLabel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        timeLabel.frame = NSRect(x: 10, y: 32, width: w - 20, height: 50)
        dateLabel.frame = NSRect(x: 10, y: 12, width: w - 20, height: 20)
    }

    private func startTimer() { timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateTime() } }

    private func updateTime() {
        let now = Date()
        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        timeLabel.stringValue = tf.string(from: now)

        let df = DateFormatter(); df.dateFormat = "EEEE, MMMM d, yyyy"
        dateLabel.stringValue = df.string(from: now).uppercased()
    }

    private func listenForThemeChanges() {
        NotificationCenter.default.addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
    }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let p = ThemeManager.shared.currentPreset
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            self.layer?.cornerRadius = p.cornerRadius
            self.layer?.borderColor = NSColor.clear.cgColor
            self.layer?.borderWidth = 0
            self.updateThemeRecursively(preset: p)
            self.updateTime()
            CATransaction.commit()
            self.needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) { dragStart = NSEvent.mouseLocation; if let w = window { initialWinOrigin = w.frame.origin }; dragActive = true; window?.makeKey() }
    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { return }
        let c = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: initialWinOrigin.x + (c.x - dragStart.x), y: initialWinOrigin.y + (c.y - dragStart.y)))
    }
    override func mouseUp(with event: NSEvent) {
        dragActive = false
        if let w = window { PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin) }
    }
}

// MARK: - 5. COLOR PICKER WIDGET (tutucolor)
class ColorPickerView: NSView {
    let widgetKey = "color_picker"
    private let bgTitleLabel = NSTextField()
    private let bgSwatchesContainer = NSView()
    private let bgPickerBtn = NSButton()

    private let textTitleLabel = NSTextField()
    private let textSwatchesContainer = NSView()
    private let textPickerBtn = NSButton()

    private var dragStart: NSPoint = .zero, initialWinOrigin: NSPoint = .zero, dragActive = false
    private var activePickerMode: String = "bg"
    
    private let bgPresetHexes   = ["#FEF9C3", "#090D16", "#FFE3F1", "#E0F2FE", "#F3E8FF", "#DCFCE7", "#F5EBE0"]
    private let textPresetHexes = ["#800020", "#000000", "#FFFFFF", "#6366F1", "#10B981", "#FF4FA0", "#64748B"]

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        listenForThemeChanges()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = kRadius
        layer?.borderWidth = kBorderWidth
        layer?.borderColor = kBorder.cgColor
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor

        // BG Row
        bgTitleLabel.stringValue = "BG COLOR"
        bgTitleLabel.font = dynamicFont(size: 9, weight: .bold)
        bgTitleLabel.textColor = kText
        bgTitleLabel.isEditable = false; bgTitleLabel.isBordered = false; bgTitleLabel.backgroundColor = .clear
        addSubview(bgTitleLabel)

        bgSwatchesContainer.wantsLayer = true
        addSubview(bgSwatchesContainer)

        bgPickerBtn.title = "Bg"
        bgPickerBtn.font = dynamicFont(size: 9, weight: .bold)
        bgPickerBtn.isBordered = false; bgPickerBtn.wantsLayer = true; bgPickerBtn.layer?.cornerRadius = kRadius / 2
        bgPickerBtn.layer?.backgroundColor = kAccent.cgColor; bgPickerBtn.layer?.borderWidth = kBorderWidth; bgPickerBtn.layer?.borderColor = kBorder.cgColor
        bgPickerBtn.contentTintColor = .white
        bgPickerBtn.target = self; bgPickerBtn.action = #selector(openBgColorPicker); addSubview(bgPickerBtn)

        // Text Row
        textTitleLabel.stringValue = "FONT COLOR"
        textTitleLabel.font = dynamicFont(size: 9, weight: .bold)
        textTitleLabel.textColor = kText
        textTitleLabel.isEditable = false; textTitleLabel.isBordered = false; textTitleLabel.backgroundColor = .clear
        addSubview(textTitleLabel)

        textSwatchesContainer.wantsLayer = true
        addSubview(textSwatchesContainer)

        textPickerBtn.title = "Font 🔤"
        textPickerBtn.font = dynamicFont(size: 9, weight: .bold)
        textPickerBtn.isBordered = false; textPickerBtn.wantsLayer = true; textPickerBtn.layer?.cornerRadius = kRadius / 2
        textPickerBtn.layer?.backgroundColor = kAccent.cgColor; textPickerBtn.layer?.borderWidth = kBorderWidth; textPickerBtn.layer?.borderColor = kBorder.cgColor
        textPickerBtn.contentTintColor = .white
        textPickerBtn.target = self; textPickerBtn.action = #selector(openTextColorPicker); addSubview(textPickerBtn)

        renderSwatches()
    }

    private func renderSwatches() {
        // Render BG Swatches
        for sub in bgSwatchesContainer.subviews { sub.removeFromSuperview() }
        let activeBgHex = ThemeManager.shared.currentBgColor.toHex().uppercased()
        let size: CGFloat = 16, gap: CGFloat = 4

        for (i, hex) in bgPresetHexes.enumerated() {
            let btn = NSButton(frame: NSRect(x: CGFloat(i) * (size + gap), y: 0, width: size, height: size))
            btn.title = ""; btn.isBordered = false; btn.wantsLayer = true; btn.layer?.cornerRadius = size / 2
            let isSelected = (hex.uppercased() == activeBgHex)
            btn.layer?.borderWidth = isSelected ? 2.0 : 1.0
            btn.layer?.borderColor = isSelected ? kText.cgColor : kBorder.withAlphaComponent(0.6).cgColor
            if let color = NSColor(hex: hex) { btn.layer?.backgroundColor = color.cgColor }
            btn.target = self; btn.action = #selector(bgSwatchTapped(_:)); btn.tag = i
            bgSwatchesContainer.addSubview(btn)
        }

        // Render Text Swatches
        for sub in textSwatchesContainer.subviews { sub.removeFromSuperview() }
        let activeTextHex = ThemeManager.shared.currentTextColor.toHex().uppercased()

        for (i, hex) in textPresetHexes.enumerated() {
            let btn = NSButton(frame: NSRect(x: CGFloat(i) * (size + gap), y: 0, width: size, height: size))
            btn.title = ""; btn.isBordered = false; btn.wantsLayer = true; btn.layer?.cornerRadius = size / 2
            let isSelected = (hex.uppercased() == activeTextHex)
            btn.layer?.borderWidth = isSelected ? 2.0 : 1.0
            btn.layer?.borderColor = isSelected ? kText.cgColor : kBorder.withAlphaComponent(0.6).cgColor
            if let color = NSColor(hex: hex) { btn.layer?.backgroundColor = color.cgColor }
            btn.target = self; btn.action = #selector(textSwatchTapped(_:)); btn.tag = i
            textSwatchesContainer.addSubview(btn)
        }
    }

    @objc private func bgSwatchTapped(_ sender: NSButton) {
        let hex = bgPresetHexes[sender.tag]
        if let color = NSColor(hex: hex) {
            ThemeManager.shared.customBgColor = color
            renderSwatches()
        }
    }

    @objc private func textSwatchTapped(_ sender: NSButton) {
        let hex = textPresetHexes[sender.tag]
        if let color = NSColor(hex: hex) {
            ThemeManager.shared.customTextColor = color
            renderSwatches()
        }
    }

    @objc private func openBgColorPicker() {
        ColorPanelDelegate.shared.openColorWheel(for: .bg, initialColor: kBg)
    }

    @objc private func openTextColorPicker() {
        ColorPanelDelegate.shared.openColorWheel(for: .text, initialColor: kText)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        if activePickerMode == "bg" {
            ThemeManager.shared.customBgColor = sender.color
        } else {
            ThemeManager.shared.customTextColor = sender.color
        }
        renderSwatches()
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let rowH = (h - 10) / 2
        let totalSwatchesW = CGFloat(bgPresetHexes.count) * 20.0 - 4.0

        // Row 1 (BG)
        bgTitleLabel.frame = NSRect(x: 10, y: h - 18, width: 65, height: 14)
        bgSwatchesContainer.frame = NSRect(x: 75, y: h - rowH + 2, width: totalSwatchesW, height: 16)
        bgPickerBtn.frame = NSRect(x: w - 58, y: h - rowH + 1, width: 48, height: 20)

        // Row 2 (Text)
        textTitleLabel.frame = NSRect(x: 10, y: rowH - 12, width: 65, height: 14)
        textSwatchesContainer.frame = NSRect(x: 75, y: 6, width: totalSwatchesW, height: 16)
        textPickerBtn.frame = NSRect(x: w - 58, y: 5, width: 48, height: 20)
    }

    private func listenForThemeChanges() {
        NotificationCenter.default.addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
    }

    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let p = ThemeManager.shared.currentPreset
            let activeColor = ThemeManager.shared.currentBgColor
            let activeText = ThemeManager.shared.currentTextColor
            self.layer?.backgroundColor = activeColor.cgColor
            self.layer?.cornerRadius = p.cornerRadius
            self.layer?.borderColor = p.borderColor.cgColor
            self.layer?.borderWidth = p.borderWidth

            self.bgTitleLabel.textColor = activeText
            self.textTitleLabel.textColor = activeText

            self.bgPickerBtn.layer?.cornerRadius = p.cornerRadius / 2
            self.bgPickerBtn.layer?.backgroundColor = p.accentColor.cgColor
            self.bgPickerBtn.layer?.borderColor = p.borderColor.cgColor
            self.bgPickerBtn.layer?.borderWidth = p.borderWidth
            self.bgPickerBtn.font = p.font(size: 9, weight: .bold)

            self.textPickerBtn.layer?.cornerRadius = p.cornerRadius / 2
            self.textPickerBtn.layer?.backgroundColor = p.accentColor.cgColor
            self.textPickerBtn.layer?.borderColor = p.borderColor.cgColor
            self.textPickerBtn.layer?.borderWidth = p.borderWidth
            self.textPickerBtn.font = p.font(size: 9, weight: .bold)

            self.updateThemeRecursively(preset: p)
            self.renderSwatches()
            CATransaction.commit()
            self.needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) { dragStart = NSEvent.mouseLocation; if let w = window { initialWinOrigin = w.frame.origin }; dragActive = true; window?.makeKey() }
    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { return }
        let c = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: initialWinOrigin.x + (c.x - dragStart.x), y: initialWinOrigin.y + (c.y - dragStart.y)))
    }
    override func mouseUp(with event: NSEvent) {
        dragActive = false
        if let w = window { PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin) }
    }
}

// MARK: - 7. SPOTIFY LIVE PLAYER WIDGET (tutuspotify)
class AudioEqualizerView: NSView {
    var isPlaying: Bool = false { didSet { isPlaying ? startAnimation() : stopAnimation() } }
    private var barHeights: [CGFloat] = [0.3, 0.6, 0.4, 0.8], animTimer: Timer?

    private func startAnimation() {
        guard animTimer == nil else { return }
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.barHeights = (0..<4).map { _ in CGFloat.random(in: 0.25...1.0) }
            self?.needsDisplay = true
        }
    }
    private func stopAnimation() { animTimer?.invalidate(); animTimer = nil; barHeights = [0.15, 0.15, 0.15, 0.15]; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let barCount = 4, gap: CGFloat = 3, barW = (bounds.width - CGFloat(barCount - 1) * gap) / CGFloat(barCount), maxH = bounds.height
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
            ctx.setFillColor(kText.cgColor); ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2)); ctx.fillPath()
            ctx.setStrokeColor(kBorder.cgColor); ctx.setLineWidth(1.0); ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2)); ctx.strokePath()
        }
    }
}

class SpotifyView: NSView {
    let widgetKey = "spotify"
    private let eqView = AudioEqualizerView()
    private let artImageView = NSImageView()
    private let trackLabel = NSTextField(), artistLabel = NSTextField()
    private let progressBar = ProgressBarView(), currTimeLabel = NSTextField(), durTimeLabel = NSTextField()
    private let prevBtn = NSButton(), playBtn = NSButton(), nextBtn = NSButton(), statusLabel = NSTextField()
    private var timer: Timer?, currentArtUrl = "", isPlaying = false, dragStart: NSPoint = .zero, initialWinOrigin: NSPoint = .zero, dragActive = false

    override init(frame: NSRect) { super.init(frame: frame); build(); updateSpotifyInfo(); startTimer(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.borderWidth = 0; layer?.borderColor = NSColor.clear.cgColor
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
        addSubview(eqView)

        artImageView.wantsLayer = true; artImageView.layer?.cornerRadius = 0.0; artImageView.layer?.borderWidth = kBorderWidth; artImageView.layer?.borderColor = kBorder.cgColor
        artImageView.imageScaling = .scaleAxesIndependently; artImageView.imageAlignment = .alignCenter; addSubview(artImageView)

        trackLabel.font = dynamicFont(size: 13, weight: .bold); trackLabel.textColor = kText; trackLabel.isEditable = false; trackLabel.isBordered = false; trackLabel.backgroundColor = .clear; trackLabel.lineBreakMode = .byTruncatingTail; addSubview(trackLabel)
        artistLabel.font = dynamicFont(size: 11, weight: .bold); artistLabel.textColor = kDim; artistLabel.isEditable = false; artistLabel.isBordered = false; artistLabel.backgroundColor = .clear; artistLabel.lineBreakMode = .byTruncatingTail; addSubview(artistLabel)

        progressBar.wantsLayer = true; addSubview(progressBar)
        currTimeLabel.font = dynamicFont(size: 10, weight: .bold); currTimeLabel.textColor = kText; currTimeLabel.isEditable = false; currTimeLabel.isBordered = false; currTimeLabel.backgroundColor = .clear; addSubview(currTimeLabel)
        durTimeLabel.font = dynamicFont(size: 10, weight: .bold); durTimeLabel.textColor = kDim; durTimeLabel.isEditable = false; durTimeLabel.isBordered = false; durTimeLabel.backgroundColor = .clear; durTimeLabel.alignment = .right; addSubview(durTimeLabel)

        setupBtn(prevBtn, title: "⏮", action: #selector(onPrev))
        setupBtn(playBtn, title: "▶", action: #selector(onPlayPause))
        setupBtn(nextBtn, title: "⏭", action: #selector(onNext))

        statusLabel.stringValue = "Spotify Offline"; statusLabel.font = dynamicFont(size: 12, weight: .bold); statusLabel.textColor = kDim; statusLabel.alignment = .center; statusLabel.isEditable = false; statusLabel.isBordered = false; statusLabel.backgroundColor = .clear; statusLabel.isHidden = true; addSubview(statusLabel)
    }

    private func setupBtn(_ btn: NSButton, title: String, action: Selector) {
        btn.title = title; btn.font = dynamicFont(size: 12, weight: .bold); btn.isBordered = false; btn.wantsLayer = true; btn.layer?.cornerRadius = kRadius / 2; btn.layer?.backgroundColor = kAccent.cgColor; btn.layer?.borderWidth = kBorderWidth; btn.layer?.borderColor = kBorder.cgColor
        btn.contentTintColor = (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish) ? .white : kSurface; btn.target = self; btn.action = action; addSubview(btn)
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
        statusLabel.frame = NSRect(x: 10, y: (h - 30)/2, width: w - 20, height: 30)
    }

    private func startTimer() { timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateSpotifyInfo() } }

    private func fmtTime(_ sec: Double) -> String {
        guard sec > 0 && !sec.isNaN && !sec.isInfinite else { return "0:00" }
        let t = Int(sec); return String(format: "%d:%02d", t / 60, t % 60)
    }

    private var artTask: URLSessionDataTask?

    @objc private func updateSpotifyInfo() {
        let sc = """
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing or player state is paused then
                    set trackName to name of current track
                    set artistName to artist of current track
                    set artUrl to artwork url of current track
                    set pState to (player state is playing)
                    set pPos to player position
                    set pDur to (duration of current track) / 1000.0
                    return trackName & "|||" & artistName & "|||" & artUrl & "|||" & pState & "|||" & pPos & "|||" & pDur
                end if
            end tell
        end if
        return "OFFLINE"
        """
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let res = runScript(sc)
            DispatchQueue.main.async { self?.handleSpotifyResult(res) }
        }
    }

    private func handleSpotifyResult(_ res: String) {
        if res == "OFFLINE" || res.isEmpty {
            eqView.isPlaying = false; eqView.isHidden = true; artImageView.isHidden = true; trackLabel.isHidden = true; artistLabel.isHidden = true; progressBar.isHidden = true; currTimeLabel.isHidden = true; durTimeLabel.isHidden = true; prevBtn.isHidden = true; playBtn.isHidden = true; nextBtn.isHidden = true
            statusLabel.stringValue = "Spotify Offline"; statusLabel.isHidden = false
        } else {
            let p = res.components(separatedBy: "|||")
            if p.count >= 6 {
                trackLabel.stringValue = p[0]; artistLabel.stringValue = p[1]; isPlaying = (p[3] == "true")
                playBtn.title = isPlaying ? "⏸" : "▶"; eqView.isPlaying = isPlaying
                let pos = Double(p[4]) ?? 0.0, dur = Double(p[5]) ?? 1.0
                currTimeLabel.stringValue = fmtTime(pos); durTimeLabel.stringValue = fmtTime(dur)
                progressBar.progress = dur > 0 ? CGFloat(pos / dur) : 0.0
                statusLabel.isHidden = true; eqView.isHidden = false; artImageView.isHidden = false; trackLabel.isHidden = false; artistLabel.isHidden = false; progressBar.isHidden = false; currTimeLabel.isHidden = false; durTimeLabel.isHidden = false; prevBtn.isHidden = false; playBtn.isHidden = false; nextBtn.isHidden = false
                if p[2] != currentArtUrl && !p[2].isEmpty { currentArtUrl = p[2]; loadArtwork(from: p[2]) }
            }
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

    @objc private func onPrev() { _ = runScript("tell application \"Spotify\" to previous track"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.updateSpotifyInfo() } }
    @objc private func onPlayPause() { _ = runScript("tell application \"Spotify\" to playpause"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.updateSpotifyInfo() } }
    @objc private func onNext() { _ = runScript("tell application \"Spotify\" to next track"); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.updateSpotifyInfo() } }

    private func listenForThemeChanges() {
        NotificationCenter.default.addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
    }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let p = ThemeManager.shared.currentPreset
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            self.layer?.cornerRadius = p.cornerRadius
            self.layer?.borderColor = NSColor.clear.cgColor
            self.layer?.borderWidth = 0
            self.artImageView.layer?.cornerRadius = 0.0
            self.artImageView.layer?.borderColor = p.borderColor.cgColor
            self.artImageView.layer?.borderWidth = p.borderWidth
            for btn in [self.prevBtn, self.playBtn, self.nextBtn] {
                btn.layer?.cornerRadius = p.cornerRadius / 2
                btn.layer?.backgroundColor = p.accentColor.cgColor
                btn.layer?.borderColor = p.borderColor.cgColor
                btn.layer?.borderWidth = p.borderWidth
                btn.font = p.font(size: 12, weight: .bold)
            }
            self.updateThemeRecursively(preset: p)
            CATransaction.commit()
            self.needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) { dragStart = NSEvent.mouseLocation; if let w = window { initialWinOrigin = w.frame.origin }; dragActive = true; window?.makeKey() }
    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { return }
        let c = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: initialWinOrigin.x + (c.x - dragStart.x), y: initialWinOrigin.y + (c.y - dragStart.y)))
    }
    override func mouseUp(with event: NSEvent) {
        dragActive = false
        if let w = window { PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin) }
    }
}

// MARK: - 8. ROBLOX DANCE TRANSPARENT GIF WIDGET (tutugif)
class GifView: NSView {
    let widgetKey = "gif"
    private let imageView = NSImageView()
    private var dragStart: NSPoint = .zero, initialWinOrigin: NSPoint = .zero
    private var dragMoved = false

    override init(frame: NSRect) { super.init(frame: frame); build(); loadGif() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.isOpaque = false; layer?.backgroundColor = NSColor.clear.cgColor
        imageView.wantsLayer = true; imageView.layer?.isOpaque = false; imageView.layer?.backgroundColor = NSColor.clear.cgColor
        imageView.animates = false; imageView.canDrawSubviewsIntoLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown; imageView.imageAlignment = .alignCenter
        addSubview(imageView)
    }

    override func layout() { super.layout(); imageView.frame = bounds }

    private func loadGif() {
        let dir = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("CustomERGifs")
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
           let firstGif = files.filter({ $0.pathExtension.lowercased() == "gif" }).first,
           let img = NSImage(contentsOf: firstGif) {
            imageView.image = img
            imageView.animates = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        if let w = window { initialWinOrigin = w.frame.origin }
        dragMoved = false
        window?.makeKey()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let w = window else { return }
        let c = NSEvent.mouseLocation
        let dx = c.x - dragStart.x, dy = c.y - dragStart.y
        if abs(dx) > 2 || abs(dy) > 2 {
            dragMoved = true
            w.setFrameOrigin(NSPoint(x: initialWinOrigin.x + dx, y: initialWinOrigin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !dragMoved {
            imageView.animates.toggle()
        } else {
            if let w = window { PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin) }
        }
    }
}



// MARK: - 10. ONLINE GMAIL / MAIL UNREAD WIDGET (tutumail)
struct GmailEntry {
    var title: String = ""
    var summary: String = ""
    var authorName: String = ""
    var authorEmail: String = ""
}

class GmailAtomParser: NSObject, XMLParserDelegate {
    var fullCount: Int = 0
    var entries: [GmailEntry] = []
    
    private var currentElement = ""
    private var currentTitle = ""
    private var currentSummary = ""
    private var currentAuthorName = ""
    private var currentAuthorEmail = ""
    private var inEntry = false
    private var inAuthor = false

    func parse(xmlData: Data) {
        let parser = XMLParser(data: xmlData)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "entry" {
            inEntry = true; currentTitle = ""; currentSummary = ""; currentAuthorName = ""; currentAuthorEmail = ""
        } else if elementName == "author" {
            inAuthor = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let str = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return }
        if !inEntry && currentElement == "fullcount" {
            fullCount = Int(str) ?? 0
        } else if inEntry {
            if currentElement == "title" {
                currentTitle += string
            } else if currentElement == "summary" {
                currentSummary += string
            } else if inAuthor {
                if currentElement == "name" { currentAuthorName += string }
                else if currentElement == "email" { currentAuthorEmail += string }
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?) {
        if elementName == "entry" {
            inEntry = false
            entries.append(GmailEntry(title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                      summary: currentSummary.trimmingCharacters(in: .whitespacesAndNewlines),
                                      authorName: currentAuthorName.trimmingCharacters(in: .whitespacesAndNewlines),
                                      authorEmail: currentAuthorEmail.trimmingCharacters(in: .whitespacesAndNewlines)))
        } else if elementName == "author" {
            inAuthor = false
        }
    }
}

class MailView: NSView {
    let widgetKey = "mail"
    private let titleLabel    = NSTextField()
    private let badgeLabel    = NSTextField()
    private let cardView      = NSView()
    private let countNumLabel = NSTextField()
    private let senderLabel   = NSTextField()
    private let subjectLabel  = NSTextField()

    private var timer: Timer?
    private var dragStart: NSPoint = .zero, initialWinOrigin: NSPoint = .zero, dragActive = false

    override init(frame: NSRect) { super.init(frame: frame); build(); updateMail(); startTimer(); listenForThemeChanges() }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true; layer?.cornerRadius = kRadius; layer?.borderWidth = 0; layer?.borderColor = NSColor.clear.cgColor
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor

        titleLabel.stringValue = "GMAIL"
        titleLabel.font = dynamicFont(size: 13, weight: .bold); titleLabel.textColor = kText
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        badgeLabel.stringValue = "0 UNREAD"
        badgeLabel.font = dynamicFont(size: 10, weight: .bold); badgeLabel.textColor = kDim; badgeLabel.alignment = .right
        badgeLabel.isEditable = false; badgeLabel.isBordered = false; badgeLabel.backgroundColor = .clear
        addSubview(badgeLabel)

        cardView.wantsLayer = true; cardView.layer?.cornerRadius = kRadius / 2; cardView.layer?.backgroundColor = kSurface.cgColor
        cardView.layer?.borderWidth = kBorderWidth; cardView.layer?.borderColor = kBorder.cgColor; addSubview(cardView)

        countNumLabel.stringValue = "0"
        countNumLabel.font = dynamicFont(size: 22, weight: .bold); countNumLabel.textColor = kText; countNumLabel.alignment = .center
        countNumLabel.isEditable = false; countNumLabel.isBordered = false; countNumLabel.backgroundColor = .clear; cardView.addSubview(countNumLabel)

        senderLabel.stringValue = "Double-click to set Gmail"
        senderLabel.font = dynamicFont(size: 11, weight: .bold); senderLabel.textColor = kText; senderLabel.lineBreakMode = .byTruncatingTail
        senderLabel.isEditable = false; senderLabel.isBordered = false; senderLabel.backgroundColor = .clear; cardView.addSubview(senderLabel)

        subjectLabel.stringValue = "Or open Apple Mail"
        subjectLabel.font = dynamicFont(size: 10, weight: .medium); subjectLabel.textColor = kDim; subjectLabel.lineBreakMode = .byTruncatingTail
        subjectLabel.isEditable = false; subjectLabel.isBordered = false; subjectLabel.backgroundColor = .clear; cardView.addSubview(subjectLabel)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleLabel.frame = NSRect(x: 12, y: h - 28, width: 100, height: 18)
        badgeLabel.frame = NSRect(x: w - 120, y: h - 28, width: 108, height: 18)

        cardView.frame   = NSRect(x: 12, y: 12, width: w - 24, height: 58)
        countNumLabel.frame = NSRect(x: 8, y: 14, width: 44, height: 30)
        senderLabel.frame   = NSRect(x: 58, y: 30, width: w - 90, height: 16)
        subjectLabel.frame  = NSRect(x: 58, y: 12, width: w - 90, height: 16)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in self?.updateMail() }
    }

    private func getGmailCredentials() -> (email: String, pass: String)? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CustomER/gmail.json")
        if let data = try? Data(contentsOf: path),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let u = json["email"], !u.isEmpty,
           let p = json["app_password"], !p.isEmpty {
            return (u, p)
        }
        return nil
    }

    private func updateMail() {
        guard let creds = getGmailCredentials() else {
            countNumLabel.stringValue = "0"
            badgeLabel.stringValue = "0 UNREAD"
            senderLabel.stringValue = "Double-click to set Gmail"
            subjectLabel.stringValue = "Online Gmail Sync"
            return
        }
        fetchGmailOnline(user: creds.email, pass: creds.pass)
    }

    private func fetchGmailOnline(user: String, pass: String) {
        guard let url = URL(string: "https://mail.google.com/mail/feed/atom") else { return }
        let loginStr = "\(user):\(pass)"
        guard let loginData = loginStr.data(using: .utf8) else { return }
        let base64Login = loginData.base64EncodedString()

        var req = URLRequest(url: url)
        req.setValue("Basic \(base64Login)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }
            let parser = GmailAtomParser()
            parser.parse(xmlData: data)

            DispatchQueue.main.async {
                let count = parser.fullCount
                self?.countNumLabel.stringValue = "\(count)"
                self?.badgeLabel.stringValue = "\(count) UNREAD"
                if let first = parser.entries.first {
                    let sender = first.authorName.isEmpty ? (first.authorEmail.isEmpty ? "Gmail Sender" : first.authorEmail) : first.authorName
                    let subject = !first.title.isEmpty ? first.title : (!first.summary.isEmpty ? first.summary : "(No Subject)")
                    self?.senderLabel.stringValue = sender
                    self?.subjectLabel.stringValue = subject
                } else if count > 0 {
                    self?.senderLabel.stringValue = "Unread Email"
                    self?.subjectLabel.stringValue = "Check Gmail Inbox"
                } else {
                    self?.senderLabel.stringValue = "No unread mail"
                    self?.subjectLabel.stringValue = "All caught up!"
                }
            }
        }.resume()
    }

    private func listenForThemeChanges() {
        NotificationCenter.default.addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
    }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let p = ThemeManager.shared.currentPreset
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            self.layer?.cornerRadius = p.cornerRadius
            self.layer?.borderColor = NSColor.clear.cgColor
            self.layer?.borderWidth = 0
            self.cardView.layer?.cornerRadius = p.cornerRadius / 2
            self.cardView.layer?.backgroundColor = p.surfaceColor.cgColor
            self.cardView.layer?.borderColor = p.borderColor.cgColor
            self.cardView.layer?.borderWidth = p.borderWidth
            self.updateThemeRecursively(preset: p)
            CATransaction.commit()
            self.needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        if let w = window { initialWinOrigin = w.frame.origin }
        dragActive = true; window?.makeKey()
        if event.clickCount == 2 {
            if let url = URL(string: "https://mail.google.com") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { return }
        let c = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: initialWinOrigin.x + (c.x - dragStart.x), y: initialWinOrigin.y + (c.y - dragStart.y)))
    }
    override func mouseUp(with event: NSEvent) {
        dragActive = false
        if let w = window { PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin) }
    }
}

// MARK: - 12. TIMETABLE WIDGET (tutotimetable - Native Vector Grid)
class TimetableWidgetView: NSView {
    let widgetKey = "timetable"
    private let titleLabel = NSTextField()
    private let cardView   = NSView()
    private var dragStart: NSPoint = .zero, initialWinOrigin: NSPoint = .zero, dragActive = false

    private let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    private let headers = ["Day", "8.00-9.00", "9.00-10.00", "Break", "10.30-11.30", "11.30-12.30", "Lunch", "1.15-2.15", "2.15-3.15"]

    // Schedule items: (startCol, span, subjectCode)
    private let schedule: [String: [(startCol: Int, span: Int, code: String)]] = [
        "Monday":    [(1, 1, "DBMS"), (2, 1, "SE"), (4, 2, "GTA"), (7, 2, "DBMS LAB")],
        "Tuesday":   [(1, 2, "DA"), (4, 1, "ML"), (5, 1, "DBMS")],
        "Wednesday": [(1, 1, "SE"), (2, 1, "DBMS"), (4, 1, "SE"), (5, 1, "ML")],
        "Thursday":  [(1, 2, "GTA"), (4, 1, "DBMS"), (5, 1, "SE"), (7, 2, "ML LAB")],
        "Friday":    [(1, 2, "ML"), (4, 2, "DA")]
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        listenForThemeChanges()
        setupDailyRefresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupDailyRefresh() {
        // 1. Midnight day change system notification
        NotificationCenter.default.addObserver(self, selector: #selector(onDayChanged), name: .NSCalendarDayChanged, object: nil)
        
        // 2. Opening/waking laptop lid from sleep system notification
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(onDayChanged), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func onDayChanged() {
        DispatchQueue.main.async {
            self.renderGrid()
        }
    }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = kRadius
        layer?.borderWidth = kBorderWidth
        layer?.borderColor = kBorder.cgColor
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor

        titleLabel.stringValue = "TIMETABLE"
        titleLabel.font = dynamicFont(size: 13, weight: .bold)
        titleLabel.textColor = kText
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = kRadius / 2
        cardView.layer?.backgroundColor = kSurface.cgColor
        cardView.layer?.borderWidth = kBorderWidth
        cardView.layer?.borderColor = kBorder.cgColor
        addSubview(cardView)

        renderGrid()
    }

    private func getMergedItems(for dayName: String) -> [(startCol: Int, span: Int, code: String)] {
        guard let items = schedule[dayName] else { return [] }
        var result: [(startCol: Int, span: Int, code: String)] = []
        for item in items {
            if let last = result.last, last.code == item.code, last.startCol + last.span == item.startCol {
                result[result.count - 1].span += item.span
            } else {
                result.append(item)
            }
        }
        return result
    }

    private func colorForSubject(_ code: String) -> NSColor {
        let isDark = ThemeManager.shared.currentPreset.name.lowercased().contains("dark") ||
                     ThemeManager.shared.currentPreset.name.lowercased().contains("cyber") ||
                     ThemeManager.shared.currentPreset.name.lowercased().contains("midnight")

        switch code.uppercased() {
        case "DBMS":
            return isDark ? NSColor(srgbRed: 0.22, green: 0.28, blue: 0.45, alpha: 0.9) : NSColor(srgbRed: 0.85, green: 0.88, blue: 0.98, alpha: 0.85)
        case "SE":
            return isDark ? NSColor(srgbRed: 0.18, green: 0.38, blue: 0.26, alpha: 0.9) : NSColor(srgbRed: 0.84, green: 0.93, blue: 0.86, alpha: 0.85)
        case "ML":
            return isDark ? NSColor(srgbRed: 0.35, green: 0.22, blue: 0.48, alpha: 0.9) : NSColor(srgbRed: 0.92, green: 0.86, blue: 0.98, alpha: 0.85)
        case "DA":
            return isDark ? NSColor(srgbRed: 0.45, green: 0.35, blue: 0.18, alpha: 0.9) : NSColor(srgbRed: 0.98, green: 0.91, blue: 0.78, alpha: 0.85)
        case "GTA":
            return isDark ? NSColor(srgbRed: 0.45, green: 0.22, blue: 0.26, alpha: 0.9) : NSColor(srgbRed: 0.98, green: 0.85, blue: 0.87, alpha: 0.85)
        case "DBMS LAB":
            return isDark ? NSColor(srgbRed: 0.18, green: 0.38, blue: 0.45, alpha: 0.9) : NSColor(srgbRed: 0.82, green: 0.92, blue: 0.98, alpha: 0.85)
        case "ML LAB":
            return isDark ? NSColor(srgbRed: 0.45, green: 0.18, blue: 0.38, alpha: 0.9) : NSColor(srgbRed: 0.97, green: 0.84, blue: 0.92, alpha: 0.85)
        default:
            return isDark ? kSurface.withAlphaComponent(0.6) : kBg.withAlphaComponent(0.45)
        }
    }

    private func renderGrid() {
        cardView.subviews.forEach { $0.removeFromSuperview() }

        let boundsW = cardView.bounds.width > 0 ? cardView.bounds.width : 500
        let boundsH = cardView.bounds.height > 0 ? cardView.bounds.height : 184

        let numRows: CGFloat = 6
        let rowH = boundsH / numRows

        let weights: [CGFloat] = [1.0, 1.0, 1.0, 0.30, 1.0, 1.0, 0.30, 1.0, 1.0]
        let totalWeight = weights.reduce(0, +)
        var colX: [CGFloat] = [0]
        for w in weights {
            colX.append(colX.last! + (w / totalWeight) * boundsW)
        }

        let todayName = getTodayName()

        // 1. Draw Header Row
        for (i, hText) in headers.enumerated() {
            let cellX = colX[i]
            let cellW = colX[i+1] - cellX
            let y = boundsH - rowH

            var displayStr = hText
            if hText == "Break" && cellW < 35 { displayStr = "B" }
            if hText == "Lunch" && cellW < 35 { displayStr = "L" }

            let label = createLabel(text: displayStr, size: 9.0, weight: .bold, color: kText, align: .center)
            label.frame = NSRect(x: cellX, y: y + (rowH - 18)/2, width: cellW, height: 18)
            cardView.addSubview(label)
        }

        // Horizontal line under header
        let hDiv = NSView(frame: NSRect(x: 0, y: boundsH - rowH, width: boundsW, height: 1))
        hDiv.wantsLayer = true
        hDiv.layer?.backgroundColor = kBorder.cgColor
        cardView.addSubview(hDiv)

        // 2. Draw Breaks (Short Break col 3 & Lunch Break col 6)
        let breakCols = [3, 6]
        for colIdx in breakCols {
            let bx1 = colX[colIdx]
            let bw = colX[colIdx + 1] - bx1
            let breakBg = NSView(frame: NSRect(x: bx1, y: 0, width: bw, height: boundsH - rowH))
            breakBg.wantsLayer = true
            breakBg.layer?.backgroundColor = kDim.withAlphaComponent(0.08).cgColor
            cardView.addSubview(breakBg)
        }

        // 3. Draw Days and Classes
        for (rowIdx, dayName) in days.enumerated() {
            let y = boundsH - CGFloat(rowIdx + 2) * rowH
            let isToday = (dayName == todayName)

            if isToday {
                let rowHighlight = NSView(frame: NSRect(x: 0, y: y, width: boundsW, height: rowH))
                rowHighlight.wantsLayer = true
                rowHighlight.layer?.backgroundColor = kAccent.withAlphaComponent(0.15).cgColor
                cardView.addSubview(rowHighlight)
            }

            let dayX = colX[0]
            let dayW = colX[1] - dayX
            let dLabel = createLabel(text: dayName, size: 10, weight: isToday ? .black : .bold, color: isToday ? kAccent : kText, align: .center)
            dLabel.frame = NSRect(x: dayX + 2, y: y + (rowH - 16)/2, width: dayW - 4, height: 16)
            cardView.addSubview(dLabel)

            let items = getMergedItems(for: dayName)
            for item in items {
                let cx1 = colX[item.startCol]
                let cx2 = colX[item.startCol + item.span]
                let cw = cx2 - cx1

                let cellBox = NSView(frame: NSRect(x: cx1 + 2, y: y + 2, width: cw - 4, height: rowH - 4))
                cellBox.wantsLayer = true
                cellBox.layer?.cornerRadius = 4.0
                cellBox.layer?.borderWidth = 1.0
                cellBox.layer?.borderColor = kBorder.withAlphaComponent(0.5).cgColor
                cellBox.layer?.backgroundColor = colorForSubject(item.code).cgColor

                let cLabel = createLabel(text: item.code, size: item.span > 1 ? 11 : 10, weight: .bold, color: kText, align: .center)
                cLabel.frame = NSRect(x: 0, y: (rowH - 4 - 16)/2, width: cw - 4, height: 16)
                cellBox.addSubview(cLabel)

                cardView.addSubview(cellBox)
            }

            if rowIdx < days.count - 1 {
                let rDiv = NSView(frame: NSRect(x: 0, y: y, width: boundsW, height: 1))
                rDiv.wantsLayer = true
                rDiv.layer?.backgroundColor = kBorder.withAlphaComponent(0.20).cgColor
                cardView.addSubview(rDiv)
            }
        }
    }

    private func createLabel(text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, align: NSTextAlignment) -> NSTextField {
        let tf = NSTextField()
        tf.stringValue = text
        tf.font = dynamicFont(size: size, weight: weight)
        tf.textColor = color
        tf.alignment = align
        tf.isEditable = false
        tf.isBordered = false
        tf.backgroundColor = .clear
        tf.cell?.usesSingleLineMode = true
        tf.cell?.lineBreakMode = .byClipping
        return tf
    }

    private func getTodayName() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE"
        return fmt.string(from: Date())
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleLabel.frame = NSRect(x: 14, y: h - 26, width: 200, height: 18)
        cardView.frame   = NSRect(x: 10, y: 10, width: w - 20, height: h - 36)
        renderGrid()
    }

    private func listenForThemeChanges() {
        NotificationCenter.default.addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
    }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let p = ThemeManager.shared.currentPreset
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            self.layer?.cornerRadius = p.cornerRadius
            self.layer?.borderColor = NSColor.clear.cgColor
            self.layer?.borderWidth = 0
            self.cardView.layer?.cornerRadius = p.cornerRadius / 2
            self.cardView.layer?.backgroundColor = p.surfaceColor.cgColor
            self.cardView.layer?.borderColor = p.borderColor.cgColor
            self.cardView.layer?.borderWidth = p.borderWidth
            self.titleLabel.textColor = p.textColor
            self.renderGrid()
            CATransaction.commit()
            self.needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) { dragStart = NSEvent.mouseLocation; if let w = window { initialWinOrigin = w.frame.origin }; dragActive = true; window?.makeKey() }
    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { return }
        let c = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: initialWinOrigin.x + (c.x - dragStart.x), y: initialWinOrigin.y + (c.y - dragStart.y)))
    }
    override func mouseUp(with event: NSEvent) {
        dragActive = false
        if let w = window { PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin) }
    }
}

// MARK: - CENTER WALLPAPER EXPANSION TRANSITION MANAGER
class CenterWallpaperTransitionManager {
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
            let win = NSWindow(contentRect: screenFrame,
                               styleMask: [.borderless],
                               backing: .buffered,
                               defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            win.ignoresMouseEvents = true

            let iv = NSView(frame: screenFrame)
            iv.wantsLayer = true
            iv.layer?.contentsGravity = .resizeAspectFill
            win.contentView = iv

            self.transitionWindow = win
            self.transitionImageView = iv
        }

        guard let win = transitionWindow, let iv = transitionImageView else {
            isAnimating = false
            completion?()
            return
        }

        win.setFrame(screenFrame, display: false)

        let midX = screenFrame.midX
        let midY = screenFrame.midY
        let startW: CGFloat = 180
        let startH: CGFloat = 112
        let startFrame = NSRect(x: midX - startW / 2, y: midY - startH / 2, width: startW, height: startH)

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

        // Close picker window right as center expand begins
        completion?()

        // 1. Smoothly expand center card from screen middle to full screen (0.35s).
        // Native wallpaper set is NOT called yet, so desktop underneath remains 100% static.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            iv.animator().frame = screenFrame
            iv.animator().layer?.cornerRadius = 0
            iv.animator().layer?.borderWidth = 0
            iv.animator().alphaValue = 1.0
        }, completionHandler: {
            // 2. NOW that overlay covers 100% of the screen, set native desktop wallpaper underneath
            self.setNativeWallpaper(url: url) {
                // Give WindowServer 1.40s to complete compositing native desktop
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.40) {
                    // 3. Slowly & smoothly cross-fade overlay out (0.65s) to reveal updated native desktop
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

// MARK: - 13. WALLPAPER SWITCHER WIDGET (tutuwallpaper)
class WallpaperPickerView: NSView {
    let widgetKey = "wallpaper_switcher"

    private let titleLabel       = NSTextField()
    private let pathLabel        = NSTextField()
    private let chooseFolderBtn  = NSButton()
    private let randomBtn        = NSButton()

    private let scrollView       = NSScrollView()
    private let contentView      = NSView()

    private var wallpaperFolderURL: URL = {
        if let savedPath = UserDefaults.standard.string(forKey: "customER_wallpaper_folder"),
           FileManager.default.fileExists(atPath: savedPath) {
            return URL(fileURLWithPath: savedPath)
        }
        let mywallURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/mywall")
        if FileManager.default.fileExists(atPath: mywallURL.path) {
            return mywallURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
    }()

    private var imageURLs: [URL] = []
    private var activeWallpaperURL: URL?
    private let thumbnailCache = NSCache<NSURL, NSImage>()

    private var folderWatcher: DispatchSourceFileSystemObject?
    private var folderFD: Int32 = -1

    private var dragStart: NSPoint = .zero, initialWinOrigin: NSPoint = .zero, dragActive = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        loadWallpapers()
        listenForThemeChanges()
        startWatchingFolder()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        stopWatchingFolder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow != nil {
            loadWallpapers()
        }
    }

    private func startWatchingFolder() {
        stopWatchingFolder()
        let path = wallpaperFolderURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        folderFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .link, .rename, .revoke], queue: .main)
        source.setEventHandler { [weak self] in
            self?.loadWallpapers()
        }
        source.setCancelHandler {
            close(fd)
        }
        folderWatcher = source
        source.resume()
    }

    private func stopWatchingFolder() {
        folderWatcher?.cancel()
        folderWatcher = nil
        if folderFD >= 0 {
            close(folderFD)
            folderFD = -1
        }
    }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = kRadius
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor

        titleLabel.stringValue = "WALLPAPER SWITCHER"
        titleLabel.font = dynamicFont(size: 13, weight: .bold)
        titleLabel.textColor = kText
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        pathLabel.stringValue = ""
        pathLabel.font = dynamicFont(size: 10, weight: .bold)
        pathLabel.textColor = kDim
        pathLabel.alignment = .right
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.isEditable = false; pathLabel.isBordered = false; pathLabel.backgroundColor = .clear
        addSubview(pathLabel)

        setupBtn(chooseFolderBtn, title: "Choose Folder", action: #selector(onChooseFolder))
        setupBtn(randomBtn, title: "Random Wallpaper", action: #selector(onRandomWallpaper))

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = kRadius / 2
        scrollView.layer?.backgroundColor = kSurface.cgColor
        scrollView.layer?.borderWidth = kBorderWidth
        scrollView.layer?.borderColor = kBorder.cgColor

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.documentView = contentView
        addSubview(scrollView)
    }

    private func setupBtn(_ btn: NSButton, title: String, action: Selector) {
        btn.title = title
        btn.font = dynamicFont(size: 10, weight: .bold)
        btn.isBordered = false; btn.wantsLayer = true; btn.layer?.cornerRadius = kRadius / 2
        btn.layer?.backgroundColor = kAccent.cgColor; btn.layer?.borderWidth = kBorderWidth; btn.layer?.borderColor = kBorder.cgColor
        btn.contentTintColor = (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish) ? .white : kSurface
        btn.target = self; btn.action = action; addSubview(btn)
    }

    private var lastRenderedBoundsSize: NSSize = .zero
    private var lastRenderedURLsCount: Int = 0

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleLabel.frame = NSRect(x: 12, y: h - 28, width: 180, height: 18)
        pathLabel.frame = NSRect(x: 200, y: h - 28, width: w - 212, height: 18)

        let btnW: CGFloat = 125, btnH: CGFloat = 24
        chooseFolderBtn.frame = NSRect(x: 12, y: h - 58, width: btnW, height: btnH)
        randomBtn.frame = NSRect(x: 12 + btnW + 8, y: h - 58, width: 135, height: btnH)

        let scrollY: CGFloat = 12
        let scrollH = h - 58 - 12 - 8
        scrollView.frame = NSRect(x: 12, y: scrollY, width: w - 24, height: scrollH)

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
            let r = idx / cols
            let c = idx % cols
            let x = gap + CGFloat(c) * (itemW + gap)
            let y = contentH - CGFloat(r + 1) * (itemH + gap)

            let card = NSButton(frame: NSRect(x: x, y: y, width: itemW, height: itemH))
            card.title = ""
            card.isBordered = false; card.wantsLayer = true; card.layer?.cornerRadius = kRadius / 2
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
                activeBadge.stringValue = "ACTIVE"
                activeBadge.font = dynamicFont(size: 8, weight: .bold)
                activeBadge.textColor = .white; activeBadge.alignment = .center
                activeBadge.isEditable = false; activeBadge.isBordered = false; activeBadge.wantsLayer = true
                activeBadge.layer?.cornerRadius = 3; activeBadge.layer?.backgroundColor = kAccent.cgColor
                card.addSubview(activeBadge)
            }

            card.tag = idx
            card.target = self
            card.action = #selector(onWallpaperSelected(_:))
            contentView.addSubview(card)
        }
    }

    @objc private func onWallpaperSelected(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < imageURLs.count else { return }
        let url = imageURLs[sender.tag]
        activeWallpaperURL = url
        let win = self.window
        CenterWallpaperTransitionManager.shared.animateAndSetWallpaper(url: url) {
            win?.orderOut(nil)
        }
    }

    @objc private func onChooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Wallpaper Folder"
        panel.directoryURL = wallpaperFolderURL

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
        let randomIndex = Int.random(in: 0..<imageURLs.count)
        let targetURL = imageURLs[randomIndex]
        activeWallpaperURL = targetURL
        let win = self.window
        CenterWallpaperTransitionManager.shared.animateAndSetWallpaper(url: targetURL) { [weak self] in
            win?.orderOut(nil)
            DispatchQueue.main.async {
                self?.renderGrid()
            }
        }
    }

    private func listenForThemeChanges() {
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
    }

    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let p = ThemeManager.shared.currentPreset
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            self.layer?.cornerRadius = p.cornerRadius
            self.layer?.borderColor = NSColor.clear.cgColor
            self.layer?.borderWidth = 0
            self.scrollView.layer?.cornerRadius = p.cornerRadius / 2
            self.scrollView.layer?.backgroundColor = p.surfaceColor.cgColor
            self.scrollView.layer?.borderColor = p.borderColor.cgColor
            self.scrollView.layer?.borderWidth = p.borderWidth
            for btn in [self.chooseFolderBtn, self.randomBtn] {
                btn.layer?.cornerRadius = p.cornerRadius / 2
                btn.layer?.backgroundColor = p.accentColor.cgColor
                btn.layer?.borderColor = p.borderColor.cgColor
                btn.layer?.borderWidth = p.borderWidth
            }
            self.updateThemeRecursively(preset: p)
            self.renderGrid()
            CATransaction.commit()
            self.needsDisplay = true
        }
    }
}

// MARK: - 14. FONT & COLOR CUSTOMIZER WIDGET (tutustyles - Option + E)
class ThemeCustomizerView: NSView {
    let widgetKey = "theme_customizer"

    private let titleLabel     = NSTextField()
    private let cardView       = NSView()

    private let fontPickerBtn  = NSButton()
    private let textWheelBtn   = NSButton()
    private let bgWheelBtn     = NSButton()
    private let bwBtn          = NSButton()
    private let resetBtn       = NSButton()

    private var dragStart: NSPoint = .zero, initialWinOrigin: NSPoint = .zero, dragActive = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        listenForThemeChanges()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = kRadius
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor
        layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor

        titleLabel.stringValue = "THEME CHANGER"
        titleLabel.font = dynamicFont(size: 11, weight: .bold)
        titleLabel.textColor = kText
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = kRadius / 2
        cardView.layer?.backgroundColor = kSurface.cgColor
        cardView.layer?.borderWidth = kBorderWidth
        cardView.layer?.borderColor = kBorder.cgColor
        addSubview(cardView)

        setupBtn(fontPickerBtn, title: "Font", action: #selector(openFontPicker))
        setupBtn(textWheelBtn, title: "Text Colour", action: #selector(openTextColorWheel))
        setupBtn(bgWheelBtn, title: "Widget Colour", action: #selector(openBgColorWheel))
        setupBtn(bwBtn, title: "Black and White", action: #selector(applyBlackAndWhite))
        setupBtn(resetBtn, title: "Reset", action: #selector(resetStyles))
    }

    private func setupBtn(_ btn: NSButton, title: String, action: Selector) {
        btn.title = title
        btn.font = dynamicFont(size: 10, weight: .bold)
        btn.isBordered = false; btn.wantsLayer = true; btn.layer?.cornerRadius = kRadius / 2
        btn.layer?.backgroundColor = kAccent.cgColor; btn.layer?.borderWidth = kBorderWidth; btn.layer?.borderColor = kBorder.cgColor
        btn.contentTintColor = kSurface
        btn.target = self; btn.action = action; cardView.addSubview(btn)
    }

    @objc private func openTextColorWheel() { ColorPanelDelegate.shared.openColorWheel(for: .text, initialColor: kText) }
    @objc private func openBgColorWheel() { ColorPanelDelegate.shared.openColorWheel(for: .bg, initialColor: kBg) }
    @objc private func openFontPicker() { FontPanelDelegate.shared.openFontPicker() }
    @objc private func applyBlackAndWhite() {
        ThemeManager.shared.customTextColor = NSColor.white
        ThemeManager.shared.customBgColor = NSColor.black
    }
    @objc private func resetStyles() { ThemeManager.shared.resetCustomStyles() }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        titleLabel.frame = NSRect(x: 14, y: h - 24, width: w - 28, height: 16)
        cardView.frame = NSRect(x: 12, y: 10, width: w - 24, height: h - 34)

        let rowH: CGFloat = 26
        let btnY = (cardView.bounds.height - rowH) / 2

        fontPickerBtn.frame = NSRect(x: 10,  y: btnY, width: 75,  height: rowH)
        textWheelBtn.frame  = NSRect(x: 90,  y: btnY, width: 95,  height: rowH)
        bgWheelBtn.frame    = NSRect(x: 190, y: btnY, width: 105, height: rowH)
        bwBtn.frame         = NSRect(x: 300, y: btnY, width: 110, height: rowH)
        resetBtn.frame      = NSRect(x: 415, y: btnY, width: 55,  height: rowH)
    }

    private func listenForThemeChanges() {
        NotificationCenter.default.addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(onThemeChanged), name: ThemeManager.notifName, object: nil)
    }
    @objc private func onThemeChanged() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let p = ThemeManager.shared.currentPreset
            self.layer?.backgroundColor = ThemeManager.shared.currentBgColor.cgColor
            self.layer?.cornerRadius = p.cornerRadius
            self.layer?.borderColor = NSColor.clear.cgColor
            self.layer?.borderWidth = 0
            self.cardView.layer?.cornerRadius = p.cornerRadius / 2
            self.cardView.layer?.backgroundColor = p.surfaceColor.cgColor
            self.cardView.layer?.borderColor = p.borderColor.cgColor
            self.cardView.layer?.borderWidth = p.borderWidth
            self.updateThemeRecursively(preset: p)
            CATransaction.commit()
            self.needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hitView = hitTest(point), hitView is NSButton {
            super.mouseDown(with: event)
            return
        }
        dragStart = NSEvent.mouseLocation
        if let w = window { initialWinOrigin = w.frame.origin }
        dragActive = true
        window?.makeKey()
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { return }
        let c = NSEvent.mouseLocation
        w.setFrameOrigin(NSPoint(x: initialWinOrigin.x + (c.x - dragStart.x), y: initialWinOrigin.y + (c.y - dragStart.y)))
    }

    override func mouseUp(with event: NSEvent) {
        dragActive = false
        if let w = window { PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin) }
    }
}

// MARK: - NOTCH EQUALIZER (White bars for dark notch)
class NotchEqualizerView: NSView {
    var isPlaying: Bool = false { didSet { isPlaying ? start() : stop() } }
    private var barHeights: [CGFloat] = [0.3, 0.6, 0.4, 0.8]
    private var animTimer: Timer?

    private func start() {
        guard animTimer == nil else { return }
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            self?.barHeights = (0..<4).map { _ in CGFloat.random(in: 0.2...1.0) }
            self?.needsDisplay = true
        }
    }
    private func stop() {
        animTimer?.invalidate(); animTimer = nil
        barHeights = [0.15, 0.15, 0.15, 0.15]
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let barCount = 4, gap: CGFloat = 2
        let barW = (bounds.width - CGFloat(barCount - 1) * gap) / CGFloat(barCount)
        let maxH = bounds.height
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        for i in 0..<barCount {
            let h = max(2.0, maxH * barHeights[i])
            let rect = CGRect(x: CGFloat(i) * (barW + gap), y: (maxH - h) / 2.0, width: barW, height: h)
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

// MARK: - NOTCH PROGRESS BAR
class NotchProgressView: NSView {
    var progress: CGFloat = 0.0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let trackRect = bounds.insetBy(dx: 0, dy: (bounds.height - 3) / 2)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        NSBezierPath(roundedRect: trackRect, xRadius: 1.5, yRadius: 1.5).fill()
        let fillW = max(0, min(bounds.width * progress, bounds.width))
        if fillW > 0 {
            let fillRect = NSRect(x: 0, y: trackRect.minY, width: fillW, height: trackRect.height)
            ctx.setFillColor(NSColor.white.cgColor)
            NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

// MARK: - BORINGNOTCH-STYLE WIDGET
class NotchWidgetWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class NotchWidgetView: NSView {
    let widgetKey = "notch"

    private enum State { case collapsed, expanded }
    private var state: State = .collapsed

    private let collapsedW: CGFloat = 210
    private let collapsedH: CGFloat = 34
    private let expandedW: CGFloat = 400
    private let expandedH: CGFloat = 130

    private let notchBlack = NSColor.black
    private let notchSurface = NSColor(hex: "#151D2A")!

    private let container = NSView()
    private let eqView = NotchEqualizerView()
    private let artView = NSImageView()
    private let trackLabel = NSTextField()
    private let artistLabel = NSTextField()
    private let prevBtn = NSButton()
    private let playBtn = NSButton()
    private let nextBtn = NSButton()
    private let progressBar = NotchProgressView()
    private let offlineLabel = NSTextField()

    private var spotifyTimer: Timer?
    private var currentArtUrl = ""
    private var isPlaying = false
    private var lastTrack = ""
    private var isOffline = true

    private var dragStartX: CGFloat = 0
    private var initialWinOrigin: NSPoint = .zero
    private var dragActive = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        startMonitoring()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // Container is the actual notch shape — always sits at the TOP of this view (flush with screen edge)
        container.wantsLayer = true
        container.layer?.backgroundColor = notchBlack.cgColor
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        addSubview(container)

        // Collapsed: tiny equalizer
        eqView.isHidden = false
        container.addSubview(eqView)

        // Expanded: album art
        artView.wantsLayer = true
        artView.layer?.cornerRadius = 10
        artView.layer?.masksToBounds = true
        artView.imageScaling = .scaleAxesIndependently
        container.addSubview(artView)

        // Track
        trackLabel.font = dynamicFont(size: 14, weight: .bold)
        trackLabel.textColor = .white
        trackLabel.isEditable = false
        trackLabel.isBordered = false
        trackLabel.backgroundColor = .clear
        trackLabel.lineBreakMode = .byTruncatingTail
        container.addSubview(trackLabel)

        // Artist
        artistLabel.font = dynamicFont(size: 11, weight: .medium)
        artistLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        artistLabel.isEditable = false
        artistLabel.isBordered = false
        artistLabel.backgroundColor = .clear
        artistLabel.lineBreakMode = .byTruncatingTail
        container.addSubview(artistLabel)

        // Offline label (shown when no Spotify)
        offlineLabel.stringValue = "Spotify Offline"
        offlineLabel.font = dynamicFont(size: 13, weight: .bold)
        offlineLabel.textColor = NSColor.white.withAlphaComponent(0.4)
        offlineLabel.alignment = .center
        offlineLabel.isEditable = false
        offlineLabel.isBordered = false
        offlineLabel.backgroundColor = .clear
        container.addSubview(offlineLabel)

        // Controls
        setupControlBtn(prevBtn, title: "⏮", action: #selector(onPrev))
        setupControlBtn(playBtn, title: "▶", action: #selector(onPlayPause))
        setupControlBtn(nextBtn, title: "⏭", action: #selector(onNext))

        // Progress
        progressBar.wantsLayer = true
        container.addSubview(progressBar)

        applyCollapsedLayout()
    }

    private func setupControlBtn(_ btn: NSButton, title: String, action: Selector) {
        btn.title = title
        btn.font = dynamicFont(size: 12, weight: .bold)
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        btn.contentTintColor = .white
        btn.target = self
        btn.action = action
        container.addSubview(btn)
    }

    // MARK: Layout
    private func applyCollapsedLayout() {
        let w = collapsedW, h = collapsedH
        // Container sits at the very TOP of this view (touching screen edge flush around notch)
        container.frame = NSRect(x: (bounds.width - w)/2, y: bounds.height - h, width: w, height: h)
        container.layer?.cornerRadius = 14.0

        eqView.isHidden = false
        eqView.frame = NSRect(x: (w - 40)/2, y: (h - 16)/2, width: 40, height: 16)

        artView.isHidden = true
        trackLabel.isHidden = true
        artistLabel.isHidden = true
        prevBtn.isHidden = true
        playBtn.isHidden = true
        nextBtn.isHidden = true
        progressBar.isHidden = true
        offlineLabel.isHidden = true
    }

    private func applyExpandedLayout() {
        let w = expandedW, h = expandedH
        container.frame = NSRect(x: (bounds.width - w)/2, y: bounds.height - h, width: w, height: h)
        container.layer?.cornerRadius = 24.0

        eqView.isHidden = true

        if isOffline {
            artView.isHidden = true
            trackLabel.isHidden = true
            artistLabel.isHidden = true
            prevBtn.isHidden = true
            playBtn.isHidden = true
            nextBtn.isHidden = true
            progressBar.isHidden = true
            offlineLabel.isHidden = false
            offlineLabel.frame = NSRect(x: 0, y: (h - 24)/2, width: w, height: 24)
            return
        }

        offlineLabel.isHidden = true

        let artSize: CGFloat = 72
        let margin: CGFloat = 18
        artView.isHidden = false
        artView.frame = NSRect(x: margin, y: (h - artSize)/2, width: artSize, height: artSize)

        let textX = artSize + margin + 12
        let textW = w - textX - margin
        trackLabel.isHidden = false
        trackLabel.frame = NSRect(x: textX, y: h - 58, width: textW, height: 22)
        artistLabel.isHidden = false
        artistLabel.frame = NSRect(x: textX, y: h - 80, width: textW, height: 16)

        progressBar.isHidden = false
        progressBar.frame = NSRect(x: textX, y: 52, width: textW, height: 4)

        let btnY: CGFloat = 16
        let btnH: CGFloat = 28
        prevBtn.isHidden = false
        playBtn.isHidden = false
        nextBtn.isHidden = false
        prevBtn.frame = NSRect(x: textX, y: btnY, width: 36, height: btnH)
        playBtn.frame = NSRect(x: textX + 44, y: btnY, width: 36, height: btnH)
        nextBtn.frame = NSRect(x: textX + 88, y: btnY, width: 36, height: btnH)
    }

    override func layout() {
        super.layout()
        if state == .collapsed {
            applyCollapsedLayout()
        } else {
            applyExpandedLayout()
        }
    }

    // MARK: Hit test — let clicks pass through empty areas
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: nil)
        let containerPoint = convert(local, to: container)
        if container.bounds.contains(containerPoint) {
            return super.hitTest(point)
        }
        return nil
    }

    // MARK: Spotify monitoring
    private func startMonitoring() {
        spotifyTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkSpotify()
        }
    }

    private func checkSpotify() {
        let sc = """
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing or player state is paused then
                    set trackName to name of current track
                    set artistName to artist of current track
                    set artUrl to artwork url of current track
                    set pState to (player state is playing)
                    set pPos to player position
                    set pDur to (duration of current track) / 1000.0
                    return trackName & "|||" & artistName & "|||" & artUrl & "|||" & pState & "|||" & pPos & "|||" & pDur
                end if
            end tell
        end if
        return "OFFLINE"
        """
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let res = runScript(sc)
            DispatchQueue.main.async { self?.handleResult(res) }
        }
    }

    private func handleResult(_ res: String) {
        if res == "OFFLINE" || res.isEmpty {
            let wasOffline = isOffline
            isOffline = true
            isPlaying = false
            eqView.isPlaying = false
            if state == .expanded && !wasOffline {
                applyExpandedLayout()
            }
            return
        }
        isOffline = false
        let p = res.components(separatedBy: "|||")
        guard p.count >= 6 else { return }

        let track = p[0]
        let artist = p[1]
        let artUrl = p[2]
        let playing = (p[3] == "true")
        let pos = Double(p[4]) ?? 0
        let dur = Double(p[5]) ?? 1

        isPlaying = playing
        playBtn.title = playing ? "⏸" : "▶"
        eqView.isPlaying = playing

        if track != lastTrack {
            lastTrack = track
            trackLabel.stringValue = track
            artistLabel.stringValue = artist
            if artUrl != currentArtUrl && !artUrl.isEmpty {
                currentArtUrl = artUrl
                loadArt(url: artUrl)
            }
            if state == .expanded { applyExpandedLayout() }
        }
        progressBar.progress = dur > 0 ? CGFloat(pos / dur) : 0
    }

    private func loadArt(url: String) {
        guard let u = URL(string: url) else { return }
        URLSession.shared.dataTask(with: u) { [weak self] data, _, _ in
            guard let data = data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.artView.image = img }
        }.resume()
    }

    // MARK: Animation
    private func animateTo(_ newState: State) {
        guard state != newState else { return }
        state = newState

        let isExpanded = (newState == .expanded)
        let targetW = isExpanded ? expandedW : collapsedW
        let targetH = isExpanded ? expandedH : collapsedH

        if let w = window, let screen = w.screen ?? NSScreen.main {
            let screenTop = screen.frame.maxY
            let currentCenterX = w.frame.midX
            let newFrame = NSRect(x: currentCenterX - targetW / 2.0, y: screenTop - targetH, width: targetW, height: targetH)

            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                w.animator().setFrame(newFrame, display: true)
                self.layout()
            }, completionHandler: {
                if self.state == .collapsed { self.applyCollapsedLayout() }
            })
        }
    }

    // MARK: Interaction (CLICK TO TOGGLE ENLARGE — NO HOVER)
    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if hitTest(pt) is NSButton {
            super.mouseDown(with: event)
            return
        }

        // Toggle state on click
        if state == .collapsed {
            animateTo(.expanded)
        } else {
            animateTo(.collapsed)
        }

        dragStartX = NSEvent.mouseLocation.x
        if let w = window { initialWinOrigin = w.frame.origin }
        dragActive = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let w = window else { return }
        let dx = NSEvent.mouseLocation.x - dragStartX
        // Lock to top of screen, only horizontal drag
        w.setFrameOrigin(NSPoint(x: initialWinOrigin.x + dx, y: w.frame.origin.y))
    }

    override func mouseUp(with event: NSEvent) {
        dragActive = false
        if let w = window {
            PositionManager.shared.savePosition(key: widgetKey, origin: w.frame.origin)
        }
    }

    @objc private func onPrev() {
        _ = runScript("tell application \"Spotify\" to previous track")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.checkSpotify() }
    }
    @objc private func onPlayPause() {
        _ = runScript("tell application \"Spotify\" to playpause")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.checkSpotify() }
    }
    @objc private func onNext() {
        _ = runScript("tell application \"Spotify\" to next track")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.checkSpotify() }
    }
}



class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var widgetWindows: [String: NSWindow] = [:]
    var wallpaperWindow: NSWindow?
    var themeCustomizerWindow: NSWindow?

    private var wallpaperHotKeyRef: EventHotKeyRef?
    private var themeHotKeyRef: EventHotKeyRef?
    private var desktopHotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register Distributed Notification IPC observer
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleIPCControlNotification(_:)),
            name: Notification.Name("com.user.CustomERApp.control"),
            object: nil
        )

        // Automatically hide floating customizer and wallpaper widgets when switching to any application
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Sync Desktop Folder Icons with Widget Theme asynchronously so launch completes instantly
        DispatchQueue.global(qos: .utility).async {
            FolderIconManager.updateDesktopFolderIcons(bgColor: ThemeManager.shared.currentBgColor)
        }

        // 1. Reminders (tututodo)
        let defaultTodoRect = NSRect(x: 5, y: 616, width: 280, height: 440)
        let todoOrigin = PositionManager.shared.getPosition(key: "reminders", defaultOrigin: defaultTodoRect.origin)
        let todoWin = addWindow(rect: NSRect(origin: todoOrigin, size: defaultTodoRect.size), view: TodoView(frame: NSRect(origin: todoOrigin, size: defaultTodoRect.size)))
        widgetWindows["reminders"] = todoWin

        // 2. Calendar
        let defaultCalRect = NSRect(x: 294, y: 331, width: 280, height: 230)
        let calOrigin = PositionManager.shared.getPosition(key: "calendar", defaultOrigin: defaultCalRect.origin)
        let calWin = addWindow(rect: NSRect(origin: calOrigin, size: defaultCalRect.size), view: CalendarView(frame: NSRect(origin: calOrigin, size: defaultCalRect.size)))
        widgetWindows["calendar"] = calWin

        // 3. Battery
        let defaultBatRect = NSRect(x: 6, y: 331, width: 280, height: 280)
        let batOrigin = PositionManager.shared.getPosition(key: "battery", defaultOrigin: defaultBatRect.origin)
        let batWin = addWindow(rect: NSRect(origin: batOrigin, size: defaultBatRect.size), view: BatteryView(frame: NSRect(origin: batOrigin, size: defaultBatRect.size)))
        widgetWindows["battery"] = batWin

        // 4. Digital Clock
        let defaultClockRect = NSRect(x: 294, y: 695, width: 280, height: 110)
        let clockOrigin = PositionManager.shared.getPosition(key: "digital_clock", defaultOrigin: defaultClockRect.origin)
        let clockWin = addWindow(rect: NSRect(origin: clockOrigin, size: defaultClockRect.size), view: DigitalClockView(frame: NSRect(origin: clockOrigin, size: defaultClockRect.size)))
        widgetWindows["digital_clock"] = clockWin

        // 7. Spotify Player
        let defaultSpotRect = NSRect(x: 716, y: 782, width: 280, height: 130)
        let spotOrigin = PositionManager.shared.getPosition(key: "spotify", defaultOrigin: defaultSpotRect.origin)
        let spotWin = addWindow(rect: NSRect(origin: spotOrigin, size: defaultSpotRect.size), view: SpotifyView(frame: NSRect(origin: spotOrigin, size: defaultSpotRect.size)))
        widgetWindows["spotify"] = spotWin

        // 8. Roblox Dance GIF
        let defaultGifRect = NSRect(x: 526, y: 861, width: 196, height: 196)
        let gifOrigin = PositionManager.shared.getPosition(key: "gif", defaultOrigin: defaultGifRect.origin)
        let gifWin = addWindow(rect: NSRect(origin: gifOrigin, size: defaultGifRect.size), view: GifView(frame: NSRect(origin: gifOrigin, size: defaultGifRect.size)))
        widgetWindows["gif"] = gifWin

        // 10. Apple Mail Unread Widget
        let defaultMailRect = NSRect(x: 293, y: 573, width: 280, height: 110)
        let mailOrigin = PositionManager.shared.getPosition(key: "mail", defaultOrigin: defaultMailRect.origin)
        let mailWin = addWindow(rect: NSRect(origin: mailOrigin, size: defaultMailRect.size), view: MailView(frame: NSRect(origin: mailOrigin, size: defaultMailRect.size)))
        widgetWindows["mail"] = mailWin

        // 11. Timetable Vector Widget (tutotimetable - Wide Format)
        let defaultTTRect = NSRect(x: 4, y: 103, width: 520, height: 220)
        let ttOrigin = PositionManager.shared.getPosition(key: "timetable", defaultOrigin: defaultTTRect.origin)
        let ttWin = addWindow(rect: NSRect(origin: ttOrigin, size: defaultTTRect.size), view: TimetableWidgetView(frame: NSRect(origin: ttOrigin, size: defaultTTRect.size)))
        ttWin.setContentSize(NSSize(width: 520, height: 220))
        widgetWindows["timetable"] = ttWin

        // 13. Wallpaper Switcher Widget (tutuwallpaper - Option + W)
        let defaultWallRect = NSRect(x: 269, y: 241, width: 680, height: 420)
        let wallOrigin = PositionManager.shared.getPosition(key: "wallpaper_switcher", defaultOrigin: defaultWallRect.origin)
        let wallWin = addWindow(rect: NSRect(origin: wallOrigin, size: defaultWallRect.size), view: WallpaperPickerView(frame: NSRect(origin: wallOrigin, size: defaultWallRect.size)))
        wallpaperWindow = wallWin
        widgetWindows["wallpaper_switcher"] = wallWin
        wallWin.orderOut(nil)

        // 14. Theme & Style Customizer Widget (tutustyles - Option + E)
        let defaultStyleRect = NSRect(x: 612, y: 540, width: 505, height: 75)
        let styleOrigin = PositionManager.shared.getPosition(key: "theme_customizer", defaultOrigin: defaultStyleRect.origin)
        let styleWin = addWindow(rect: NSRect(origin: styleOrigin, size: defaultStyleRect.size), view: ThemeCustomizerView(frame: NSRect(origin: styleOrigin, size: defaultStyleRect.size)))
        themeCustomizerWindow = styleWin
        widgetWindows["theme_customizer"] = styleWin
        styleWin.orderOut(nil)

        // 15. BoringNotch-style Spotify Notch Widget (Disabled by default - uncomment to activate)
        /*
        let notchCollapsedW: CGFloat = 210
        let notchCollapsedH: CGFloat = 34
        let screenTop = NSScreen.main?.frame.maxY ?? 900
        let defaultNotchOrigin = NSPoint(
            x: (NSScreen.main?.frame.midX ?? 600) - notchCollapsedW / 2,
            y: screenTop - notchCollapsedH
        )
        let notchOrigin = PositionManager.shared.getPosition(key: "notch", defaultOrigin: defaultNotchOrigin)

        let notchWin = NotchWidgetWindow(
            contentRect: NSRect(origin: notchOrigin, size: NSSize(width: notchCollapsedW, height: notchCollapsedH)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        notchWin.isOpaque = false
        notchWin.backgroundColor = .clear
        notchWin.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 1)
        notchWin.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        notchWin.hasShadow = false
        notchWin.ignoresMouseEvents = false

        let notchView = NotchWidgetView(frame: NSRect(origin: .zero, size: NSSize(width: notchCollapsedW, height: notchCollapsedH)))
        notchWin.contentView = notchView
        notchWin.makeKeyAndOrderFront(nil)
        widgetWindows["notch"] = notchWin
        windows.append(notchWin)
        */

        setupHotkeys()
    }

    @objc private func handleIPCControlNotification(_ notif: Notification) {
        guard let userInfo = notif.userInfo as? [String: String],
              let action = userInfo["action"] else { return }

        DispatchQueue.main.async {
            if action == "kill_app" {
                NSApp.terminate(nil)
                return
            } else if action == "hide_all" || action == "kill_all" || action == "close_all" {
                for win in self.widgetWindows.values {
                    win.orderOut(nil)
                }
                return
            } else if action == "show_all" || action == "open_all" {
                for (key, win) in self.widgetWindows {
                    if key != "wallpaper_switcher" && key != "theme_customizer" {
                        win.makeKeyAndOrderFront(nil)
                    }
                }
                return
            } else if action == "set_font" {
                if let fontName = userInfo["value"] {
                    ThemeManager.shared.customFontName = fontName
                }
                return
            } else if action == "set_text_color" {
                if let val = userInfo["value"], let col = NSColor(hex: val) {
                    ThemeManager.shared.customTextColor = col
                }
                return
            } else if action == "set_bg_color" {
                if let val = userInfo["value"], let col = NSColor(hex: val) {
                    ThemeManager.shared.customBgColor = col
                }
                return
            } else if action == "set_accent_color" {
                if let val = userInfo["value"], let col = NSColor(hex: val) {
                    ThemeManager.shared.customAccentColor = col
                }
                return
            } else if action == "reset_styles" {
                ThemeManager.shared.resetCustomStyles()
                return
            } else if action == "set_bw" || action == "black_and_white" {
                ThemeManager.shared.customTextColor = NSColor.white
                ThemeManager.shared.customBgColor = NSColor.black
                return
            } else if action == "open_color_picker" {
                ColorPanelDelegate.shared.openColorWheel(for: .text, initialColor: kText)
                return
            } else if action == "open_font_picker" {
                FontPanelDelegate.shared.openFontPicker()
                return
            }

            let rawWidgetKey = userInfo["widget"] ?? ""
            if rawWidgetKey.isEmpty || rawWidgetKey == "all" {
                if action == "hide" || action == "kill" || action == "close" {
                    for win in self.widgetWindows.values { win.orderOut(nil) }
                    return
                } else if action == "show" || action == "open" {
                    for win in self.widgetWindows.values { win.makeKeyAndOrderFront(nil) }
                    return
                }
            }

            let widgetKey = self.canonicalWidgetKey(rawWidgetKey)
            guard let win = self.widgetWindows[widgetKey] else { return }

            switch action {
            case "hide", "kill", "close":
                win.orderOut(nil)
            case "show", "open":
                win.makeKeyAndOrderFront(nil)
            case "toggle":
                if win.isVisible {
                    win.orderOut(nil)
                } else {
                    win.makeKeyAndOrderFront(nil)
                }
            default:
                break
            }
        }
    }

    private func canonicalWidgetKey(_ input: String) -> String {
        let key = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "todo", "reminders", "reminder": return "reminders"
        case "calendar", "cal": return "calendar"
        case "battery", "bat": return "battery"
        case "clock", "digital", "digital_clock": return "digital_clock"
        case "analog", "analog_clock": return "analog_clock"
        case "spotify", "music": return "spotify"
        case "gif", "roblox": return "gif"
        case "mail", "email": return "mail"
        case "timetable", "schedule": return "timetable"
        case "collage", "album", "album_collage": return "album_collage"
        case "wallpaper", "switcher", "wallpaper_switcher": return "wallpaper_switcher"
        case "theme", "styles", "style", "theme_customizer": return "theme_customizer"
        case "notch", "dynamic_island", "pill", "notch_widget": return "notch"
        default: return key
        }
    }

    private func setupHotkeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, userPtr) -> OSStatus in
            guard let ptr = userPtr, let event = eventRef else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async {
                if hkID.id == 1 {
                    appDelegate.toggleWallpaperWindow()
                } else if hkID.id == 2 {
                    appDelegate.toggleThemeCustomizerWindow()
                } else if hkID.id == 3 {
                    appDelegate.toggleDesktopIcons()
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        // Option + W (KeyCode 13) -> Wallpaper Switcher
        let wallHotKeyID = EventHotKeyID(signature: OSType(0x57414C4C), id: 1)
        RegisterEventHotKey(13, UInt32(optionKey), wallHotKeyID, GetApplicationEventTarget(), 0, &wallpaperHotKeyRef)

        // Option + E (KeyCode 14) -> Theme & Style Customizer
        let themeHotKeyID = EventHotKeyID(signature: OSType(0x5448454D), id: 2)
        RegisterEventHotKey(14, UInt32(optionKey), themeHotKeyID, GetApplicationEventTarget(), 0, &themeHotKeyRef)

        // Option + D (KeyCode 2) -> Toggle Desktop Icons & Folders
        let deskHotKeyID = EventHotKeyID(signature: OSType(0x4445534B), id: 3)
        RegisterEventHotKey(2, UInt32(optionKey), deskHotKeyID, GetApplicationEventTarget(), 0, &desktopHotKeyRef)
    }

    @objc func toggleDesktopIcons() {
        let current = UserDefaults(suiteName: "com.apple.finder")?.bool(forKey: "CreateDesktop") ?? true
        let nextVal = !current
        let p1 = Process()
        p1.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p1.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", nextVal ? "true" : "false"]
        try? p1.run()
        p1.waitUntilExit()

        let p2 = Process()
        p2.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p2.arguments = ["Finder"]
        try? p2.run()
    }

    func toggleWallpaperWindow() {
        guard let win = wallpaperWindow else { return }
        if win.isVisible {
            win.orderOut(nil)
        } else {
            if let activeApp = NSWorkspace.shared.frontmostApplication {
                let bundleID = activeApp.bundleIdentifier ?? ""
                let isDesktopActive = (bundleID == "com.apple.finder" || bundleID == "com.user.CustomERApp" || activeApp.processIdentifier == ProcessInfo.processInfo.processIdentifier)
                if !isDesktopActive { return }
            }
            win.level = .floating
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func toggleThemeCustomizerWindow() {
        guard let win = themeCustomizerWindow else { return }
        if win.isVisible {
            win.orderOut(nil)
        } else {
            if let activeApp = NSWorkspace.shared.frontmostApplication {
                let bundleID = activeApp.bundleIdentifier ?? ""
                let isDesktopActive = (bundleID == "com.apple.finder" || bundleID == "com.user.CustomERApp" || activeApp.processIdentifier == ProcessInfo.processInfo.processIdentifier)
                if !isDesktopActive { return }
            }
            win.level = .floating
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func activeAppDidChange(_ notif: Notification) {
        guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let bundleID = app.bundleIdentifier ?? ""
        let isDesktopActive = (bundleID == "com.apple.finder" || bundleID == "com.user.CustomERApp" || app.processIdentifier == ProcessInfo.processInfo.processIdentifier)
        if !isDesktopActive {
            wallpaperWindow?.orderOut(nil)
            themeCustomizerWindow?.orderOut(nil)
        }
    }

    @discardableResult
    private func addWindow(rect: NSRect, view: NSView) -> NSWindow {
        let win = MasterWidgetWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = NSWindow.Level(rawValue: -1)
        win.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        win.isMovableByWindowBackground = true
        win.hasShadow = false
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        windows.append(win)
        return win
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
