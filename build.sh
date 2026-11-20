#!/bin/zsh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$DIR/CustomERApp}"

swiftc -O \
  "$DIR"/Sources/Core/*.swift \
  "$DIR"/Sources/Widgets/*.swift \
  "$DIR"/Sources/main.swift \
  -framework AppKit \
  -framework Carbon \
  -framework CoreImage \
  -framework IOBluetooth \
  -framework IOKit \
  -framework Network \
  -framework Security \
  -o "$OUT"

# Optional stable code signing (enables popup-free macOS Keychain storage).
# Create a local "CustomER Local" Code Signing certificate in Keychain Access,
# or pass CUSTOMER_SIGN_IDENTITY="Your Cert Name" ./build.sh
SIGN_ID="${CUSTOMER_SIGN_IDENTITY:-CustomER Local}"
if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$SIGN_ID\""; then
  codesign --force --sign "$SIGN_ID" --identifier "com.customER.app" "$OUT"
  echo "Built & signed ($SIGN_ID): $OUT"
else
  echo "Built $OUT"
fi
