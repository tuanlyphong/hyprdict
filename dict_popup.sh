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
  # 🇯🇵 JAPANESE — Jotoba API (jotoba.de, open source, no regional blocks)
  # ===========================================================================
  json=$(curl -sf \
    -A "Mozilla/5.0" \
    -X POST "https://jotoba.de/api/search/words" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"$word\", \"language\": \"English\", \"no_english\": false}")

  [ -z "$json" ] && show_rofi "Error: could not reach Jotoba" && exit 1

  output=$(echo "$json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
words = data.get('words', [])
if not words:
    print('No results')
    sys.exit(0)

w = words[0]

# Reading / kanji
reading = w.get('reading', {})
kana    = reading.get('kana', '')
kanji   = reading.get('kanji', '')
header  = f'{kanji} [{kana}]' if kanji else kana
print(header)

# Senses
for sense in w.get('senses', [])[:4]:
    glosses = '; '.join(sense.get('glosses', []))
    pos_list = sense.get('pos', [])
    # pos entries can be strings or dicts
    pos_strs = []
    for p in pos_list:
        if isinstance(p, str):
            pos_strs.append(p)
        elif isinstance(p, dict):
            pos_strs.append(next(iter(p.keys()), ''))
    pos = ', '.join(pos_strs) if pos_strs else ''
    if pos:
        print(f'  • [{pos}] {glosses}')
    else:
        print(f'  • {glosses}')
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
