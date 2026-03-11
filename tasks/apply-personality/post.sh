#!/usr/bin/env bash
# apply-personality/post.sh — apply mode change, eval log, output report
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
ACTIVE_PERSONALITY="$BASE/data/active_personality.txt"
EVAL_APPEND="$BASE/scripts/eval-append.sh"

# --- Read stdin ---
INPUT=$(cat)

# --- Extract sections (same awk pattern as conversation-start/post.sh) ---
extract_section() {
  local name="$1"
  local marker="=== ${name} ==="
  echo "$INPUT" | awk -v m="$marker" '
    $0 == m { found=1; next }
    found && /^=== .+ ===$/ { exit }
    found { print }
  '
}

ACTION_SECTION=$(extract_section "ACTION")
ACTION=$(echo "$ACTION_SECTION" | sed -n 's/.*action:[[:space:]]*\(set\|reset\).*/\1/p' | head -1)
MODE_ID=$(echo "$ACTION_SECTION" | sed -n 's/.*mode:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)

EVAL_SECTION=$(extract_section "EVAL_DATA")
SELF_ASSESSED=$(echo "$EVAL_SECTION" | sed -n 's/.*self_assessed_useful:[[:space:]]*\(true\|false\).*/\1/p' | head -1)
SELF_ASSESSED="${SELF_ASSESSED:-false}"

# --- 1. Apply mode change ---
if [[ "$ACTION" == "reset" ]]; then
  rm -f "$ACTIVE_PERSONALITY"
elif [[ "$ACTION" == "set" && -n "$MODE_ID" ]]; then
  printf '%s' "$MODE_ID" > "$ACTIVE_PERSONALITY"
fi

# --- 2. Eval logging (skip silently on failure) ---
EVAL_MODE="${MODE_ID:-default}"
if [[ "$ACTION" == "set" || "$ACTION" == "reset" ]]; then
  bash "$EVAL_APPEND" --type personality_switch \
    --action "$ACTION" \
    --mode "$EVAL_MODE" \
    --self_assessed_useful "$SELF_ASSESSED" &>/dev/null || true
fi

# --- 3. Debug ---
DEBUG=$(jq -r '.debug // false' "$BASE/config.json" 2>/dev/null || echo "false")
if [[ "$DEBUG" == "true" ]]; then
  echo "post.sh: action=$ACTION mode=$EVAL_MODE self_assessed=$SELF_ASSESSED" >&2
fi

# --- 4. Strip ACTION and EVAL_DATA, output clean report ---
echo "$INPUT" | awk '
  /^=== ACTION ===$/ { skip=1; next }
  /^=== EVAL_DATA ===$/ { skip=1; next }
  skip && /^=== .+ ===$/ { skip=0 }
  skip { next }
  { print }
'
