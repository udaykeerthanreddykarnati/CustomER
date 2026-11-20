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
  -framework ServiceManagement \
  -o "$OUT"

echo "Built $OUT"
