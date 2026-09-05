#!/usr/bin/env bash
# Integration tier: drive the real game and check what it actually did.
#
#   test/integration/run.sh                    # hidden Xvfb display, software GL
#   AUPC_DISPLAY=:0 test/integration/run.sh    # your desktop, to watch
#
# Only ever send synthetic input to the Xvfb display. Keys aimed at a window on
# your own display can leave a modifier stuck down system wide.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$root/test/integration"
env_dir="$here/env"
factorio="${AUPC_FACTORIO:-/home/sparr/Games/Steam/steamapps/common/Factorio/bin/x64/factorio}"
results="$env_dir/write-data/script-output/aupc-results.lua"
sentinel="AUPC-TESTS-COMPLETE"
deadline="${AUPC_TIMEOUT:-300}"
display_number="${AUPC_XVFB_DISPLAY:-99}"

[[ -x "$factorio" ]] || { echo "no factorio binary at $factorio" >&2; exit 2; }

"$here/setup.sh" >/dev/null
rm -f "$results"
# Keep the previous log; the one being thrown away is regularly the wanted one.
[[ -f "$env_dir/run.out" ]] && mv -f "$env_dir/run.out" "$env_dir/run.previous.out"
: > "$env_dir/run.out"

# SteamAppId stops the binary relaunching itself through Steam, which detaches it
# from our display and pops a confirmation dialog on the desktop.
args=(
    --config "$env_dir/config.ini"
    --mod-directory "$env_dir/mods"
    --load-scenario aupc-tests/aupc
)

if [[ -n "${AUPC_DISPLAY:-}" ]]; then
    echo "==> launching on display $AUPC_DISPLAY (hardware GL)"
    env DISPLAY="$AUPC_DISPLAY" SDL_AUDIODRIVER=dummy SteamAppId=427520 \
        "$factorio" "${args[@]}" >> "$env_dir/run.out" 2>&1 &
else
    echo "==> launching on a private Xvfb display (software GL)"
    xvfb-run -n "$display_number" -s "-screen 0 640x480x24" \
        env LIBGL_ALWAYS_SOFTWARE=1 SDL_AUDIODRIVER=dummy SteamAppId=427520 \
        "$factorio" "${args[@]}" >> "$env_dir/run.out" 2>&1 &
fi
launcher=$!

# Block on the sentinel rather than polling, so a fast run finishes fast, and
# watch for a scenario that failed to load as well. Without that second pattern
# a syntax error in the scenario costs the whole timeout before saying so.
matched="$(timeout "$deadline" grep -m1 -E "$sentinel|Error .*control\\.lua" \
    < <(tail -n +1 -F "$env_dir/run.out") || true)"
if [[ "$matched" == *"$sentinel"* ]]; then
    echo "==> scenario finished"
elif [[ -n "$matched" ]]; then
    echo "==> the scenario failed to run:" >&2
    echo "    $matched" >&2
else
    echo "==> gave up after ${deadline}s without the sentinel" >&2
fi

# Only ever kill the game we started. Three independent conditions have to hold,
# because a bare `pkill -f` is dangerous here in two directions: it matches any
# shell whose argv happens to quote the pattern (including the one that wrote
# this script), and it would happily kill a Factorio the user is playing.
descends_from_launcher() {
    local pid="$1" guard=0
    while [[ -n "$pid" && "$pid" != "1" && "$pid" != "0" ]]; do
        [[ "$pid" == "$launcher" ]] && return 0
        (( ++guard > 64 )) && return 1
        pid="$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null || true)"
    done
    return 1
}

for pid in $(pgrep -f -- "--config $env_dir/config.ini" 2>/dev/null || true); do
    # 1. it is the game itself, not a shell quoting our command line
    [[ "$(cat "/proc/$pid/comm" 2>/dev/null || true)" == "factorio" ]] || continue
    # 2. it was started by this script, so a session the user launched is untouchable
    descends_from_launcher "$pid" || continue
    # 3. and it is not us
    [[ "$pid" == "$$" ]] && continue
    kill -TERM "$pid" 2>/dev/null || true
done
wait "$launcher" 2>/dev/null || true

exec lua5.2 "$here/report.lua" "$results"
