# Minimal Theme

The primary, elegant theme for macOS Minimal Desktop Widgets featuring a warm Pastel Butter background, Rich Burgundy header typography, Soft Cream card surfaces, and crisp cartoon outlines.

---

## Palettes & Design Tokens

- Background: Pastel Butter (`#FEF9C3`)
- Cards: Soft Cream (`#FEFCE8`)
- Headers & Text: Rich Burgundy (`#800020`)
- Subtitle Labels: Muted Olive (`#595940`)
- Outlines: Solid Black Border (`#000000`)
- Radius: 16px Rounded Corners

---

## Build & Run

To compile and run the Minimal theme:

```bash
# Navigate to the minimal theme directory
cd themes/minimal

# Compile Swift binary
swiftc CustomERApp_MinimalTheme.swift -o CustomERApp -framework AppKit -framework Foundation -framework IOKit

# Run executable
./CustomERApp
```

To set this theme as your primary background daemon:

```bash
mkdir -p ~/.local/bin
mv themes/minimal/CustomERApp ~/.local/bin/CustomERApp
launchctl unload ~/Library/LaunchAgents/com.user.CustomERApp.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.user.CustomERApp.plist
```
