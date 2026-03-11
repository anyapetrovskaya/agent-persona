#!/usr/bin/env bash
set -euo pipefail

# Resolve base path relative to this script's location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR/../../data"
CONFIG="$SCRIPT_DIR/../../config.json"

# --- Read config ---
DEBUG=false
TZ_VAL=""
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG" 2>/dev/null || echo false)
  TZ_VAL=$(jq -r '.timezone // empty' "$CONFIG" 2>/dev/null || true)
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

# --- Reminders check ---
HANDOFF="$BASE/current_session_handoff.md"
reminders="none"

if [[ -f "$HANDOFF" ]]; then
  in_reminder_section=false
  matched_lines=()

  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]+[Rr]eminder ]]; then
      in_reminder_section=true
      continue
    fi
    if $in_reminder_section && [[ "$line" =~ ^## ]]; then
      break
    fi
    if $in_reminder_section && [[ -n "$line" ]]; then
      if [[ "$line" =~ ([0-9]{1,2}:[0-9]{2}) ]]; then
        reminder_time="${BASH_REMATCH[1]}"
        reminder_min=$(to_minutes "$reminder_time")
        diff=$(( current_min - reminder_min ))
        if (( diff < 0 )); then diff=$(( -diff )); fi
        if (( diff <= 5 )); then
          clean="${line#- }"
          matched_lines+=("$clean")
        fi
      fi
    fi
  done < "$HANDOFF"

  if (( ${#matched_lines[@]} > 0 )); then
    reminders=$(printf '%s; ' "${matched_lines[@]}")
    reminders="${reminders%; }"
  fi
fi

# --- Output ---
echo "time: $CURRENT_TIME"
if $DEBUG; then
  echo "epoch: $EPOCH"
fi

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
echo "Capture epoch value above. Follow any actions listed. Track sub-agent count and total tool calls this turn — pass all three to footer.sh at end of turn. Pass --session <id> to all task.sh calls."
