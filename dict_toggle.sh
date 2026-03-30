#!/bin/bash
# dict_toggle.sh — Super+L: start watcher if off, kill if on
# Uses a PID file to avoid pkill -f matching unrelated processes.

WATCH_SCRIPT="hyprdict-watch"
PID_FILE="/tmp/dict_watch.pid"

if [ -f "$PID_FILE" ]; then
  pid=$(cat "$PID_FILE")
  if kill -0 "$pid" 2>/dev/null; then
    # ── ON → OFF ─────────────────────────────────────────────────────────
    # Kill the watcher process group so child watchers die too
    kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null
    rm -f "$PID_FILE"
    pkill -f "rofi.*dict.rasi" 2>/dev/null
    notify-send -t 2000 "Dict" "Lookup off" 2>/dev/null || true
    exit 0
  else
    # Stale PID file
    rm -f "$PID_FILE"
  fi
fi

# ── OFF → ON ───────────────────────────────────────────────────────────────
# Start in its own process group (setsid) so we can kill the whole group
setsid "$WATCH_SCRIPT" &
echo $! >"$PID_FILE"
notify-send -t 2000 "Dict" "Lookup on" 2>/dev/null || true
