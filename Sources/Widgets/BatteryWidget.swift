import AppKit
import Foundation
import IOBluetooth
import IOKit.ps

// MARK: - 3. BATTERY & BLUETOOTH WIDGET (Event-Driven Power + Throttled BT Profiling)
struct BTDeviceItem: Equatable {
    var name: String
    var singleBattery: Int?
    var leftBattery: Int?
    var rightBattery: Int?
    var caseBattery: Int?
    var isCharging: Bool

    var hasAnyBattery: Bool {
        singleBattery != nil || leftBattery != nil || rightBattery != nil || caseBattery != nil
    }

    var displayString: String {
        var parts: [String] = []
        if let l = leftBattery, l > 0 { parts.append("L:\(l)%") }
        if let r = rightBattery, r > 0 { parts.append("R:\(r)%") }
        if let c = caseBattery, c > 0 { parts.append("Case:\(c)%") }
        if parts.isEmpty {
            if let s = singleBattery, s > 0 {
                return "\(s)%"
            }
            return isCharging ? "CHARGING" : "N/A"
        }
        return parts.joined(separator: " ")
    }
}

class BatteryView: BaseWidgetView {
    private let macCard = NSView()
    private let macPctLabel = NSTextField()
    private let macStatusLabel = NSTextField()
    private let macProgressBar = NSView()
    private let macProgressFill = NSView()
    private let btHeaderLabel = NSTextField()
    private let btListContainer = NSView()

    private var btTimer: Timer?
    private var powerRunLoopSource: CFRunLoopSource?
    private var isFetching = false
    private var lastBTDevices: [BTDeviceItem] = []
    private var lastProfilerFetch: Date = .distantPast
    private var lastConnectedCount: Int = -1

    init(frame: NSRect) {
        super.init(frame: frame, widgetKey: "battery")
        build()
        setupPowerNotifications()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        btTimer?.invalidate()
        if let src = powerRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    private var lastBTContainerSize: NSSize = .zero

    private func build() {
        macCard.wantsLayer = true; macCard.layer?.cornerRadius = kRadius / 2; macCard.layer?.backgroundColor = kSurface.cgColor
        macCard.layer?.borderWidth = kBorderWidth; macCard.layer?.borderColor = kBorder.cgColor; addSubview(macCard)

        let pctCell = CenteredTextFieldCell(textCell: "100%")
        pctCell.alignment = .left; pctCell.font = dynamicFont(size: 30, weight: .bold); pctCell.textColor = kText
        pctCell.usesSingleLineMode = true; pctCell.lineBreakMode = .byClipping
        macPctLabel.cell = pctCell
        macPctLabel.isEditable = false; macPctLabel.isBordered = false; macPctLabel.drawsBackground = false; macPctLabel.backgroundColor = .clear
        macCard.addSubview(macPctLabel)

        let statusCell = CenteredTextFieldCell(textCell: "")
        statusCell.alignment = .center; statusCell.font = dynamicFont(size: 10, weight: .bold); statusCell.textColor = .white
        statusCell.usesSingleLineMode = true; statusCell.lineBreakMode = .byClipping
        macStatusLabel.cell = statusCell
        macStatusLabel.isEditable = false; macStatusLabel.isBordered = false
        macStatusLabel.drawsBackground = false; macStatusLabel.backgroundColor = .clear
        macStatusLabel.tag = 100
        macStatusLabel.wantsLayer = true; macStatusLabel.layer?.cornerRadius = kRadius / 2; macStatusLabel.layer?.backgroundColor = kAccent.cgColor
        macStatusLabel.layer?.borderWidth = kBorderWidth; macStatusLabel.layer?.borderColor = kBorder.cgColor
        macCard.addSubview(macStatusLabel)

        macProgressBar.wantsLayer = true; macProgressBar.layer?.cornerRadius = kRadius / 2; macProgressBar.layer?.backgroundColor = kSurface.cgColor
        macProgressBar.layer?.borderWidth = kBorderWidth; macProgressBar.layer?.borderColor = kBorder.cgColor
        macProgressBar.layer?.masksToBounds = true
        macCard.addSubview(macProgressBar)

        macProgressFill.wantsLayer = true; macProgressFill.layer?.cornerRadius = 0; macProgressFill.layer?.backgroundColor = kAccent.cgColor
        macProgressBar.addSubview(macProgressFill)

        btHeaderLabel.stringValue = "BLUETOOTH DEVICES"
        btHeaderLabel.font = dynamicFont(size: 10, weight: .bold); btHeaderLabel.textColor = kDim; btHeaderLabel.tag = 99
        btHeaderLabel.isEditable = false; btHeaderLabel.isBordered = false; btHeaderLabel.drawsBackground = false; btHeaderLabel.backgroundColor = .clear
        addSubview(btHeaderLabel)

        addSubview(btListContainer)
        updateMacBatteryUI()
        fetchBTDevicesAsync(forceProfiler: true)

        // Lightweight IOBluetooth check every 15s; heavy system_profiler is throttled to 45s or on device-count change.
        btTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.updateMacBatteryUI()
            self?.fetchBTDevicesAsync(forceProfiler: false)
        }
    }

