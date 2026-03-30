#!/bin/bash

# Accept word from watcher daemon as $1, else fall back to clipboard
if [ -n "$1" ]; then
  word="$1"
else
  word=$(wl-paste --no-newline 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
fi

[ -z "$word" ] && exit 0

# Kill any existing dict popup
pkill -f "rofi.*dict.rasi" 2>/dev/null
sleep 0.05

# ── Helper: show with rofi -e (textbox mode = proper wrapping, no input bar)
# MousePrimary mapped to cancel so clicking anywhere on the popup closes it.
show_rofi() {
  rofi \
    -theme ~/.config/rofi/dict.rasi \
    -e "$1" \
    -kb-cancel "Escape,MousePrimary" \
    -kb-accept-entry ""
}

# ── Detect Japanese ───────────────────────────────────────────────────────────
is_jp=$(echo "$word" | grep -qP '[\p{Hiragana}\p{Katakana}\p{Han}]' && echo 1 || echo 0)

if [ "$is_jp" -eq 1 ]; then
  # ===========================================================================
  # 🇯🇵 JAPANESE — Jisho JSON API
  # ===========================================================================
  encoded=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$word")

  json=$(curl -sf -A "Mozilla/5.0" \
    "https://jisho.org/api/v1/search/words?keyword=${encoded}")

  [ -z "$json" ] && show_rofi "Error: could not reach Jisho" && exit 1

  output=$(echo "$json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('data', [])
if not results:
    print('No results')
    sys.exit(0)
r = results[0]
jp = r['japanese'][0]
word = jp.get('word') or jp.get('reading', '')
reading = jp.get('reading', '')
senses = r.get('senses', [])
lines = []
for s in senses[:4]:
    defs = '; '.join(s.get('english_definitions', []))
    pos  = ', '.join(s.get('parts_of_speech', []))
    lines.append(f'[{pos}] {defs}' if pos else defs)
header = f'{word} [{reading}]' if (word and reading and word != reading) else (word or reading)
print(header)
for l in lines:
    print(f'  • {l}')
")
  show_rofi "$output"

else
  # ===========================================================================
  # 🇬🇧 ENGLISH — Free Dictionary API (dictionaryapi.dev)
  # ===========================================================================
  word_lower=$(echo "$word" | tr '[:upper:]' '[:lower:]')

  json=$(curl -sf -A "Mozilla/5.0" \
    "https://api.dictionaryapi.dev/api/v2/entries/en/${word_lower}")

  [ -z "$json" ] && show_rofi "Error: could not reach dictionary API" && exit 1

  output=$(echo "$json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if isinstance(data, dict) and 'title' in data:
    print('No definition found')
    sys.exit(0)
entry = data[0]
word = entry.get('word', '')
phonetic = entry.get('phonetic', '')
if not phonetic:
    for p in entry.get('phonetics', []):
        if p.get('text'):
            phonetic = p['text']
            break
header = word + (f'  {phonetic}' if phonetic else '')
print(header)
for meaning in entry.get('meanings', [])[:3]:
    pos  = meaning.get('partOfSpeech', '')
    defs = meaning.get('definitions', [])
    if defs:
        d       = defs[0].get('definition', '')
        example = defs[0].get('example', '')
        line    = f'[{pos}] {d}'
        if example:
            line += f'\n    e.g. {example}'
        print(f'  • {line}')
")
  show_rofi "$output"
fi
