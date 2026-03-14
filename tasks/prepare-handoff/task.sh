#!/usr/bin/env bash
# prepare-handoff/task.sh — slim instructions for main agent
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$AP_DIR/data"
CONFIG="$AP_DIR/config.json"
STAGING="$DATA_DIR/.staging"

# --- Parse args → stage for pre.sh ---
TIME="" EPISODE="" END_OF_DAY=false CONVERSATION="" SESSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --time)         TIME="$2"; shift 2 ;;
    --episode)      EPISODE="$2"; shift 2 ;;
    --end-of-day)   END_OF_DAY=true; shift ;;
    --conversation) CONVERSATION="$2"; shift 2 ;;
    --session)      SESSION="$2"; shift 2 ;;
    *)              echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -z "$TIME" ]] && TIME=$(date +%H:%M:%S)
if [[ -z "$EPISODE" ]]; then
  EPISODE=$(ls -t "$DATA_DIR/episodic"/episode_*.json 2>/dev/null | head -1)
fi
if [[ -z "$EPISODE" ]]; then
  EPISODE="$DATA_DIR/episodic/episode_$(date +%Y-%m-%d_T%H-%M-00).json"
fi

STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
mkdir -p "$STAGING_DIR"
INVOCATION_ID="$(date +%s%N)-${RANDOM}"
jq -n --arg time "$TIME" --arg episode "${EPISODE:-}" --argjson end_of_day "$END_OF_DAY" --arg conversation "${CONVERSATION:-}" \
  '{time: $time, episode: $episode, end_of_day: $end_of_day, conversation: $conversation}' > "$STAGING_DIR/prepare-handoff-${INVOCATION_ID}.json"

# --- Debug flag ---
DEBUG=false
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG")
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false

echo "=== INSTRUCTIONS ==="
echo "spawn: Read agent-persona/tasks/prepare-handoff/task.md and execute. Include the last 2 user/assistant exchanges from this conversation verbatim in your prompt to the sub-agent (truncate each to ~500 chars if longer)."
if [[ -n "$SESSION" ]]; then
  echo "session: $SESSION"
fi
echo "invocation: $INVOCATION_ID"
echo ""
echo "=== FLAGS ==="
echo "debug: $DEBUG"
