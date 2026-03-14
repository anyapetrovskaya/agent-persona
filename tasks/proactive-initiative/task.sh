#!/usr/bin/env bash
# proactive-initiative/task.sh — slim instructions for main agent
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$BASE/config.json"
STAGING="$BASE/data/.staging"

# --- Parse args → stage for sub-agent ---
TRIGGER="" CONTEXT="" TIME="" SESSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trigger) TRIGGER="$2"; shift 2 ;;
    --context) CONTEXT="$2"; shift 2 ;;
    --time)    TIME="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    *)         echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -z "$TRIGGER" ]] && { echo "ERROR: --trigger required" >&2; exit 1; }

STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
mkdir -p "$STAGING_DIR"
INVOCATION_ID="$(date +%s%N)-${RANDOM}"
jq -n --arg trigger "$TRIGGER" --arg context "${CONTEXT:-}" --arg time "${TIME:-}" \
  '{trigger: $trigger, context: $context, time: $time}' > "$STAGING_DIR/proactive-initiative-${INVOCATION_ID}.json"

# --- Debug flag ---
DEBUG=false
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG")
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false

echo "=== INSTRUCTIONS ==="
echo "spawn: Read agent-persona/tasks/proactive-initiative/task.md and execute."
if [[ -n "$SESSION" ]]; then echo "session: $SESSION"; fi
echo "invocation: $INVOCATION_ID"
echo ""
echo "=== FLAGS ==="
echo "debug: $DEBUG"
