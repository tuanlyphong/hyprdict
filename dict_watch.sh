#!/bin/bash
# dict_watch.sh — auto-triggers dict_popup on mouse selection
#
# Add to hyprland.conf:
#   exec-once = ~/.config/hypr/scripts/dict_watch.sh

POPUP_SCRIPT="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/dict_popup.sh"
PREV_FILE="/tmp/dict_watch_prev"
PENDING_FILE="/tmp/dict_watch_pending"

cleanup() { kill 0; }
trap cleanup EXIT

# ── Shared filter + trigger ───────────────────────────────────────────────────
try_trigger() {
  local raw="$1"

  # Strip null bytes and control characters, trim whitespace
  local word
  word=$(printf '%s' "$raw" | tr -d '\0' | tr -d '\r' |
    tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  [ -z "$word" ] && return

  # Japanese: allow multi-char tokens (no space restriction)
  if printf '%s' "$word" | grep -qP '[\p{Hiragana}\p{Katakana}\p{Han}]'; then
    : # pass through
  else
    # English: reject anything containing a space (phrases/sentences)
    printf '%s' "$word" | grep -q ' ' && return
  fi

  local len=${#word}
  [ "$len" -lt 2 ] && return
  [ "$len" -gt 60 ] && return

  local prev
  prev=$(cat "$PREV_FILE" 2>/dev/null)
  [ "$word" = "$prev" ] && return

  echo "$word" >"$PREV_FILE"
  bash "$POPUP_SCRIPT" "$word" &
}

# ── Watcher 1: PRIMARY selection (browser, terminal, most apps) ───────────────
watch_primary() {
  wl-paste --primary --watch bash -c '
    PENDING_FILE="'"$PENDING_FILE"'"

    # Sanitize null bytes before any processing
    word=$(cat | tr -d '"'"'\0\r\n'"'"' | sed '"'"'s/^[[:space:]]*//;s/[[:space:]]*$//'"'"')
    [ -z "$word" ] && exit 0

    echo "$word" > "$PENDING_FILE"
    sleep 0.4

    current=$(cat "$PENDING_FILE" 2>/dev/null)
    [ "$word" != "$current" ] && exit 0

    printf "__PRIMARY__%s\n" "$word"
  ' | while IFS= read -r line; do
    [[ "$line" == __PRIMARY__* ]] && try_trigger "${line#__PRIMARY__}"
  done
}

# ── Watcher 2: CLIPBOARD poll (Zathura writes here, not primary) ──────────────
watch_clipboard() {
  local prev_clip=""
  while true; do
    sleep 0.6

    # tr -d '\0' strips null bytes that cause the warning spam
    local clip
    clip=$(wl-paste --no-newline 2>/dev/null | tr -d '\0\r' |
      sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    [ -z "$clip" ] && continue
    [ "$clip" = "$prev_clip" ] && continue

    # Extra guard: skip if output looks binary (non-printable chars remain)
    printf '%s' "$clip" | grep -qP '[^\x09\x0a\x20-\x7e\x80-\xff]' && continue

    prev_clip="$clip"
    try_trigger "$clip"
  done
}

watch_primary &
watch_clipboard &
wait
