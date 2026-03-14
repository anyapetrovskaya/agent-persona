#!/usr/bin/env bash
# mark-accessed.sh — update last_accessed and increment access_count
# for knowledge items matching content strings passed via stdin (one per line).
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
KNOWLEDGE="$BASE/data/knowledge/knowledge.json"

[[ -f "$KNOWLEDGE" ]] || { echo "ERROR: knowledge.json not found" >&2; exit 1; }

CONTENT_LINES=$(cat)
[[ -z "$CONTENT_LINES" ]] && exit 0

NOW=$(date -Iseconds)

TMPFILE="${KNOWLEDGE}.tmp"

echo "$CONTENT_LINES" | jq -R -s --arg now "$NOW" '
  split("\n") | map(select(length > 0))
' > /tmp/mark_accessed_keys.json

jq --arg now "$NOW" --slurpfile keys /tmp/mark_accessed_keys.json '
  .items = [.items[] |
    if (.content as $c | $keys[0] | any(. == $c)) then
      .last_accessed = $now |
      .access_count = (.access_count // 0) + 1
    else . end
  ]
' "$KNOWLEDGE" > "$TMPFILE" && mv "$TMPFILE" "$KNOWLEDGE"

MATCHED=$(jq --slurpfile keys /tmp/mark_accessed_keys.json '
  [.items[] | select(.content as $c | $keys[0] | any(. == $c))] | length
' "$KNOWLEDGE")

rm -f /tmp/mark_accessed_keys.json

DEBUG=$(jq -r '.debug // false' "$BASE/config.json" 2>/dev/null || echo "false")
if [[ "$DEBUG" == "true" ]]; then
  echo "mark-accessed: updated $MATCHED items" >&2
fi
