#!/usr/bin/env bash
# infer-knowledge/task.sh — slim instructions for main agent
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$BASE/config.json"
STAGING="$BASE/data/.staging"

# --- Parse args → stage for sub-agent ---
EPISODES=""
SESSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --episodes) EPISODES="$2"; shift 2 ;;
    --session)  SESSION="$2"; shift 2 ;;
    *)          echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
mkdir -p "$STAGING_DIR"
INVOCATION_ID="$(date +%s%N)-${RANDOM}"
if [[ -n "$EPISODES" ]]; then
  jq -n --arg episodes "$EPISODES" '{episodes: $episodes}' > "$STAGING_DIR/infer-knowledge-${INVOCATION_ID}.json"
else
  echo '{}' > "$STAGING_DIR/infer-knowledge-${INVOCATION_ID}.json"
fi

# --- Debug flag ---
DEBUG=false
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG")
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false

echo "=== INSTRUCTIONS ==="
echo "spawn: Read agent-persona/tasks/infer-knowledge/task.md and execute."
[[ -n "$SESSION" ]] && echo "session: $SESSION"
echo "invocation: $INVOCATION_ID"
echo ""
echo "=== FLAGS ==="
echo "debug: $DEBUG"
