#!/usr/bin/env bash
# generate-narrative/task.sh — slim instructions for main agent
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$BASE/config.json"
STAGING="$BASE/data/.staging"

# --- Parse args → stage for sub-agent ---
PERSPECTIVE="both"
PERIOD="all"
SESSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --perspective) PERSPECTIVE="$2"; shift 2 ;;
    --period)      PERIOD="$2"; shift 2 ;;
    --session)     SESSION="$2"; shift 2 ;;
    *)             echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
mkdir -p "$STAGING_DIR"
INVOCATION_ID="$(date +%s%N)-${RANDOM}"
jq -n --arg perspective "$PERSPECTIVE" --arg period "$PERIOD" \
  '{perspective: $perspective, period: $period}' > "$STAGING_DIR/generate-narrative-${INVOCATION_ID}.json"

# --- Debug flag ---
DEBUG=false
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG")
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false

echo "=== INSTRUCTIONS ==="
echo "spawn: Read agent-persona/tasks/generate-narrative/task.md and execute."
if [[ -n "$SESSION" ]]; then echo "session: $SESSION"; fi
echo "invocation: $INVOCATION_ID"
echo ""
echo "=== FLAGS ==="
echo "debug: $DEBUG"
