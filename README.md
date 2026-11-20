# CustomER

A lightweight, native macOS desktop widget suite and wallpaper manager built in pure Swift (`AppKit`, `Carbon`, `IOKit`, `IOBluetooth`, `Network`, `Security`).

Designed to live directly on your desktop background with zero third-party dependencies, zero Electron overhead, and low CPU/RAM usage.

---

## Quick Start

### Prerequisites
- **macOS 12.0 (Monterey)** or later
- **Swift compiler** (Xcode or `xcode-select --install`)

### Build & Run
```bash
git clone https://github.com/udaykeerthanreddykarnati/CustomER.git
cd CustomER
chmod +x build.sh
./build.sh
./CustomERApp &
```

*(Optional)* Install to `~/.local/bin` to launch from anywhere:
```bash
mkdir -p ~/.local/bin
cp CustomERApp ~/.local/bin/
```

For development hot-reloading (requires `fswatch`):
```bash
chmod +x watch.sh && ./watch.sh
```

---

## Project Structure

```text
CustomER/
├── build.sh                     # Compiles all Swift modules with zero external dependencies
├── watch.sh                     # Hot-reload watcher for Sources/
└── Sources/
    ├── main.swift               # App lifecycle, single-instance lock, IPC & hotkeys
    ├── Core/
    │   ├── AppPaths.swift       # Unified ~/Library/Application Support/CustomER/ + atomic saves
    │   ├── BaseWidgetView.swift # Shared window dragging, position persistence & theme sync
    │   ├── DateFormatters.swift # Cached DateFormatters (zero per-tick allocations)
    │   ├── KeychainHelper.swift # Private 0600 local secret store for Gmail & sync tokens
    │   ├── PositionManager.swift# Window position persistence + multi-monitor clamping
    │   ├── ShellHelpers.swift   # AppleScript / shell utilities
    │   ├── SyncServer.swift     # Token-authenticated LAN HTTP server + optional cloud sync
    │   └── Theme.swift          # Presets (Minimal, Glass, Childish), color wheel & font picker
    └── Widgets/
        ├── TodoWidget.swift             # Tasks, star priority, Return/Esc shortcuts & mobile sync
        ├── HabitsWidget.swift           # Daily recurring habits (resets at 2:00 AM)
        ├── CalendarWidget.swift         # Monthly calendar with month navigation & day events
        ├── TimetableWidget.swift        # Weekly class/work vector timetable grid
        ├── BatteryWidget.swift          # Event-driven Mac battery + Bluetooth device levels
        ├── DigitalClockWidget.swift     # Minimal clock & date
        ├── SpotifyWidget.swift          # Event-driven Spotify player (zero idle polling)
        ├── MailWidget.swift             # Gmail unread count & preview (private 0600 credentials)
        ├── GifWidget.swift              # Transparent desktop GIF (click to play/pause)
        ├── WallpaperWidget.swift        # Wallpaper folder picker with smooth transition
        ├── ThemeCustomizerWidget.swift  # Live preset, font & color wheel customizer
        └── NotchWidget.swift            # Optional Dynamic Island Spotify pill
```

---

## Widgets Included

- **Reminders (`TodoWidget`)**: Active/Done tabs, star priority (`★`), double-click inline editing, `Enter` to add / `Esc` to cancel, conflict-safe per-task sync, and token-protected LAN QR pairing.
- **Daily Habits (`HabitsWidget`)**: Recurring daily checklist that automatically resets at 2:00 AM.
- **Monthly Calendar (`CalendarWidget`)**: `<` / `>` month navigation (click month title to jump back to today), double-click any date to add/edit/delete events, plus optional weekly recurring day highlights.
- **Weekly Timetable (`TimetableWidget`)**: Vector grid that highlights today's row automatically and supports merged multi-hour blocks.
- **Battery & Bluetooth (`BatteryWidget`)**: Event-driven Mac battery updates via `IOKit` plus connected Bluetooth accessory levels (AirPods L/R/Case, headphones, mice).
- **Spotify Player (`SpotifyWidget`)**: Subscribes to macOS `com.spotify.client.PlaybackStateChanged` notifications for zero-CPU idle behavior and live album art/controls.
- **Gmail Unread (`MailWidget`)**: Displays unread count and latest sender/subject; credentials are stored privately in an owner-only (`chmod 0600`) local file.
- **Digital Clock (`DigitalClockWidget`)**: Clean time and date with zero wasted redraws.
- **GIF Widget (`GifWidget`)**: Loads the first `.gif` in `~/Pictures/CustomERGifs/`. Click to play/pause, drag to move.
- **Wallpaper Switcher (`Option + W`)**: Auto-watching grid of `~/Pictures/Wallpapers` (or any chosen folder) with animated wallpaper transitions.
- **Theme Customizer (`Option + E`)**: Cycle presets (`MINIMAL`, `GLASS`, `CHILDISH`), pick any system font, or customize text/widget colors with the native color wheel.
- **Dynamic Island Notch (`NotchWidget`)**: Hidden by default; toggle anytime via IPC or `widget_visibility.json`.

---

## Customizing the Timetable Widget

The timetable comes with a generalized sample schedule (`CS101`, `MATH`, `PHYS`, `ENG`, `DESIGN`). You can customize it in **either** of two easy ways:

### Option A: Edit the Hardcoded Values in Code (Recommended if you compile locally)

1. Open **[`Sources/Widgets/TimetableWidget.swift`](Sources/Widgets/TimetableWidget.swift)**.
2. Find the clearly marked section near the top:
   ```swift
   // MARK: - CUSTOMIZE YOUR HARDCODED TIMETABLE HERE
   ```
