#!/usr/bin/env bash
# memory-diff/task.sh — slim instructions for main agent
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$BASE/config.json"
STAGING="$BASE/data/.staging"

# --- Parse args → stage for sub-agent ---
EPISODE_ID="latest"
SESSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --episode) EPISODE_ID="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    *)         echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
mkdir -p "$STAGING_DIR"
INVOCATION_ID="$(date +%s%N)-${RANDOM}"
jq -n --arg episode_id "$EPISODE_ID" \
  '{episode_id: $episode_id}' > "$STAGING_DIR/memory-diff-${INVOCATION_ID}.json"

# --- Debug flag ---
DEBUG=false
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG")
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false

echo "=== INSTRUCTIONS ==="
echo "spawn: Read agent-persona/tasks/memory-diff/task.md and execute."
[[ -n "$SESSION" ]] && echo "session: $SESSION"
echo "invocation: $INVOCATION_ID"
echo ""
echo "=== FLAGS ==="
echo "debug: $DEBUG"
