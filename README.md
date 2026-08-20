# CustomER — Native macOS Desktop Widget Suite & Wallpaper Manager

A lightweight, high-performance native macOS desktop widget suite built in pure Swift using AppKit, Carbon, IOKit, and IOBluetooth.

Designed to live directly on your desktop background, below normal app windows and desktop icons, with zero third-party dependencies, zero Electron bloat, and minimal resource usage.

---

## Features

- **Reminders Widget (`tututodo`)**:
  - **Star Mark (`★`)**: Mark important todo tasks with a prominent amber/gold highlight (`#F59E0B`).
  - **Top Sorting**: Starred tasks automatically float to the top of your list.
  - **Double-Click Edit & Delete**: Double click any todo to edit inline, or click `✕` to delete.
  - **Active / Done Tabs**: Easily switch between pending and completed tasks.

- **Monthly Calendar Widget (`tutucalendar`)**:
  - **Double-Click Date Event Management**: Double click any date to view, add, edit, or delete events for that specific day.
  - **Visual Event Indicators**: Days with scheduled events display a purple event dot (`•`) and a highlighted accent border on the grid.
  - **Laundry Schedule**: Built-in highlights for Give Laundry (Mon/Thu) and Take Laundry (Wed/Sat).

- **Wallpaper Switcher (`Option + W`)**:
  - Press `Option + W` anywhere to open a floating wallpaper picker grid.
  - Smooth expansion and crossfade transitions behind desktop icons with zero screen flickering.

- **Style & Theme Customizer (`Option + E`)**:
  - Press `Option + E` to open the font and color customizer.
  - Switch between **Minimal Butter**, **Cyber Glass**, and **Childish Pink** theme presets.
  - Choose custom text and background colors via native macOS color wheels.

- **System & Hardware Widgets**:
  - **Battery & Bluetooth (`tutubattery`)**: Live battery percentage, AC power status, and connected Bluetooth device levels (AirPods, headphones, mouse).
  - **System Monitor (`tutusys`)**: Real-time CPU usage, RAM allocation, and disk space.
  - **Digital Clock (`tutuclock`)**: Clean digital time and date.

---

## Quick Start

### 1. Clone & Build

```bash
git clone https://github.com/udaykeerthanreddykarnati/CustomER.git
cd CustomER
swiftc -O CustomERApp.swift -framework AppKit -framework Carbon -framework IOKit -framework IOBluetooth -o CustomERApp
./CustomERApp &
```

### 2. Usage & Hotkeys

- **`Option + W`**: Toggle floating Wallpaper Picker grid.
- **`Option + E`**: Toggle Style & Theme Customizer.
- **Reminders**: Click **`★`** to pin important tasks to top.
- **Calendar**: Double-click any day number on the calendar grid to manage events for that date.

---

## Terminal Commands (`widgets`)

CustomER includes a terminal command interface powered by macOS `DistributedNotificationCenter` IPC:

```bash
# Start / Restart all desktop widgets
widgets

# Stop all widgets
widgets kill

# Show or hide specific widgets
widgets show calendar
widgets kill battery

# Customize theme & colors
widgets font "Avenir Next"
widgets color text #FF5500
widgets color bg #1E1E2E
widgets reset
```

---

## Requirements

- macOS 12.0 (Monterey) or later
- Swift compiler (included with Xcode or Command Line Tools)
