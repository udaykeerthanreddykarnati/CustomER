# Cyber Dark Glass Theme

An ultra-modern, frosted glass theme for macOS Minimal Desktop Widgets featuring deep obsidian backgrounds, electric indigo highlights, violet accent badges, and rounded 24px pill corners.

---

## Palettes & Design Tokens

- Background: Deep Cyber Midnight (`#090D16`)
- Cards: Frosted Dark Glass (`#151D2A`)
- Primary Accent: Electric Indigo (`#6366F1`)
- Secondary Accent: Violet Glow (`#8B5CF6`)
- Text: Crystal White (`#F1F5F9`)
- Muted Labels: Steel Slate (`#64748B`)
- Borders: Slate Glass (`#263346`)
- Radius: 24px Ultra-Smooth Pill Corners

---

## Build & Run

To compile and run the Cyber Dark Glass theme:

```bash
# Navigate to the glass theme directory
cd themes/glass

# Compile Swift binary
swiftc CustomERApp_GlassTheme.swift -o CustomERApp -framework AppKit -framework Foundation -framework IOKit

# Run executable
./CustomERApp
```

To set this theme as your primary background daemon:

```bash
mkdir -p ~/.local/bin
mv themes/glass/CustomERApp ~/.local/bin/CustomERApp
launchctl unload ~/Library/LaunchAgents/com.user.CustomERApp.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.user.CustomERApp.plist
```
