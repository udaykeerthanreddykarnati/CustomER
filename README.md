# macOS Minimal Desktop Widgets

A lightweight, native macOS background daemon and interactive desktop widget suite built in Swift with pure AppKit. 

Designed for zero CPU overhead, seamless desktop-level window placement, instant theme color switching, and customizable widgets that blend right into your macOS desktop.

---

## ✨ Features

- 📝 **Reminders & Todo (`tututodo`)**: Interactive checklist with add, inline edit, strike-through completion, and active/done tabs.
- 📅 **Monthly Calendar (`tutucalendar`)**: Clean monthly calendar with current day highlights and dark/light contrast formatting.
- 🔋 **Battery & Bluetooth (`tutubattery`)**: Real-time Mac battery percentage, charging status indicator, and connected Bluetooth device battery metrics.
- 🕒 **Digital Clock (`tutuclock`)**: Minimalist digital time (HH:mm) and date display with zero second-hand clutter.
- 🎨 **Color Swatches Picker (`tutucolor`)**: On-the-fly theme palette switcher and system color wheel with instant zero-flicker background updates.
- 🕰️ **Analog Clock (`tutuclockcircle`)**: Circular analog clock with hour, minute, and smooth second hands.
- 🎵 **Spotify Live Player (`tutuspotify`)**: Live album artwork display, track info, real-time progress bar, animated equalizer, and playback controls.
- 💃 **ROBLOX Dance GIF (`tutugif`)**: Transparent animated GIF player on your desktop with click-to-pause controls.
- 🐙 **GitHub Profile Tracker (`tutugithub`)**: Live public repository count, total contributions tracker via GitHub GraphQL API, and double-click profile navigation.
- ✉️ **Gmail Reader (`tutumail`)**: Online Gmail Atom feed parser for real-time unread email count and subject line previews.
- 🖼️ **Album Art / Photo Slots Grid (`tutuphotos`)**: Single continuous row of 13 compact album photo slots with downsampled image rendering.

---

## 🛠️ Build & Run

### Prerequisites
- macOS 12.0 or later
- Swift compiler (`swiftc` included with Xcode / Command Line Tools)

### Build & Execute Directly
```bash
swiftc CustomERApp.swift -o CustomERApp -framework AppKit -framework Foundation -framework IOKit
./CustomERApp
```

### Run as a macOS Background Daemon (LaunchAgent)
1. Move the compiled binary to `~/.local/bin/CustomERApp`.
2. Create a LaunchAgent plist at `~/Library/LaunchAgents/com.user.CustomERApp.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE PLIST PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.CustomERApp</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/YOUR_USER/.local/bin/CustomERApp</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```
3. Load the daemon:
```bash
launchctl load ~/Library/LaunchAgents/com.user.CustomERApp.plist
```

---

## ⚙️ Architecture & Design Principles

- **Pure AppKit Native**: Zero external dependencies, third-party libraries, or Electron overhead.
- **Desktop Level Placement**: Windows use `NSWindow.Level(rawValue: -1)` to stay anchored right above the wallpaper below normal app windows.
- **Position Memory**: Drag any widget anywhere; positions auto-save to `positions.json`.
- **Instant Theme Sync**: `DistributedNotificationCenter` notifications update background colors with `CATransaction` disabled actions for zero flicker.
- **Privacy Conscious**: Sensitive credentials (like Gmail App Passwords) are stored locally in user Application Support directory and ignored by version control.

---

## 📄 License
MIT License
