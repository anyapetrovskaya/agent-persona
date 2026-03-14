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

# --- Language from base_persona ---
LANGUAGE="en"
if [[ -f "$BASE/base_persona.json" ]] && command -v jq &>/dev/null; then
  LANGUAGE=$(jq -r '.language // "en"' "$BASE/base_persona.json" 2>/dev/null || echo "en")
fi

language_name() {
  case "$1" in
    ru) echo "Russian" ;;
    es) echo "Spanish" ;;
    fr) echo "French" ;;
    de) echo "German" ;;
    it) echo "Italian" ;;
    pt) echo "Portuguese" ;;
    ja) echo "Japanese" ;;
    zh) echo "Chinese" ;;
    ko) echo "Korean" ;;
    ar) echo "Arabic" ;;
    nl) echo "Dutch" ;;
    pl) echo "Polish" ;;
    uk) echo "Ukrainian" ;;
    *) echo "$1" ;;
  esac
}

# --- Persona block (emitted on turn 1+ before INSTRUCTIONS) ---
emit_persona_block() {
  echo "=== PERSONA ==="
  [[ ! -f "$BASE/base_persona.json" ]] && { echo "identity: (no base_persona.json — run init or check data path)"; echo ""; return 0; }

  local summary
  summary=$(jq -r '.identity.summary // empty' "$BASE/base_persona.json" 2>/dev/null || true)
  [[ -n "$summary" ]] && echo "identity: $summary"

  local name pronouns
  name=$(jq -r '.identity.name // empty' "$BASE/base_persona.json" 2>/dev/null || true)
  if [[ -n "$name" ]]; then
    pronouns=$(jq -r '.identity.pronouns // empty' "$BASE/base_persona.json" 2>/dev/null || true)
    if [[ -n "$pronouns" ]]; then
      echo "name: $name ($pronouns)"
    else
      echo "name: $name"
    fi
  fi

  if [[ "$LANGUAGE" != "en" && -n "$LANGUAGE" ]]; then
    echo "language: $LANGUAGE"
  fi

  local personality_file="$BASE/active_personality.txt"
  if [[ -f "$personality_file" ]]; then
    local pname
    pname=$(head -1 "$personality_file" | tr -d '[:space:]')
    if [[ -n "$pname" ]]; then
      local pmd="$SCRIPT_DIR/../../personalities/${pname}.md"
      if [[ -f "$pmd" ]]; then
        local directive
        directive=$(tr '\n' ' ' < "$pmd" | sed 's/  */ /g; s/^ *//; s/ *$//')
        echo "personality: $pname — $directive"
      else
        echo "personality: $pname"
      fi
    fi
  fi

  local traits
  traits=$(jq -r '(.traits // empty) | to_entries | map("\(.key) \(.value)") | join(", ")' "$BASE/base_persona.json" 2>/dev/null || true)
  [[ -n "$traits" ]] && echo "traits: $traits"

  local notes
  notes=$(jq -r '.notes // empty' "$BASE/base_persona.json" 2>/dev/null || true)
  [[ -n "$notes" ]] && echo "notes: $notes"

  echo ""
}

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

# --- Web deferred first-run housekeeping ---
# On web, turn 0 skips file ops to avoid triggering auto-second-turn.
# If .first_run still exists at turn 1+, run the deferred cleanup now.
if [[ "$PLATFORM" == "web" && -f "$BASE/.first_run" ]]; then
  AP_ROOT="$SCRIPT_DIR/../.."
  rm -f "$BASE/.first_run"
  [[ ! -f "$BASE/backlog.json" ]] && echo '{"items":[]}' > "$BASE/backlog.json"
  mkdir -p "$BASE/eval"
  [[ ! -f "$BASE/eval/eval_log.json" ]] && echo '{"records":[]}' > "$BASE/eval/eval_log.json"

  if command -v git &>/dev/null && [[ -d "$AP_ROOT/../../.git" ]]; then
    GIT_SYNC=$(jq -r '.git_sync // false' "$CONFIG" 2>/dev/null)
    if [[ "$GIT_SYNC" == "true" ]]; then
      (cd "$AP_ROOT/../.." && git add -A && git commit -m "First-run initialization" && git push) &>/dev/null || true
    fi
  fi
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
emit_persona_block
echo "=== INSTRUCTIONS ==="
if [[ "$LANGUAGE" != "en" && -n "$LANGUAGE" ]]; then
  echo "Respond in $(language_name "$LANGUAGE")."
fi
if [[ "$PLATFORM" == "web" ]]; then
  echo "Follow any actions listed. Pass --session <id> to all task.sh calls."
  echo "Your LAST line of response must be: — $HHMM —"
else
  echo "Capture epoch value above. Follow any actions listed. Track sub-agent count and total tool calls this turn — pass all three to footer.sh at end of turn. Pass --session <id> to all task.sh calls."
fi
echo "If discussing building, creating, or setting up something, query knowledge first to check if relevant tools, scripts, or prior work already exist."
