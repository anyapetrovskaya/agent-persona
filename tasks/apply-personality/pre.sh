#!/usr/bin/env bash
# apply-personality/pre.sh — gather context for personality switch (run by sub-agent)
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
DATA="$BASE/data"
STAGING="$DATA/.staging"
PERSONALITIES="$BASE/personalities"

# --- Parse script args ---
SESSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION="$2"; shift 2 ;;
    *)         shift ;;
  esac
done

# --- Read staged args ---
STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
WORDS=""
MODE_ID=""
ARGS_FILE="$STAGING_DIR/apply-personality.json"
if [[ -f "$ARGS_FILE" ]]; then
  WORDS=$(jq -r '.words // ""' "$ARGS_FILE")
  MODE_ID=$(jq -r '.mode_id // ""' "$ARGS_FILE")
  rm -f "$ARGS_FILE"
fi

echo "=== USER_INPUT ==="
echo "words: ${WORDS:-}"
echo "mode_id: ${MODE_ID:-none}"

# --- Current mode ---
CURRENT_MODE=""
SOURCE="base_persona_default"
if [[ -f "$DATA/active_personality.txt" ]]; then
  CURRENT_MODE="$(tr -d '[:space:]' < "$DATA/active_personality.txt")"
  [[ -n "$CURRENT_MODE" ]] && SOURCE="active_personality.txt"
fi
if [[ -z "$CURRENT_MODE" ]] && [[ -f "$DATA/base_persona.json" ]]; then
  CURRENT_MODE=$(jq -r '.default_mode // "expert-laconic"' "$DATA/base_persona.json")
fi
[[ -z "$CURRENT_MODE" ]] && CURRENT_MODE="expert-laconic"

echo ""
echo "=== CURRENT_MODE ==="
echo "mode: $CURRENT_MODE"
echo "source: $SOURCE"

# --- Base traits ---
TRAITS=""
if [[ -f "$DATA/base_persona.json" ]]; then
  TRAITS=$(jq -r '.traits | to_entries | map("\(.key)=\(.value)") | join(" ")' "$DATA/base_persona.json")
fi

echo ""
echo "=== BASE_TRAITS ==="
echo "$TRAITS"

# --- Available modes ---
AVAILABLE=""
if [[ -d "$PERSONALITIES" ]]; then
  AVAILABLE=$(find "$PERSONALITIES" -maxdepth 1 -name "*.md" ! -name "README.md" -exec basename {} .md \; | sort | tr '\n' ' ')
  AVAILABLE="${AVAILABLE%" "}"
fi

echo ""
echo "=== AVAILABLE_MODES ==="
echo "$AVAILABLE"

# --- Mode directives ---
echo ""
echo "=== MODE_DIRECTIVES ==="
if [[ -d "$PERSONALITIES" ]]; then
  for f in "$PERSONALITIES"/*.md; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f" .md)
    [[ "$base" == "README" ]] && continue
    echo "--- $base ---"
    cat "$f"
    echo ""
  done
fi
