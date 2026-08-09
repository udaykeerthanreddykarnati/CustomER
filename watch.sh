#!/bin/zsh
# ─────────────────────────────────────────────────────────
#  CustomER — Hot Reload Watcher
#  Run this once:  chmod +x watch.sh && ./watch.sh
#  Every time you save CustomERApp.swift it will:
#    1. Kill the running app
#    2. Recompile
#    3. Relaunch
# ─────────────────────────────────────────────────────────

SRC="$(dirname "$0")/CustomERApp.swift"
BIN="/tmp/CustomERApp"
APPNAME="CustomERApp"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

compile_and_run() {
    echo ""
    echo "${CYAN}──────────────────────────────────────────${NC}"
    echo "${YELLOW}🔄  Change detected — reloading...${NC}"

    # Kill existing instance
    pkill -x "$APPNAME" 2>/dev/null
    sleep 0.2

    # Compile
    echo "${YELLOW}⚙️   Compiling...${NC}"
    ERRORS=$(swiftc -O "$SRC" \
        -framework AppKit \
        -framework Carbon \
        -framework IOKit \
        -o "$BIN" 2>&1)

    if [[ $? -ne 0 ]]; then
        echo "${RED}❌  Compile error:${NC}"
        echo "$ERRORS"
        echo "${YELLOW}⚠️   Fix the error and save again to retry.${NC}"
        return
    fi

    echo "${GREEN}✅  Compiled OK${NC}"

    # Relaunch
    "$BIN" &
    echo "${GREEN}🚀  Launched! (PID $!)${NC}"
    echo "${CYAN}──────────────────────────────────────────${NC}"
}

echo "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo "${CYAN}║   CustomER  Hot-Reload Watcher  🔥        ║${NC}"
echo "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo "Watching: ${YELLOW}$SRC${NC}"
echo "Press ${RED}Ctrl+C${NC} to stop."

# Initial build on start
compile_and_run

# Watch for changes
fswatch -o --event Updated --event Created "$SRC" | while read; do
    compile_and_run
done
