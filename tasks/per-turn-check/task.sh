#!/usr/bin/env bash
set -euo pipefail

TURN=1
MESSAGE=""
SESSION_ARG=""
CONVERSATION_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --turn)         TURN="$2"; shift 2 ;;
    --message)      MESSAGE="$2"; shift 2 ;;
    --session)      SESSION_ARG="$2"; shift 2 ;;
    --conversation) CONVERSATION_ARG="$2"; shift 2 ;;
    *)              shift ;;
  esac
done

# Resolve base path relative to this script's location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR/../../data"
CONFIG="$SCRIPT_DIR/../../config.json"

# --- Read config ---
DEBUG=false
TZ_VAL=""
PLATFORM="ide"
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG" 2>/dev/null || echo false)
  TZ_VAL=$(jq -r '.timezone // empty' "$CONFIG" 2>/dev/null || true)
  PLATFORM=$(jq -r '.platform // "ide"' "$CONFIG" 2>/dev/null || echo ide)
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false
export TZ="${TZ_VAL:-UTC}"

if $DEBUG; then
  CURRENT_TIME=$(date +%H:%M:%S)
  EPOCH=$(date +%s)
else
  CURRENT_TIME=$(date +%H:%M)
fi

# HH:MM for time math
HHMM="${CURRENT_TIME:0:5}"

# Convert HH:MM to total minutes since midnight
to_minutes() {
  local h m
  h=$((10#${1%%:*}))
  m=$((10#${1##*:}))
  echo $(( h * 60 + m ))
}

current_min=$(to_minutes "$HHMM")

# --- Save check ---
SAVE_FILE="$BASE/last_proactive_save.txt"
SAVE_INTERVAL=15

if [[ -f "$CONFIG" ]] && command -v jq &>/dev/null; then
  interval_val=$(jq -r '.save_interval // empty' "$CONFIG" 2>/dev/null || true)
  if [[ -n "$interval_val" ]]; then
    SAVE_INTERVAL="$interval_val"
  fi
fi

save_due="yes"
if [[ -f "$SAVE_FILE" ]]; then
  boundary=$(head -1 "$SAVE_FILE" | tr -d '[:space:]')
  if [[ "$boundary" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
    boundary_min=$(to_minutes "$boundary")
    next_save_min=$(( boundary_min + SAVE_INTERVAL ))
    if (( current_min < next_save_min )); then
      save_due="no"
    fi
  fi
fi

# --- Reminders check (from backlog) ---
BACKLOG_SCRIPT="$SCRIPT_DIR/../../scripts/backlog.sh"
reminders="none"
if [[ -f "$BACKLOG_SCRIPT" ]]; then
  alarm_output=$(bash "$BACKLOG_SCRIPT" alarms 2>/dev/null) || true
  if [[ -n "$alarm_output" ]]; then
    reminders="$alarm_output"
  fi
fi

# --- Output header ---
echo "time: $CURRENT_TIME"
if $DEBUG; then
  echo "epoch: $EPOCH"
fi

# --- Turn 0: dispatch to conversation-start ---
if [[ "$TURN" == "0" ]]; then
  echo "actions: none"
  echo ""

  CS_ARGS=(--message "$MESSAGE")
  [[ -n "$SESSION_ARG" ]] && CS_ARGS+=(--session "$SESSION_ARG")
  [[ -n "$CONVERSATION_ARG" ]] && CS_ARGS+=(--conversation "$CONVERSATION_ARG")
  bash "$SCRIPT_DIR/../conversation-start/task.sh" "${CS_ARGS[@]}"
  exit 0
fi

# --- Turn 1+: normal per-turn-check ---
has_actions=false
action_lines=""

if [[ "$reminders" != "none" ]]; then
  has_actions=true
  IFS=';' read -ra parts <<< "$reminders"
  for part in "${parts[@]}"; do
    part="$(echo "$part" | sed 's/^ *//;s/ *$//')"
    [[ -n "$part" ]] && action_lines+=$'\n'"- reminder: $part"
  done
fi

if [[ "$save_due" == "yes" ]]; then
  has_actions=true
  action_lines+=$'\n'"- save: bash agent-persona/tasks/prepare-handoff/task.sh"
fi

if $has_actions; then
  echo "actions:$action_lines"
else
  echo "actions: none"
fi

echo ""
echo "=== INSTRUCTIONS ==="
if [[ "$PLATFORM" == "web" ]]; then
  echo "Follow any actions listed. Pass --session <id> to all task.sh calls."
  echo "Your LAST line of response must be: — $HHMM —"
else
  echo "Capture epoch value above. Follow any actions listed. Track sub-agent count and total tool calls this turn — pass all three to footer.sh at end of turn. Pass --session <id> to all task.sh calls."
fi
echo "If discussing building, creating, or setting up something, query knowledge first to check if relevant tools, scripts, or prior work already exist."
