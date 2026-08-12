# CustomER — Native macOS Desktop Widget Suite & Wallpaper Manager

A lightweight, high-performance native macOS desktop widget suite and wallpaper switcher built in pure Swift using AppKit, Carbon, IOKit, and IOBluetooth.

Designed to live directly on your desktop background, below normal app windows and desktop icons, with zero third-party dependencies, zero Electron bloat, and minimal hardware resource usage.

---

## Technical Overview & Feature Breakdown

### 1. Wallpaper Switcher & Global Hotkey (`Option + W`)
- **Global Hotkey**: Press `Option + W` anywhere on macOS (via Carbon Event Manager) to instantly summon the floating wallpaper picker grid.
- **Aspect-Fill Thumbnail Grid**: Renders wallpaper previews with `NSCache` memory downsampling (150x95 resolution) to keep memory footprint minimal.
- **Center-Expansion Transition Engine**: 
  - Expands from a center thumbnail card to full screen in `0.35s` behind desktop icons (`CGWindowLevelForKey(.desktopWindow) + 1`).
  - Holds overlay for `1.40s` while WindowServer completes asynchronous desktop texture swapping.
  - Crossfades smoothly (`0.65s`) into the updated desktop with zero jump or flickering.
  - Uses `CALayer.contentsGravity = .resizeAspectFill` to match native macOS display cropping 1:1 without image distortion or stretching.

### 2. Style & Theme Customizer Widget & Hotkey (`Option + E`)
- **Global Hotkey**: Press `Option + E` anywhere on macOS to open the floating **Font & Color Customizer**.
- **Isolated Color Wheels**: Open native `NSColorPanel` for text color and widget background color without affecting fixed design accents.
- **System Font Selector**: Open native `NSFontPanel` to select any font installed on your Mac with PostScript name lookup.
- **One-Click Black & White Mode**: Instantly switch to pure white text on black widget cards (`widgets bw`).

### 2. Battery & Connected Bluetooth Devices Widget (`tutubattery`)
- **Mac System Battery**: Real-time battery percentage and charging/AC power indicator via `IOKit.pwr_mgt`.
- **Live Bluetooth Devices**: Queries macOS `IOBluetooth` framework directly (`IOBluetoothDevice.pairedDevices()`) for connected headphones, earbuds (e.g. AirPods, Noise Buds, soundcore), keyboards, and mice.
- **Exact Percentage Sync**: Reads hardware battery keys (`batteryPercentSingle`, `batteryPercentCombined`, `batteryPercentLeft`, `batteryPercentRight`, `batteryPercentCase`) for 1:1 accuracy matching the macOS menu bar.

### 3. Digital Clock & Calendar Widget (`tutuclock`)
- Digital time (HH:mm) and date display with clean typography and zero second-hand CPU churn.

### 4. System Performance Monitor Widget (`tutusys`)
- Real-time CPU usage, RAM allocation, disk space, and system uptime monitoring.

### 5. Weather Widget (`tutuweather`)
- Live weather conditions and temperature updates fetched via lightweight Open-Meteo REST API.

### 6. Music & Audio Control Widget (`tutumusic`)
- Displays current track info, artist name, playback controls (Play/Pause, Skip), and audio visualizer state.

### 7. Dynamic Theme & Layout Engine
- **Theme Presets**: Switch on-the-fly between **Minimal Butter** (Pastel Yellow), **Cyber Glass** (Dark Midnight), and **Childish Pink** (Cotton Candy).
- **Position Persistence**: Draggable widget positions saved automatically to `~/Library/Application Support/CustomER/positions.json`.

---

## Why It's Good (Strengths & Highlights)

1. **Ultra-Lightweight & Fast**:
   - Resting CPU usage: **`< 1.0%`**
   - Memory footprint: **`~131 MB`** (vs 500 MB+ for Electron/web-based widget apps).