    private func setupPowerNotifications() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ context in
            guard let ptr = context else { return }
            let view = Unmanaged<BatteryView>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async { view.updateMacBatteryUI() }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            powerRunLoopSource = src
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(onWake), name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    @objc private func onWake() {
        updateMacBatteryUI()
        fetchBTDevicesAsync(forceProfiler: true)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let cardW = w - 24
        macCard.frame = NSRect(x: 12, y: h - 100, width: cardW, height: 88)
        macProgressBar.frame = NSRect(x: 12, y: 12, width: cardW - 24, height: 18)
        btHeaderLabel.frame = NSRect(x: 12, y: h - 124, width: w - 24, height: 16)
        btListContainer.frame = NSRect(x: 12, y: 12, width: w - 24, height: h - 142)

        updateMacBatteryUI()

        if btListContainer.bounds.size != lastBTContainerSize {
            lastBTContainerSize = btListContainer.bounds.size
            renderBTDevices(lastBTDevices, force: true)
        }
    }

    private func updateMacBatteryUI() {
        let (pct, onAC, isActivelyCharging) = getMacBatteryInfo()
        macPctLabel.stringValue = "\(pct)%"

        let cardW = macCard.bounds.width > 0 ? macCard.bounds.width : (bounds.width - 24)
        let pad: CGFloat = 12
        // Top region inside macCard is y = 30..88 (vertical midpoint = 59)
        let topMidY: CGFloat = 59

        if onAC {
            let statusText = isActivelyCharging ? "CHARGING" : (pct >= 99 ? "FULL" : "PLUGGED IN")
            let statusFont = dynamicFont(size: 10, weight: .bold)
            macStatusLabel.font = statusFont
            macStatusLabel.stringValue = statusText
            macStatusLabel.textColor = .white
            macStatusLabel.layer?.backgroundColor = isActivelyCharging
                ? (NSColor(hex: "#10B981") ?? kAccent).cgColor
                : kAccent.cgColor
            macStatusLabel.isHidden = false

            let textW = ceil((statusText as NSString).size(withAttributes: [.font: statusFont]).width)
            let badgeW = max(78, min(textW + 20, cardW * 0.46))
            let badgeH: CGFloat = 24
            macStatusLabel.frame = NSRect(x: cardW - badgeW - pad, y: topMidY - badgeH / 2, width: badgeW, height: badgeH)
            let pctH: CGFloat = 40
            macPctLabel.frame = NSRect(x: pad, y: topMidY - pctH / 2, width: max(80, cardW - badgeW - pad * 2 - 8), height: pctH)
        } else {
            macStatusLabel.isHidden = true
            let pctH: CGFloat = 40
            macPctLabel.frame = NSRect(x: pad, y: topMidY - pctH / 2, width: cardW - pad * 2, height: pctH)
        }

        let inset = kBorderWidth
        let innerW = max(0, macProgressBar.bounds.width - inset * 2)
        let innerH = max(0, macProgressBar.bounds.height - inset * 2)
        let clampedPct = CGFloat(max(0, min(100, pct))) / 100.0
        macProgressFill.frame = NSRect(x: inset, y: inset, width: innerW * clampedPct, height: innerH)
        macProgressFill.layer?.backgroundColor = isActivelyCharging
            ? (NSColor(hex: "#10B981") ?? kAccent).cgColor
            : kAccent.cgColor
    }

