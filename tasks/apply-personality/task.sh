#!/usr/bin/env bash
# apply-personality/task.sh — slim instructions for main agent
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$BASE/config.json"
STAGING="$BASE/data/.staging"

# --- Parse args → stage for pre.sh ---
WORDS=""
MODE_ID=""
SESSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --words)   WORDS="$2"; shift 2 ;;
    --mode-id) MODE_ID="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    *)         echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -z "$WORDS" ]] && [[ -z "$MODE_ID" ]] && { echo "ERROR: at least one of --words or --mode-id required" >&2; exit 1; }

STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
mkdir -p "$STAGING_DIR"
INVOCATION_ID="$(date +%s%N)-${RANDOM}"
jq -n --arg words "$WORDS" --arg mode_id "${MODE_ID:-}" \
  '{words: $words, mode_id: $mode_id}' > "$STAGING_DIR/apply-personality-${INVOCATION_ID}.json"

# --- Debug flag ---
DEBUG=false
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG")
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false

echo "=== INSTRUCTIONS ==="
echo "spawn: Read agent-persona/tasks/apply-personality/task.md and execute."
[[ -n "$SESSION" ]] && echo "session: $SESSION"
echo "invocation: $INVOCATION_ID"
echo ""
echo "=== FLAGS ==="
echo "debug: $DEBUG"
