#!/usr/bin/env bash
# Step through the integration fixtures in a live Factorio window, stopping
# before each step to say what is about to happen.
#
#   test/integration/walkthrough.sh                    # on your desktop
#   AUPC_DISPLAY=:1 test/integration/walkthrough.sh    # somewhere else
#   AUPC_DISPLAY=headless test/integration/walkthrough.sh   # private Xvfb, to script
#
# In the game: Next advances, Skip fixture moves on, Run the rest finishes
# without stopping again, Stop ends early. The two undo fixtures ask you to
# press ctrl+z yourself, so a watched run never aims synthetic input at a
# desktop you are using.
#
# The game is left running at the end; quit it normally. The report is printed
# once you do.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$root/test/integration"
env_dir="$here/env"
factorio="${AUPC_FACTORIO:-/home/sparr/Games/Steam/steamapps/common/Factorio/bin/x64/factorio}"
results="$env_dir/write-data/script-output/aupc-results.lua"
display="${AUPC_DISPLAY:-${DISPLAY:-:0}}"
xvfb_display="${AUPC_XVFB_DISPLAY:-121}"

# xvfb-run -n attaches to a display that already exists rather than failing, so a
# hardcoded number silently shares somebody else's session. The DimensionSync
# harness next door uses :99, and this one used to as well.
require_free_display() {
    # Ask whether a server actually answers rather than whether a socket file
    # exists: the socket outlives a server that has just exited, which would
    # block the next run for no reason.
    if [[ ! -e "/tmp/.X11-unix/X$1" ]]; then return 0; fi
    if DISPLAY=":$1" timeout 3 xdpyinfo >/dev/null 2>&1; then
        echo "==> display :$1 is already in use by a running X server." >&2
        echo "    Set AUPC_XVFB_DISPLAY to a free number." >&2
        exit 3
    fi
}


[[ -x "$factorio" ]] || { echo "no factorio binary at $factorio" >&2; exit 2; }

AUPC_WALKTHROUGH=true "$here/setup.sh" >/dev/null
rm -f "$results"
[[ -f "$env_dir/run.out" ]] && mv -f "$env_dir/run.out" "$env_dir/run.previous.out"
: > "$env_dir/run.out"

args=(
    --config "$env_dir/config.ini"
    --mod-directory "$env_dir/mods"
    --load-scenario aupc-tests/aupc
)

# SteamAppId stops the binary relaunching itself through Steam, which would
# detach it from the display and pop a confirmation dialog.
if [[ "$display" == "headless" ]]; then
    require_free_display "$xvfb_display"
    echo "==> running unwatched on private display :$xvfb_display"
    xvfb-run -n "$xvfb_display" -s "-screen 0 1280x800x24" \
        env LIBGL_ALWAYS_SOFTWARE=1 SDL_AUDIODRIVER=dummy SteamAppId=427520 \
        "$factorio" "${args[@]}" >> "$env_dir/run.out" 2>&1 || true
else
    echo "==> opening on display $display; it will stop at the first step and wait"
    env DISPLAY="$display" SDL_AUDIODRIVER=dummy SteamAppId=427520 \
        "$factorio" "${args[@]}" >> "$env_dir/run.out" 2>&1 || true
fi

# No trap and no kill here: a walkthrough is over when you close the game.
if [[ -f "$results" ]]; then
    lua5.2 "$here/report.lua" "$results" || true
else
    echo "==> no report was written; the run was closed before it finished"
fi
