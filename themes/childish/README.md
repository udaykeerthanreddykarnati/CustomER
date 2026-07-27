# Bubbly Childish Theme

A vibrant, playful theme for macOS Minimal Desktop Widgets featuring Cotton Candy Pink card backgrounds, Bubblegum Pop headers and badges, solid cartoon outlines, and bubbly rounded system fonts.

---

## Palettes & Design Tokens

- Background: Cotton Candy Pink (`#FFE3F1`)
- Cards: Marshmallow Cream (`#FFF6FA`)
- Headers & Accents: Bubblegum Pop (`#FF4FA0`)
- Subtitle Labels: Dusty Lavender (`#8C6B9E`)
- Outlines: Solid Black Cartoon Border (`#000000`)
- Radius: 16px Bubbly Rounded Corners
- Font: Native Rounded System Font (`.design(.rounded)`)

---

## Build & Run

To compile and run the Bubbly Childish theme:

```bash
# Navigate to the childish theme directory
cd themes/childish

# Compile Swift binary
swiftc CustomERApp_ChildishTheme.swift -o CustomERApp -framework AppKit -framework Foundation -framework IOKit

# Run executable
./CustomERApp
```

To set this theme as your primary background daemon:

```bash
mkdir -p ~/.local/bin
mv themes/childish/CustomERApp ~/.local/bin/CustomERApp
launchctl unload ~/Library/LaunchAgents/com.user.CustomERApp.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.user.CustomERApp.plist
```
