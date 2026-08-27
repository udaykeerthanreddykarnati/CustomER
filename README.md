# CustomER

A lightweight, high-performance native macOS desktop widget suite & wallpaper manager built in pure Swift (AppKit, Carbon, IOKit).

Designed to live directly on your desktop background with zero third-party dependencies, zero Electron bloat, and ultra-low RAM footprint (`~90 MB`).

---

## Quick Start (1-Line Install & Run)

```bash
git clone https://github.com/udaykeerthanreddykarnati/CustomER.git && cd CustomER && swiftc -O CustomERApp.swift -framework AppKit -framework Carbon -framework IOKit -framework IOBluetooth -o CustomERApp && ./CustomERApp &
```

---

## Step-by-Step Installation Guide

### Prerequisites
- **macOS 12.0 (Monterey)** or later
- **Swift compiler** (included with Xcode or Command Line Tools)

### 1. Clone Repository
```bash
git clone https://github.com/udaykeerthanreddykarnati/CustomER.git
cd CustomER
```

### 2. Compile Application
```bash
swiftc -O CustomERApp.swift \
  -framework AppKit \
  -framework Carbon \
  -framework IOKit \
  -framework IOBluetooth \
  -o CustomERApp
```

### 3. Run Application
```bash
./CustomERApp &
```

*(Optional)* Move the compiled binary to your local binaries path to launch it anytime:
```bash
mkdir -p ~/.local/bin
mv CustomERApp ~/.local/bin/
```

---

## Global Hotkeys

- **`Option + W`**: Toggle floating Wallpaper Picker grid.
- **`Option + E`**: Toggle Style & Theme Customizer (Fonts, Color Wheel, Presets).
- **`Option + D`**: Toggle Desktop Icons & Folders on/off instantly.

---

## Key Features & Widgets

- **Dynamic Island Notch Widget (`notch`)**: Floating Spotify pill at top-center. Collapses into a 148×36 midnight pill with animated equalizer, expanding on track change or hover to 360×80 with album art and playback controls.
- **Reminders (`tututodo`)**: Star mark (`★`) priority sorting with warm amber highlight, double-click inline editing, and active/done tabs.
- **Monthly Calendar (`tutucalendar`)**: Double-click any date to view, add, edit, or delete events for that day. Event dot indicators (`•`) and laundry schedule.
- **Vector Timetable (`tutotimetable`)**: Compact class schedule grid with auto-highlighting for today's active classes.
- **Battery & Bluetooth (`tutubattery`)**: Real-time Mac battery level, AC power status, and connected Bluetooth device levels (AirPods, headphones, mouse).
- **System Monitor (`tutusys`)**: Real-time CPU usage, RAM allocation, and disk space.
- **Digital Clock (`tutuclock`)**: Clean digital time and date.

---

## Terminal Commands (`widgets`)

CustomER includes IPC control via macOS `DistributedNotificationCenter`:

```bash
widgets                # Launch / restart desktop widgets
widgets kill           # Hide all widgets
widgets show notch     # Show Dynamic Island Spotify Notch
widgets kill battery   # Hide specific widget
widgets font "Menlo"   # Set custom font
widgets reset          # Reset colors & fonts back to default theme
```
