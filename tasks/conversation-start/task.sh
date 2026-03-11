#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/../per-turn-check/task.sh"
echo ""

BASE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA="$BASE/data"
CONFIG="$BASE/config.json"
STAGING="$DATA/.staging"

# --- Parse args ---
TIME="" MESSAGE="" CONVERSATION="" SESSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --time)         TIME="$2"; shift 2 ;;
    --message)      MESSAGE="$2"; shift 2 ;;
    --conversation) CONVERSATION="$2"; shift 2 ;;
    --session)      SESSION="$2"; shift 2 ;;
    *)              echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# =============================================================
# FIRST-RUN PATH — brand new setup, show greeting and exit
# =============================================================
if [[ -f "$DATA/.first_run" ]]; then
  GREETING=""
  [[ -f "$DATA/first_greeting.txt" ]] && GREETING=$(cat "$DATA/first_greeting.txt")

  PERSONALITY="open-to-anything"
  [[ -f "$DATA/active_personality.txt" ]] && PERSONALITY=$(cat "$DATA/active_personality.txt")

  DIRECTIVE=""
  PERSONALITY_FILE="$BASE/personalities/${PERSONALITY}.md"
  [[ -f "$PERSONALITY_FILE" ]] && DIRECTIVE=$(cat "$PERSONALITY_FILE")

  rm "$DATA/.first_run"

  echo "$GREETING"
  echo "---"
  echo "personality: $PERSONALITY"
  if [[ -n "$DIRECTIVE" ]]; then
    echo "directive:"
    echo "$DIRECTIVE"
  fi
  echo "---"
  echo "Output the greeting above verbatim. Follow personality directive for the session. Do NOT mention features, setup, or internals unless user asks. Do NOT be sycophantic."
  exit 0
fi

# =============================================================
# RETURNING PATH — stage args + slim instructions
# =============================================================
[[ -z "$TIME" ]] && TIME=$(date +%H:%M:%S)

# --- Detect mode from message ---
MODE="default"
if [[ -n "$MESSAGE" ]]; then
  case "$MESSAGE" in
    *"anon mode"*)       MODE="anon" ;;
    *"standalone mode"*) MODE="standalone" ;;
  esac
fi

# --- Generate session ID if not provided ---
if [[ -z "$SESSION" ]]; then
  SESSION="$(date +%s)-${RANDOM}"
fi

# --- Stage args for pre.sh ---
STAGING_DIR="$STAGING/$SESSION"
mkdir -p "$STAGING_DIR"
jq -n --arg message "$MESSAGE" --arg time "$TIME" --arg mode "$MODE" --arg conversation "${CONVERSATION:-}" \
  '{message: $message, time: $time, mode: $mode, conversation: $conversation}' > "$STAGING_DIR/conversation-start.json"

# --- Debug flag ---
DEBUG=false
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG")
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false
if [[ -n "$MESSAGE" ]] && [[ "$MESSAGE" == *"debug on"* ]]; then
  DEBUG=true
fi

echo "=== INSTRUCTIONS ==="
echo "spawn: Read agent-persona/tasks/conversation-start/task.md and execute. Session: $SESSION"
echo "session: $SESSION"
echo ""
echo "=== FLAGS ==="
echo "debug: $DEBUG"
