# macOS Minimal Desktop Widgets

Lightweight, native macOS background daemon and desktop widget suite written in Swift using pure AppKit. Designed for zero CPU overhead, desktop-level window placement, and theme customization without third-party dependencies.

---

## Installation & Setup

### 1. Prerequisites
- macOS 12.0 or later
- Swift compiler (included with Xcode or Command Line Tools)

### 2. Clone Repository
```bash
git clone https://github.com/udaykeerthanreddykarnati/macos-minimal-desktop-widgets.git
cd macos-minimal-desktop-widgets
```

### 3. Compile Binary
```bash
# Compile the Swift source code into a standalone binary
swiftc CustomERApp.swift -o CustomERApp -framework AppKit -framework Foundation -framework IOKit

# Make binary executable
chmod +x CustomERApp
```

### 4. Run Directly
```bash
./CustomERApp
```

### 5. Run as Background Daemon (LaunchAgent)
To make the widget daemon launch automatically at startup and run in the background:

```bash
# Move compiled binary to user local bin directory
mkdir -p ~/.local/bin
mv CustomERApp ~/.local/bin/CustomERApp

# Create LaunchAgent directory if missing
mkdir -p ~/Library/LaunchAgents

# Write LaunchAgent plist file
cat << 'EOF' > ~/Library/LaunchAgents/com.user.CustomERApp.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE PLIST PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.CustomERApp</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/SHARED_USER/.local/bin/CustomERApp</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

# Update plist path with your current user home directory
sed -i '' "s|/Users/SHARED_USER|$HOME|g" ~/Library/LaunchAgents/com.user.CustomERApp.plist

# Load and start daemon
launchctl unload ~/Library/LaunchAgents/com.user.CustomERApp.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.user.CustomERApp.plist
```

---

## Features

- **Reminders**: Task list with add, inline edit, strike-through completion, and active/done filtering.
- **Calendar**: Monthly calendar with current day highlighting.
- **Battery & Devices**: Mac battery percentage, charging status indicator, and connected Bluetooth device levels.
- **Digital Clock**: Digital time (HH:mm) and date display without second-hand clutter.
- **Color Swatch Picker**: Theme palette switcher and color panel with debounced folder icon updates.
- **Analog Clock**: Circular analog clock with hour, minute, and second hands.
- **Spotify Player**: Track artwork, artist info, progress bar, audio equalizer, and playback controls.
- **ROBLOX Dance GIF**: Transparent GIF player with click-to-pause controls.
- **GitHub Stats**: Public repository count and total contributions tracker using GitHub GraphQL API.
- **Gmail Reader**: Online Gmail Atom feed parser displaying unread email count and subject line previews.
- **Photo Slots Grid**: Continuous row of 13 photo slots with downsampled image rendering.

---

## Configuration & Storage

Persistent configuration data is stored locally under `~/Library/Application Support/CustomER/`:

- `positions.json`: Stores saved (x, y) coordinates for all widgets.
- `theme.json`: Stores active background color theme hex code.
- `gmail.json`: Stores optional Gmail address and App Password for online mail sync.

---

## License

MIT License
