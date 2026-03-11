#!/usr/bin/env bash
# prepare-handoff/pre.sh — gather all context for handoff (run by sub-agent)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$AP_DIR/data"
CONFIG="$AP_DIR/config.json"
STAGING="$DATA_DIR/.staging"

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
TIME="" EPISODE="" END_OF_DAY=false CONVERSATION=""
ARGS_FILE="$STAGING_DIR/prepare-handoff.json"
if [[ -f "$ARGS_FILE" ]]; then
  TIME=$(jq -r '.time // ""' "$ARGS_FILE")
  EPISODE=$(jq -r '.episode // ""' "$ARGS_FILE")
  END_OF_DAY=$(jq -r '.end_of_day // false' "$ARGS_FILE")
  CONVERSATION=$(jq -r '.conversation // ""' "$ARGS_FILE")
  rm -f "$ARGS_FILE"
fi
[[ -z "$TIME" ]] && TIME=$(date +%H:%M:%S)
if [[ -z "$EPISODE" ]] || [[ "$EPISODE" == "null" ]]; then
  EPISODE=$(ls -t "$DATA_DIR/episodic"/episode_*.json 2>/dev/null | head -1)
fi
[[ "$END_OF_DAY" == "true" ]] && END_OF_DAY=true || END_OF_DAY=false

# --- Config ---
GIT_SYNC=false TIMEZONE=UTC SAVE_INTERVAL=15
if [[ -f "$CONFIG" ]]; then
  GIT_SYNC=$(jq -r '.git_sync // false' "$CONFIG")
  TIMEZONE=$(jq -r '.timezone // "UTC"' "$CONFIG")
  SAVE_INTERVAL=$(jq -r '.save_interval // 15' "$CONFIG")
fi

echo "=== CONFIG ==="
echo "git_sync=$GIT_SYNC"
echo "timezone=$TIMEZONE"
echo "save_interval=$SAVE_INTERVAL"

# --- Episode metadata ---
EP_PATH="$EPISODE"
SESSION_ID=$(basename "$EP_PATH" .json)
IS_NEW=true
EXISTING_COUNT=0
if [[ -n "$EP_PATH" ]] && [[ -f "$EP_PATH" ]]; then
  EXISTING_COUNT=$(jq '.records | length' "$EP_PATH")
  IS_NEW=false
fi

echo ""
echo "=== EPISODE_META ==="
echo "path=$EP_PATH"
echo "session_id=$SESSION_ID"
echo "is_new=$IS_NEW"
echo "existing_record_count=$EXISTING_COUNT"

# --- Existing episode content ---
echo ""
echo "=== EXISTING_EPISODE ==="
if [[ -n "$EP_PATH" ]] && [[ -f "$EP_PATH" ]]; then
  cat "$EP_PATH"
else
  echo "NONE"
fi

# --- Save boundary ---
HOUR="${TIME%%:*}"
MIN="${TIME#*:}"; MIN="${MIN%%:*}"
BOUNDARY=$(printf "%02d:%02d" "$((10#$HOUR))" "$(( (10#$MIN / SAVE_INTERVAL) * SAVE_INTERVAL ))")

echo ""
echo "=== SAVE_BOUNDARY ==="
echo "$BOUNDARY"

# --- Existing reminders ---
echo ""
echo "=== EXISTING_REMINDERS ==="
if [[ -n "$CONVERSATION" ]]; then
  HANDOFF_FILE="$DATA_DIR/conversations/${CONVERSATION}.md"
else
  HANDOFF_FILE="$DATA_DIR/current_session_handoff.md"
fi
if [[ -f "$HANDOFF_FILE" ]] && grep -q "^## Reminder for user" "$HANDOFF_FILE"; then
  awk '/^## Reminder for user/{found=1; print; next} found && /^## /{exit} found{print}' "$HANDOFF_FILE"
else
  echo "NONE"
fi

# --- Handoff triggers ---
echo ""
echo "=== HANDOFF_TRIGGERS ==="
TRIGGERS_FILE="$DATA_DIR/learned_triggers.json"
if [[ -f "$TRIGGERS_FILE" ]]; then
  jq -c '[.triggers[] | select(.trigger_type == "before_handoff" and .approved == true)]' "$TRIGGERS_FILE"
else
  echo "[]"
fi

# --- Timestamps ---
echo ""
echo "=== TIMESTAMPS ==="
echo "iso=$(date -Iseconds)"
echo "tz=$(date +%Z)"
echo "tz_offset=$(date +%:z)"

# --- Correction count ---
echo ""
echo "=== CORRECTION_COUNT ==="
if [[ -n "$EP_PATH" ]] && [[ -f "$EP_PATH" ]]; then
  jq '[.records[] | select(.type == "correction")] | length' "$EP_PATH"
else
  echo "0"
fi

# --- Eval log metadata ---
echo ""
echo "=== EVAL_LOG ==="
EVAL_FILE="$DATA_DIR/eval/eval_log.json"
echo "path=$EVAL_FILE"
if [[ -f "$EVAL_FILE" ]]; then
  echo "exists=true"
  echo "event_count=$(jq '.events | length' "$EVAL_FILE")"
else
  echo "exists=false"
fi

# --- Flags ---
echo ""
echo "=== FLAGS ==="
DEBUG_FLAG=$(jq -r '.debug // false' "$CONFIG" 2>/dev/null || echo false)
echo "end_of_day=$END_OF_DAY"
echo "debug=$DEBUG_FLAG"
echo "git_sync=$GIT_SYNC"
echo "conversation=$CONVERSATION"
