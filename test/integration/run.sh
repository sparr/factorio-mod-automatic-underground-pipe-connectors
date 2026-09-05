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
display_number="${AUPC_XVFB_DISPLAY:-121}"

# xvfb-run -n attaches to a display that already exists rather than failing, so a
# hardcoded number silently shares somebody else's session. The DimensionSync
# harness next door uses :99, and this one used to as well.
require_free_display() {
    if [[ -e "/tmp/.X11-unix/X$1" ]]; then
        echo "==> display :$1 is already in use by another X server." >&2
        echo "    Set AUPC_XVFB_DISPLAY to a free number." >&2
        exit 3
    fi
}


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
    require_free_display "$display_number"
    echo "==> launching on private display :$display_number (software GL)"
    xvfb-run -n "$display_number" -s "-screen 0 640x480x24" \
        env LIBGL_ALWAYS_SOFTWARE=1 SDL_AUDIODRIVER=dummy SteamAppId=427520 \
        "$factorio" "${args[@]}" >> "$env_dir/run.out" 2>&1 &
fi
launcher=$!

# Kill only the game this run started: it must be named factorio, carry our
# config path, and descend from our launcher, so a session the user is playing
# can never match. Running from a trap matters because a run cut short -- piped
# into head, or interrupted -- otherwise leaves a process holding the write-data
# lock, and the next run cannot start at all.
descends_from_launcher() {
    local pid="$1" guard=0
    while [[ -n "$pid" && "$pid" != "1" && "$pid" != "0" ]]; do
        [[ "$pid" == "$launcher" ]] && return 0
        (( ++guard > 64 )) && return 1
        pid="$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null || true)"
    done
    return 1
}

stop_game() {
    for pid in $(pgrep -f -- "--config $env_dir/config.ini" 2>/dev/null || true); do
        [[ "$(cat "/proc/$pid/comm" 2>/dev/null || true)" == "factorio" ]] || continue
        descends_from_launcher "$pid" || continue
        [[ "$pid" == "$$" ]] && continue
        kill -TERM "$pid" 2>/dev/null || true
    done
}
trap stop_game EXIT INT TERM

# Block on a marker rather than polling, so a fast run finishes fast. Watching
# for a scenario that failed to load matters too: without it a syntax error in
# the scenario costs the whole timeout before saying so.
# Each call resumes after the previous match, so a second marker of the same
# shape is not answered by rereading the first one. The result comes back in a
# global rather than through $(...), which would run this in a subshell and
# throw the new offset away -- and then answer the first marker forever.
watch_offset=1
WAIT_MATCH=""
wait_for() {
    local hit
    hit="$(timeout "$deadline" grep -n -m1 -E "$1" \
        < <(tail -n "+$watch_offset" -F "$env_dir/run.out") || true)"
    if [[ -z "$hit" ]]; then
        WAIT_MATCH=""
        return 1
    fi
    watch_offset=$(( watch_offset + ${hit%%:*} ))
    WAIT_MATCH="${hit#*:}"
    return 0
}

# Synthetic input goes to the private Xvfb display and nowhere else by default.
# A key aimed at a window on a desktop somebody is using can leave a modifier
# stuck down system wide, so sending to $AUPC_DISPLAY takes a second opt-in.
send_keys() {
    local keys="$1" target window
    if [[ -n "${AUPC_DISPLAY:-}" ]]; then
        if [[ -z "${AUPC_ALLOW_INPUT_ON_DISPLAY:-}" ]]; then
            echo "==> refusing to send '$keys' to $AUPC_DISPLAY;" \
                 "set AUPC_ALLOW_INPUT_ON_DISPLAY=1 to override" >&2
            return 1
        fi
        target="$AUPC_DISPLAY"
    else
        target=":$display_number"
    fi

    window="$(DISPLAY="$target" xdotool search --name "Factorio" 2>/dev/null | tail -1 || true)"
    if [[ -z "$window" ]]; then
        echo "==> no Factorio window on $target, cannot send '$keys'" >&2
        return 1
    fi
    if [[ -n "${AUPC_INPUT_DEBUG:-}" ]]; then
        echo "--- windows matching Factorio on $target ---" >&2
        DISPLAY="$target" xdotool search --name "Factorio" 2>/dev/null | while read -r w; do
            echo "    $w name=$(DISPLAY="$target" xdotool getwindowname "$w" 2>/dev/null)" \
                 "geom=$(DISPLAY="$target" xdotool getwindowgeometry --shell "$w" 2>/dev/null \
                         | tr '\n' ' ')" >&2
        done
    fi

    # There is no window manager on the Xvfb display, so focus has to be set by
    # hand. xdotool's key events are XTEST, which follow the input focus rather
    # than a window id; --window would use XSendEvent, which SDL ignores.
    DISPLAY="$target" xdotool windowmap "$window" 2>/dev/null || true
    DISPLAY="$target" xdotool windowraise "$window" 2>/dev/null || true
    DISPLAY="$target" xdotool windowfocus "$window" 2>/dev/null || true
    # Park the pointer inside the window too: with PointerRoot focus the server
    # delivers to whatever is under the cursor rather than to the focused window.
    DISPLAY="$target" xdotool mousemove --window "$window" 320 240 2>/dev/null || true

    if [[ -n "${AUPC_INPUT_DEBUG:-}" ]]; then
        echo "    focus is now $(DISPLAY="$target" xdotool getwindowfocus 2>/dev/null)" \
             "($(DISPLAY="$target" xdotool getwindowfocus getwindowname 2>/dev/null))" >&2
    fi

    DISPLAY="$target" xdotool key --clearmodifiers --delay 120 "$keys"
    echo "==> sent $keys to window $window on $target"
}

# The scenario asks for keys by printing a marker; answer each and keep watching.
matched=""
for _ in $(seq 1 20); do
    if ! wait_for "AUPC-AWAIT-[A-Z]+|$sentinel|Error .*control\\.lua"; then
        matched=""
        break
    fi
    matched="$WAIT_MATCH"
    case "$matched" in
        *AUPC-AWAIT-PROBE*) send_keys "ctrl+shift+F9" || true ;;
        *AUPC-AWAIT-UNDO*)  send_keys "ctrl+z" || true ;;
        *)                  break ;;
    esac
done

if grep -q "Couldn't acquire exclusive lock" "$env_dir/run.out" 2>/dev/null; then
    echo "==> another Factorio still holds this environment's lock; it did not start" >&2
elif [[ "$matched" == *"$sentinel"* ]]; then
    echo "==> scenario finished"
elif [[ -n "$matched" ]]; then
    echo "==> the scenario failed to run:" >&2
    echo "    $matched" >&2
else
    echo "==> gave up after ${deadline}s without the sentinel" >&2
fi

stop_game
wait "$launcher" 2>/dev/null || true

exec lua5.2 "$here/report.lua" "$results"