2. **Direct macOS Hardware Integration**:
   - Uses native `IOBluetooth` and `IOKit` frameworks for hardware precision rather than scraping slow shell commands.
3. **Seamless Wallpaper Transitions**:
   - Plays expansion animations **behind desktop icons and widgets** so your desktop environment is never blocked.
   - Perfectly handles macOS Sonoma / Sequoia / Tahoe asynchronous WindowServer texture loading without visual glitching.
4. **Clean Aesthetics**:
   - Zero emojis in the user interface for a clean, professional look.
   - Fluid typography and glassmorphism styling.
5. **No Third-Party Dependencies**:
   - Pure Swift standard library and macOS SDK frameworks (`AppKit`, `Carbon`, `IOKit`, `IOBluetooth`).

---

## Limitations & Tradeoffs ("Why It's Bad")

1. **Monolithic Single-File Architecture**:
   - The entire application logic is contained inside `CustomERApp.swift` (~2,700 lines). While convenient for single-command compilation (`swiftc`), it requires clean IDE section markers for navigation.
2. **Requires Non-Sandboxed Execution**:
   - Because it uses Carbon global hotkeys (`Option + W`) and `IOBluetooth` hardware calls, it cannot run inside a restricted App Sandbox.
3. **WindowServer Hand-Off Timing**:
   - macOS internal wallpaper rendering is asynchronous and takes ~1.2s–1.4s to finish compositing in WindowServer. The transition engine deliberately holds the overlay for `1.40s` to prevent the old wallpaper from showing, which introduces a slight intentional delay before the overlay crossfades out.
4. **Uniform Screen Wallpaper Setting**:
   - Currently applies wallpaper selection uniformly across all attached displays (`NSScreen.screens`), rather than setting independent wallpapers per monitor.

---

## Compilation & Usage

### 1. Prerequisites
- macOS 12.0 (Monterey) or later.
- Swift compiler (included with Xcode or Command Line Tools).

### 2. Compile & Run
```bash
# Compile with all required macOS frameworks
swiftc -O CustomERApp.swift \
  -framework AppKit \
  -framework Carbon \
  -framework IOKit \
  -framework IOBluetooth \
  -o /tmp/CustomERApp

# Launch application
/tmp/CustomERApp &
```

### 3. Hot Reloading Script (`watch.sh`)
For rapid development, run `watch.sh` to automatically recompile and restart the app whenever `CustomERApp.swift` is saved:
```bash
chmod +x watch.sh
./watch.sh
```

---

## Terminal CLI Commands (`widgets`)

CustomER includes a terminal command interface powered by macOS `DistributedNotificationCenter` IPC:

```bash
# Start / Restart all widgets (auto-compiles if source updated)
widgets

# Stop all widgets
widgets kill

# Hide / Close a specific widget
widgets kill calendar    # Hides calendar widget
widgets kill battery     # Hides battery widget
widgets kill spotify     # Hides spotify widget

# Show / Open a specific widget
widgets show calendar
widgets show spotify

# Custom Font & Color Wheel Control
widgets font                       # Opens native macOS Font Panel (choose any font installed on your Mac!)
widgets font "Avenir Next"         # Set specific font (e.g. Menlo, Helvetica Neue, Optima, Futura)
widgets color text                 # Opens native macOS Color Wheel for text color
widgets color text #FF5500         # Set text color hex
widgets color bg #1E1E2E           # Set background color hex
widgets reset                      # Reset custom colors & fonts back to default theme

# Toggle visibility of a specific widget
widgets toggle calendar

# Check running status & list available widget keys
widgets list

# Force recompile latest code and restart
widgets build
```

---

## File Structure

```
CustomER/
├── CustomERApp.swift   # Main Swift application (Widgets, Wallpaper Manager, Hotkeys, Themes)
├── README.md           # Technical documentation and features
└── watch.sh            # Hot-reload development watcher script
```

---

## License

Private Repository — Personal Use Only.
