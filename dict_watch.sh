#!/bin/bash

POPUP_SCRIPT="hyprdict-popup"
PREV_FILE="/tmp/dict_watch_prev"
PENDING_FILE="/tmp/dict_watch_pending"

cleanup() { kill 0; }
trap cleanup EXIT

# ── Normalize text (CRITICAL) ────────────────────────────────────────────────
clean_text() {
  printf '%s' "$1" |
    iconv -f UTF-8 -t UTF-8 -c 2>/dev/null |
    tr -d '\0\r' |
    sed 's/[[:space:]]\+/ /g' |
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# ── Detect Japanese safely ───────────────────────────────────────────────────

is_japanese() {
  printf '%s' "$1" | grep -qP '[\p{Hiragana}\p{Katakana}\p{Han}]'
}
# ── Shared filter + trigger ──────────────────────────────────────────────────
try_trigger() {
  local raw="$1"
  local word
  word=$(clean_text "$raw")

  [ -z "$word" ] && return

  local len=${#word}

  if is_japanese "$word"; then
    [ "$len" -lt 1 ] && return
  else
    [[ "$word" == *" "* ]] && return
    [ "$len" -lt 2 ] && return
  fi

  [ "$len" -gt 60 ] && return

  local prev
  prev=$(cat "$PREV_FILE" 2>/dev/null)
  [ "$word" = "$prev" ] && return

  echo "$word" >"$PREV_FILE"
  "$POPUP_SCRIPT" "$word" &
}

# ── Watcher 1: PRIMARY selection ─────────────────────────────────────────────
watch_primary() {
  wl-paste --primary --watch bash -c '
    PENDING_FILE="'"$PENDING_FILE"'"
    word=$(cat | tr -d '"'"'\0\r\n'"'"' | sed '"'"'s/^[[:space:]]*//;s/[[:space:]]*$//'"'"')
    [ -z "$word" ] && exit 0
    echo "$word" > "$PENDING_FILE"
    sleep 0.35
    current=$(cat "$PENDING_FILE" 2>/dev/null)
    [ "$word" != "$current" ] && exit 0
    printf "__PRIMARY__%s\n" "$word"
  ' | while IFS= read -r line; do
    [[ "$line" == __PRIMARY__* ]] && try_trigger "${line#__PRIMARY__}"
  done
}

# ── Watcher 2: CLIPBOARD (Zathura fix) ───────────────────────────────────────
watch_clipboard() {
  local prev_clip=""

  while true; do
    sleep 0.5

    local clip
    clip=$(wl-paste --no-newline 2>/dev/null)
    clip=$(clean_text "$clip")

    [ -z "$clip" ] && continue
    [ "$clip" = "$prev_clip" ] && continue

    prev_clip="$clip"
    try_trigger "$clip"
  done
}

watch_primary &
watch_clipboard &
wait
