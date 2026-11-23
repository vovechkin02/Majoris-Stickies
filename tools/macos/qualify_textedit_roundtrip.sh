#!/usr/bin/env bash
# Capture genuine, user-confirmed TextEdit saves and compare them read-only.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' 'This evidence-capture workflow requires a real macOS host.' >&2
  exit 2
fi
if [[ $# -ne 4 ]]; then
  printf '%s\n' 'Usage: qualify_textedit_roundtrip.sh ORIGINAL.rtfd MAJORIS-EXPORT.rtfd TEXTEDIT-RESAVED.rtfd NEW-EVIDENCE-DIR' >&2
  exit 2
fi

original=$1
exported=$2
resaved=$3
evidence=$4
script_dir=$(cd -- "$(dirname -- "$0")" && pwd -P)
inspector="$script_dir/../stickies_textedit_qualify.py"

for input in "$original" "$exported" "$resaved"; do
  if [[ ! -d "$input" || -L "$input" || "$input" != *.rtfd ]]; then
    printf 'Expected an existing, real .rtfd directory: %s\n' "$input" >&2
    exit 2
  fi
done

printf '%s\n' \
  'Before recording provenance, confirm:' \
  '1. ORIGINAL was created and saved by the actual TextEdit application.' \
  '2. MAJORIS-EXPORT was produced by the running Majoris Stickies application.' \
  '3. TEXTEDIT-RESAVED was opened and saved by TextEdit from the Majoris export.' \
  'These claims are user-attested; the tool cannot authenticate GUI applications.'
printf '%s' 'Type VERIFIED to continue: '
IFS= read -r confirmation
if [[ "$confirmation" != 'VERIFIED' ]]; then
  printf '%s\n' 'No provenance was recorded.' >&2
  exit 2
fi

# No existing evidence is overwritten; source RTFD directories are never edited.
mkdir -- "$evidence"
python3 "$inspector" record "$original" --producer textedit \
  --confirm-textedit-save --output "$evidence/original.json"
python3 "$inspector" record "$exported" --producer majoris \
  --output "$evidence/majoris-export.json"
python3 "$inspector" record "$resaved" --producer textedit \
  --confirm-textedit-save --output "$evidence/textedit-resaved.json"
python3 "$inspector" matrix "$original" "$exported" "$resaved" \
  --original-record "$evidence/original.json" \
  --export-record "$evidence/majoris-export.json" \
  --resaved-record "$evidence/textedit-resaved.json" \
  > "$evidence/semantic-comparison.json"

printf 'Semantic comparison and byte evidence recorded in: %s\n' "$evidence"
printf '%s\n' 'GTK/Wayland display, TextEdit appearance, and human visual comparison remain separate qualification gates.'