    private func getMacBatteryInfo() -> (percent: Int, onAC: Bool, isCharging: Bool) {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for src in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, src).takeUnretainedValue() as? [String: Any] {
                let capacity = info[kIOPSCurrentCapacityKey] as? Int ?? 100
                let onAC = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                let isCharging = (info[kIOPSIsChargingKey] as? Bool) ?? onAC
                return (capacity, onAC, isCharging)
            }
        }
        return (100, false, false)
    }

    private func fetchBTDevicesAsync(forceProfiler: Bool) {
        guard !isFetching else { return }
        isFetching = true
        DispatchQueue.global(qos: .background).async { [weak self] in
            let devices = self?.getBTDevicesBackground(forceProfiler: forceProfiler) ?? []
            DispatchQueue.main.async {
                self?.isFetching = false
                self?.renderBTDevices(devices)
            }
        }
    }

    private func getBTDevicesBackground(forceProfiler: Bool) -> [BTDeviceItem] {
        var list: [BTDeviceItem] = []

        if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            for d in devices where d.isConnected() {
                let name = d.nameOrAddress ?? "Bluetooth Device"
                let s = (d.safeValue(forKey: "batteryPercentSingle") as? Int).flatMap { ($0 > 0 && $0 <= 100) ? $0 : nil }
                let l = (d.safeValue(forKey: "batteryPercentLeft") as? Int).flatMap { ($0 > 0 && $0 <= 100) ? $0 : nil }
                let r = (d.safeValue(forKey: "batteryPercentRight") as? Int).flatMap { ($0 > 0 && $0 <= 100) ? $0 : nil }
                let c = (d.safeValue(forKey: "batteryPercentCase") as? Int).flatMap { ($0 > 0 && $0 <= 100) ? $0 : nil }
                let combined = (d.safeValue(forKey: "batteryPercentCombined") as? Int).flatMap { ($0 > 0 && $0 <= 100) ? $0 : nil }
                let headset = (d.safeValue(forKey: "headsetBatteryPercent") as? Int).flatMap { ($0 > 0 && $0 <= 100) ? $0 : nil }
                let single = s ?? combined ?? headset

                let isCharging = (d.safeValue(forKey: "isCaseCharging") as? Bool == true) ||
                                 (d.safeValue(forKey: "isLeftCharging") as? Bool == true) ||
                                 (d.safeValue(forKey: "isRightCharging") as? Bool == true)

                list.append(BTDeviceItem(name: name, singleBattery: single, leftBattery: l, rightBattery: r, caseBattery: c, isCharging: isCharging))
            }
        }

        // Only run the expensive `system_profiler` subprocess when:
        //  - forced (launch/wake), or
        //  - connected device count changed, or
        //  - at least 45 seconds elapsed AND at least one device is missing battery info (or list is empty).
        let needsProfiler = forceProfiler
            || list.count != lastConnectedCount
            || (Date().timeIntervalSince(lastProfilerFetch) >= 45.0 && (list.isEmpty || list.contains { !$0.hasAnyBattery }))

        lastConnectedCount = list.count
        guard needsProfiler else {
            // Merge cached battery figures from lastBTDevices if IOBluetooth didn't expose them
            for i in list.indices where !list[i].hasAnyBattery {
                if let prev = lastBTDevices.first(where: { $0.name.lowercased() == list[i].name.lowercased() }) {
                    list[i] = prev
                }
            }
            return list
        }

        lastProfilerFetch = Date()
        let pipe = Pipe(), proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        proc.arguments = ["SPBluetoothDataType"]
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        let str = String(data: data, encoding: .utf8) ?? ""
        let lines = str.components(separatedBy: .newlines)

        var currentName: String?
        var isConnected = false
        var curSingle: Int?, curLeft: Int?, curRight: Int?, curCase: Int?
        var curCharging = false
        var inConnectedSection = false

        func commitCurrent() {
            guard let name = currentName else { return }
            if isConnected {
                if let idx = list.firstIndex(where: { $0.name.lowercased() == name.lowercased() || $0.name.contains(name) || name.contains($0.name) }) {
                    if list[idx].singleBattery == nil { list[idx].singleBattery = curSingle }
                    if list[idx].leftBattery == nil { list[idx].leftBattery = curLeft }
                    if list[idx].rightBattery == nil { list[idx].rightBattery = curRight }
                    if list[idx].caseBattery == nil { list[idx].caseBattery = curCase }
                    if curCharging { list[idx].isCharging = true }
                } else {
                    list.append(BTDeviceItem(name: name, singleBattery: curSingle, leftBattery: curLeft, rightBattery: curRight, caseBattery: curCase, isCharging: curCharging))
                }
            }
            currentName = nil
            isConnected = inConnectedSection
            curSingle = nil; curLeft = nil; curRight = nil; curCase = nil; curCharging = false
        }

        let ignoredHeaders = ["Bluetooth Controller:", "Devices (Paired, Configured, etc.):", "Connected:", "Not Connected:", "Services:", "Hardware, Features, and Settings:"]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "Connected:" {
                commitCurrent(); inConnectedSection = true; continue
            } else if trimmed == "Not Connected:" {
                commitCurrent(); inConnectedSection = false; continue
            }

            if (line.hasPrefix("          ") && !line.hasPrefix("              ")) ||
               (line.hasPrefix("      ") && !line.hasPrefix("          ") && trimmed.hasSuffix(":") && !ignoredHeaders.contains(trimmed)) {
                if trimmed.hasSuffix(":") && !ignoredHeaders.contains(trimmed) && !trimmed.contains("Address:") {
                    commitCurrent()
                    let name = trimmed.replacingOccurrences(of: ":", with: "")
                    if !name.isEmpty { currentName = name; isConnected = inConnectedSection }
                }
            }

            if line.contains("Connected: Yes") || line.contains("State: Connected") { isConnected = true }
            else if line.contains("Connected: No") || line.contains("State: Not Connected") { isConnected = false }

            if currentName != nil {
                if line.contains("Battery Level:") && !line.contains("Left") && !line.contains("Right") && !line.contains("Case") {
                    if let range = line.range(of: "(\\d+)%", options: .regularExpression) {
                        curSingle = Int(line[range].replacingOccurrences(of: "%", with: ""))
                    }
                } else if line.contains("Left Battery Level:") || line.contains("Left:") {
                    if let range = line.range(of: "(\\d+)%", options: .regularExpression) {
                        curLeft = Int(line[range].replacingOccurrences(of: "%", with: ""))
                    }
                } else if line.contains("Right Battery Level:") || line.contains("Right:") {
                    if let range = line.range(of: "(\\d+)%", options: .regularExpression) {
                        curRight = Int(line[range].replacingOccurrences(of: "%", with: ""))
                    }
                } else if line.contains("Case Battery Level:") || line.contains("Case:") {
                    if let range = line.range(of: "(\\d+)%", options: .regularExpression) {
                        curCase = Int(line[range].replacingOccurrences(of: "%", with: ""))
                    }
                } else if line.contains("Charging: Yes") || line.contains("State: Charging") || line.contains("Battery Status: Charging") {
                    curCharging = true
                }
            }
        }
        commitCurrent()
        return list
    }

    private func renderBTDevices(_ devices: [BTDeviceItem], force: Bool = false) {
        guard force || devices != lastBTDevices || btListContainer.subviews.isEmpty else { return }
        lastBTDevices = devices
        for sub in btListContainer.subviews { sub.removeFromSuperview() }

        if devices.isEmpty {
            let noDevLabel = NSTextField(labelWithString: "No Bluetooth devices connected")
            noDevLabel.font = dynamicFont(size: 11, weight: .medium); noDevLabel.textColor = kDim; noDevLabel.alignment = .center; noDevLabel.tag = 99
            noDevLabel.frame = NSRect(x: 0, y: (btListContainer.bounds.height - 20) / 2, width: btListContainer.bounds.width, height: 20)
            btListContainer.addSubview(noDevLabel)
            return
        }

        let containerW = btListContainer.bounds.width, itemH: CGFloat = 40, gap: CGFloat = 6
        for (i, dev) in devices.enumerated() {
            let y = btListContainer.bounds.height - CGFloat(i + 1) * (itemH + gap)
            let devCard = NSView(frame: NSRect(x: 0, y: y, width: containerW, height: itemH))
            devCard.wantsLayer = true; devCard.layer?.cornerRadius = kRadius / 2; devCard.layer?.backgroundColor = kSurface.cgColor
            devCard.layer?.borderWidth = kBorderWidth; devCard.layer?.borderColor = kBorder.cgColor

            let batText = dev.displayString
            let textFont = dynamicFont(size: 11, weight: .bold)
            let textSize = (batText as NSString).size(withAttributes: [.font: textFont])
            let badgeW = max(52, min(textSize.width + 16, containerW - 90))

            let nameTF = NSTextField()
            let nameCell = CenteredTextFieldCell(textCell: dev.name)
            nameCell.font = dynamicFont(size: 12, weight: .bold); nameCell.textColor = kText; nameCell.lineBreakMode = .byTruncatingTail
            nameTF.cell = nameCell; nameTF.stringValue = dev.name
            nameTF.isEditable = false; nameTF.isBordered = false; nameTF.drawsBackground = false; nameTF.backgroundColor = .clear
            nameTF.frame = NSRect(x: 10, y: 8, width: containerW - badgeW - 24, height: 24)
            devCard.addSubview(nameTF)

            let badgeTF = NSTextField()
            let badgeCell = CenteredTextFieldCell(textCell: batText)
            badgeCell.alignment = .center; badgeCell.font = textFont
            badgeCell.textColor = dev.isCharging ? .white : ((ThemeManager.shared.currentPreset == .glass || ThemeManager.shared.currentPreset == .childish) ? .white : kSurface)
            badgeTF.cell = badgeCell; badgeTF.stringValue = batText; badgeTF.tag = 100
            badgeTF.isEditable = false; badgeTF.isBordered = false
            badgeTF.drawsBackground = false; badgeTF.backgroundColor = .clear
            badgeTF.wantsLayer = true; badgeTF.layer?.cornerRadius = kRadius / 2
            badgeTF.layer?.backgroundColor = dev.isCharging ? NSColor(hex: "#10B981")!.cgColor : kAccent.cgColor
            badgeTF.layer?.borderWidth = kBorderWidth; badgeTF.layer?.borderColor = kBorder.cgColor
            badgeTF.frame = NSRect(x: containerW - badgeW - 10, y: 8, width: badgeW, height: 24)
            devCard.addSubview(badgeTF)

            btListContainer.addSubview(devCard)
        }
    }

    override func applyTheme(preset: ThemePreset) {
        macCard.layer?.backgroundColor = preset.surfaceColor.cgColor
        macCard.layer?.borderColor = preset.borderColor.cgColor
        macCard.layer?.borderWidth = preset.borderWidth
        macProgressBar.layer?.backgroundColor = preset.surfaceColor.cgColor
        macProgressBar.layer?.borderColor = preset.borderColor.cgColor
        macProgressFill.layer?.backgroundColor = kAccent.cgColor
        macStatusLabel.layer?.backgroundColor = kAccent.cgColor
        macStatusLabel.layer?.borderColor = preset.borderColor.cgColor
        updateThemeRecursively(preset: preset)
        updateMacBatteryUI()
        renderBTDevices(lastBTDevices, force: true)
    }
}
