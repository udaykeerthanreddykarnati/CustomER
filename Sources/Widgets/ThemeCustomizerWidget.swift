import AppKit
import Foundation

// MARK: - 14. FONT & COLOR CUSTOMIZER WIDGET (Option + E)
class ThemeCustomizerView: BaseWidgetView {
    private let titleLabel    = NSTextField()
    private let cardView      = NSView()
    private let presetBtn     = NSButton()
    private let fontPickerBtn = NSButton()
    private let textWheelBtn  = NSButton()
    private let bgWheelBtn    = NSButton()
    private let bwBtn         = NSButton()
    private let resetBtn      = NSButton()

    init(frame: NSRect) {
        super.init(frame: frame, widgetKey: "theme_customizer")
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        titleLabel.stringValue = "THEME CHANGER"
        titleLabel.font = dynamicFont(size: 11, weight: .bold); titleLabel.textColor = kText
        titleLabel.isEditable = false; titleLabel.isBordered = false; titleLabel.backgroundColor = .clear
        addSubview(titleLabel)

        cardView.wantsLayer = true; cardView.layer?.cornerRadius = kRadius / 2
        cardView.layer?.backgroundColor = kSurface.cgColor; cardView.layer?.borderWidth = kBorderWidth; cardView.layer?.borderColor = kBorder.cgColor
        addSubview(cardView)

        setupBtn(presetBtn, title: ThemeManager.shared.currentPreset.name, action: #selector(cyclePreset))
        setupBtn(fontPickerBtn, title: "Font", action: #selector(openFontPicker))
        setupBtn(textWheelBtn, title: "Text Colour", action: #selector(openTextColorWheel))
        setupBtn(bgWheelBtn, title: "Widget Colour", action: #selector(openBgColorWheel))
        setupBtn(bwBtn, title: "B & W", action: #selector(applyBlackAndWhite))
        setupBtn(resetBtn, title: "Reset", action: #selector(resetStyles))
    }

    private func setupBtn(_ btn: NSButton, title: String, action: Selector) {
        btn.title = title; btn.font = dynamicFont(size: 10, weight: .bold); btn.isBordered = false; btn.wantsLayer = true; btn.tag = 100
        btn.layer?.cornerRadius = kRadius / 2; btn.layer?.backgroundColor = kAccent.cgColor
        btn.layer?.borderWidth = kBorderWidth; btn.layer?.borderColor = kBorder.cgColor
        btn.contentTintColor = (ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish) ? .white : kSurface
        btn.target = self; btn.action = action; cardView.addSubview(btn)
    }

    @objc private func cyclePreset() { ThemeManager.shared.cyclePreset() }
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
        presetBtn.frame     = NSRect(x: 8,   y: btnY, width: 72, height: rowH)
        fontPickerBtn.frame = NSRect(x: 85,  y: btnY, width: 54, height: rowH)
        textWheelBtn.frame  = NSRect(x: 144, y: btnY, width: 88, height: rowH)
        bgWheelBtn.frame    = NSRect(x: 237, y: btnY, width: 96, height: rowH)
        bwBtn.frame         = NSRect(x: 338, y: btnY, width: 56, height: rowH)
        resetBtn.frame      = NSRect(x: 399, y: btnY, width: 56, height: rowH)
    }

    override func applyTheme(preset: ThemePreset) {
        cardView.layer?.cornerRadius = preset.cornerRadius / 2
        cardView.layer?.backgroundColor = preset.surfaceColor.cgColor
        cardView.layer?.borderColor = preset.borderColor.cgColor
        cardView.layer?.borderWidth = preset.borderWidth
        presetBtn.title = preset.name
        for btn in [presetBtn, fontPickerBtn, textWheelBtn, bgWheelBtn, bwBtn, resetBtn] {
            btn.layer?.backgroundColor = kAccent.cgColor
            btn.layer?.borderColor = preset.borderColor.cgColor
            btn.layer?.borderWidth = preset.borderWidth
            btn.contentTintColor = (preset == .glass || preset == .childish) ? .white : kSurface
        }
        updateThemeRecursively(preset: preset)
    }
}