3. Inside `TimetableConfig.defaultConfig`, update these 5 fields:
   - **`days`**: Rows shown in the grid (e.g., `["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]`).
   - **`headers`**: Column labels from left to right. Column `0` is always `"Day"`; time slots start at column `1`.
   - **`breakColumns`**: Indices of narrow break/lunch columns in `headers` (e.g., `[3, 6]` makes columns `3` and `6` narrow shaded dividers).
   - **`schedule`**: A dictionary mapping each day name to an array of `TimetableSlot(startCol:span:code:)`:
     - `startCol`: Which column in `headers` the block starts at (counting from `1`).
     - `span`: How many consecutive columns it spans (`1` = single slot, `2` = double block / lab).
     - `code`: Short label displayed on the tile.
   - **`subjectColors`**: Optional hex color per subject code (uppercase). Any unlisted subject automatically gets a pastel color.

   **Example:**
   ```swift
   "Monday": [
       TimetableSlot(startCol: 1, span: 1, code: "ALGO"),      // 8:00-9:00 (Col 1)
       TimetableSlot(startCol: 4, span: 2, code: "OS LAB")     // 10:30-12:30 (Cols 4 & 5)
   ]
   ```
4. Rebuild and restart:
   ```bash
   ./build.sh && pkill -x CustomERApp; ./CustomERApp &
   ```

### Option B: Override via JSON (No Recompile Needed)

Create `~/Library/Application Support/CustomER/timetable.json` using the same structure:
```json
{
  "days": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"],
  "headers": ["Day", "8:00-9:00", "9:00-10:00", "Break", "10:30-11:30", "11:30-12:30", "Lunch", "1:15-2:15", "2:15-3:15"],
  "breakColumns": [3, 6],
  "schedule": {
    "Monday": [
      { "startCol": 1, "span": 1, "code": "ALGO" },
      { "startCol": 4, "span": 2, "code": "OS LAB" }
    ]
  },
  "subjectColors": {
    "ALGO": "#D9E0FA",
    "OS LAB": "#D1EBFA"
  }
}
```
If `timetable.json` exists, it automatically overrides the hardcoded defaults on launch.

---

## Customizing Calendar Recurring Day Highlights (Optional)

Want certain weekdays color-coded every week (e.g., gym days, chores, meetings)?
- **In code**: Edit `CalendarConfig.defaultConfig` in [`Sources/Widgets/CalendarWidget.swift`](Sources/Widgets/CalendarWidget.swift).
- **Or via JSON**: Create `~/Library/Application Support/CustomER/calendar_config.json`:
  ```json
  {
    "legend": "MON/THU: GYM  •  WED/SAT: REVIEW",
    "tags": [
      { "weekdays": [1, 4], "hexColor": "#F59E0B" },
      { "weekdays": [3, 6], "hexColor": "#10B981" }
    ]
  }
  ```
  *(Weekday numbers: `0 = Sun`, `1 = Mon`, `2 = Tue`, `3 = Wed`, `4 = Thu`, `5 = Fri`, `6 = Sat`.)*

---

## Global Hotkeys

- **`Option + W`** *(on Desktop)*: Toggle floating Wallpaper Switcher.
- **`Option + E`** *(on Desktop)*: Toggle Style & Theme Customizer.
- **`Option + D`**: Toggle macOS Desktop icons on/off.

---

## Gmail, Secret Storage & Optional Cloud Sync

- **Adaptive Secret Storage**:
  - **Default (unsigned local builds)**: Credentials are stored in an owner-only (`chmod 0600`) file at `~/Library/Application Support/CustomER/.secrets.json` (never in Git, zero macOS Keychain popups when recompiling).
  - **Optional macOS Keychain mode (per-app ACL isolation, zero rebuild popups)**: Open **Keychain Access → Certificate Assistant → Create a Certificate…**, name it `CustomER Local`, and choose Certificate Type **Code Signing**. Running `./build.sh` will automatically sign the binary with `CustomER Local`, and `CustomERApp` will automatically migrate `.secrets.json` into a single macOS Keychain item (`secrets_bundle`) and delete the local file.
- **Gmail Widget**: Double-click the Gmail widget to enter your Gmail address and a 16-character Google App Password.
- **LAN Task Sync**: Click **Sync** on the Todo widget and scan the QR code from your phone on the same Wi-Fi. All `/api/*` endpoints require the random per-device pairing token embedded in the QR URL.
- **Optional GitHub Gist Cloud Sync**: Create `~/Library/Application Support/CustomER/sync.json` (`chmod 600`) with:
  ```json
  {
    "gist_id": "YOUR_GIST_ID",
    "github_token": "YOUR_PERSONAL_ACCESS_TOKEN"
  }
  ```
  On next launch, CustomER imports them into its secret store (removing `sync.json`) and syncs automatically (with ETag caching and sleep pause). Never commit credentials to the repository.

---

## IPC Control (`DistributedNotificationCenter`)

You can control running widgets from scripts via macOS `DistributedNotificationCenter` notification name `com.user.CustomERApp.control` with `userInfo` keys `action` (`show`, `hide`, `toggle`, `show_all`, `hide_all`, `set_font`, `set_bg_color`, `set_text_color`, `set_accent_color`, `reset_styles`, `kill_app`) and optional `widget` (`reminders`, `habits`, `calendar`, `timetable`, `battery`, `digital_clock`, `spotify`, `mail`, `gif`, `notch`) or `value`.
