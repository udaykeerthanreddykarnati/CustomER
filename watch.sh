#!/bin/zsh
# ─────────────────────────────────────────────────────────
#  CustomER — Hot Reload Watcher
#  Run once:  chmod +x watch.sh && ./watch.sh
#  Whenever you save any Swift file under Sources/, it will:
#    1. Kill the running app
#    2. Recompile all modules via build.sh
#    3. Relaunch
# ─────────────────────────────────────────────────────────

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$DIR/Sources"
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
    echo "${YELLOW}Change detected — reloading...${NC}"

    pkill -x "$APPNAME" 2>/dev/null || true
    sleep 0.2

    echo "${YELLOW}Compiling...${NC}"
    ERRORS=$("$DIR/build.sh" "$BIN" 2>&1)

    if [[ $? -ne 0 ]]; then
        echo "${RED}Compile error:${NC}"
        echo "$ERRORS"
        echo "${YELLOW}Fix the error and save again to retry.${NC}"
        return
    fi

    echo "${GREEN}Compiled OK${NC}"
    "$BIN" &
    echo "${GREEN}Launched! (PID $!)${NC}"
    echo "${CYAN}──────────────────────────────────────────${NC}"
}

echo "${CYAN}CustomER Hot-Reload Watcher${NC}"
echo "Watching: ${YELLOW}$SRC_DIR${NC}"
echo "Press ${RED}Ctrl+C${NC} to stop."

compile_and_run

fswatch -o -e ".*" -i "\\.swift$" "$SRC_DIR" | while read; do
    compile_and_run
done
