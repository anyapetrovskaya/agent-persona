#!/usr/bin/env bash
# conversation-start/pre.sh — gather all session context (run by sub-agent)
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
DATA="$BASE/data"
CONFIG="$BASE/config.json"
STAGING="$DATA/.staging"

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
MESSAGE="" TIME="" MODE="default" CONVERSATION=""
ARGS_FILE="$STAGING_DIR/conversation-start.json"
if [[ -f "$ARGS_FILE" ]]; then
  MESSAGE=$(jq -r '.message // ""' "$ARGS_FILE")
  TIME=$(jq -r '.time // ""' "$ARGS_FILE")
  MODE=$(jq -r '.mode // "default"' "$ARGS_FILE")
  CONVERSATION=$(jq -r '.conversation // ""' "$ARGS_FILE")
  rm -f "$ARGS_FILE"
fi
[[ -z "$TIME" ]] && TIME=$(date +%H:%M:%S)

# --- Read config ---
DEBUG=false
GIT_SYNC=false
TZ_VAL="UTC"
SAVE_INTERVAL=15
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG")
  GIT_SYNC=$(jq -r '.git_sync // false' "$CONFIG")
  TZ_VAL=$(jq -r '.timezone // "UTC"' "$CONFIG")
  SAVE_INTERVAL=$(jq -r '.save_interval // 15' "$CONFIG")
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false
export TZ="$TZ_VAL"

# --- GIT SYNC ---
if [[ "$GIT_SYNC" == "true" ]]; then
  git -C "$BASE" pull 2>/dev/null || true
fi

echo "=== MODE ==="
echo "mode: $MODE"
echo "debug: $DEBUG"

# --- PERSONALITY ---
PERSONALITY_ID=""
if [[ -f "$DATA/active_personality.txt" ]]; then
  PERSONALITY_ID="$(tr -d '[:space:]' < "$DATA/active_personality.txt")"
fi
if [[ -z "$PERSONALITY_ID" ]] && [[ -f "$DATA/base_persona.json" ]]; then
  PERSONALITY_ID=$(jq -r '.default_mode // "expert-laconic"' "$DATA/base_persona.json")
fi
[[ -z "$PERSONALITY_ID" ]] && PERSONALITY_ID="expert-laconic"

TRAITS=""
if [[ -f "$DATA/base_persona.json" ]]; then
  TRAITS=$(jq -r '.traits | to_entries | map("\(.key)=\(.value)") | join(" ")' "$DATA/base_persona.json")
fi

echo ""
echo "=== PERSONALITY ==="
echo "id: $PERSONALITY_ID"
echo "base_traits: $TRAITS"

PERSONALITY_FILE="$BASE/personalities/${PERSONALITY_ID}.md"
echo ""
echo "=== PERSONALITY_DIRECTIVE ==="
if [[ -f "$PERSONALITY_FILE" ]]; then
  cat "$PERSONALITY_FILE"
else
  echo "[not found]"
fi

# --- HANDOFF ---
echo ""
echo "=== HANDOFF ==="
if [[ -n "$CONVERSATION" ]]; then
  HANDOFF_FILE="$DATA/conversations/${CONVERSATION}.md"
else
  HANDOFF_FILE="$DATA/current_session_handoff.md"
fi
HANDOFF_EXISTS=false
ITEMS_COUNT=0
if [[ -f "$HANDOFF_FILE" ]] && [[ -s "$HANDOFF_FILE" ]]; then
  HANDOFF_EXISTS=true
  ITEMS_COUNT=$(grep -c '.' "$HANDOFF_FILE" || true)
  echo "exists: true"
  cat "$HANDOFF_FILE"
else
  echo "exists: false"
  echo "NONE"
fi

# --- PROCEDURAL NOTES ---
NOTES_FILE="$DATA/procedural_notes.json"
echo ""
echo "=== PROCEDURAL_NOTES ==="
if [[ -f "$NOTES_FILE" ]]; then
  echo "active: $(jq -c '[.notes[] | select(.status == "active")]' "$NOTES_FILE")"
  echo "pending_approval: $(jq -c '[.notes[] | select(.status == "pending_approval")]' "$NOTES_FILE")"
else
  echo "active: []"
  echo "pending_approval: []"
fi

# --- CONSOLIDATION ---
echo ""
echo "=== CONSOLIDATION ==="
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
KNOWLEDGE_FILE="$DATA/knowledge/knowledge.json"
if [[ -f "$KNOWLEDGE_FILE" ]]; then
  LAST_INFER=$(jq -r '.last_infer_date // ""' "$KNOWLEDGE_FILE")
  if [[ -n "$LAST_INFER" ]] && { [[ "$LAST_INFER" == "$TODAY" ]] || [[ "$LAST_INFER" == "$YESTERDAY" ]]; }; then
    echo "status: current"
  else
    echo "status: overdue"
  fi
  echo "last_infer_date: ${LAST_INFER:-never}"
else
  echo "status: overdue"
  echo "last_infer_date: never"
fi

# --- SAVE BOUNDARY ---
to_minutes() {
  local h m
  h=$((10#${1%%:*}))
  m=$((10#${1##*:}))
  echo $(( h * 60 + m ))
}

HHMM="${TIME:0:5}"
current_min=$(to_minutes "$HHMM")
current_floor=$(( (current_min / SAVE_INTERVAL) * SAVE_INTERVAL ))

SAVE_FILE="$DATA/last_proactive_save.txt"
next_save_min=$(( current_floor + SAVE_INTERVAL ))

if [[ -f "$SAVE_FILE" ]]; then
  boundary=$(head -1 "$SAVE_FILE" | tr -d '[:space:]')
  if [[ "$boundary" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
    boundary_min=$(to_minutes "$boundary")
    if (( boundary_min >= current_floor )); then
      next_save_min=$(( boundary_min + SAVE_INTERVAL ))
    fi
  fi
fi

echo ""
echo "=== SAVE_BOUNDARY ==="
printf "next: %02d:%02d\n" $(( (next_save_min / 60) % 24 )) $(( next_save_min % 60 ))

# --- INITIATIVE ---
TRIGGERS_FILE="$DATA/learned_triggers.json"
echo ""
echo "=== INITIATIVE ==="
if [[ -f "$TRIGGERS_FILE" ]]; then
  TRIGGER_MSG=$(jq -r '.triggers[] | select(.trigger_type == "conversation_start" and .approved == true) | .suggested_line' "$TRIGGERS_FILE" 2>/dev/null | head -1)
  if [[ -n "$TRIGGER_MSG" ]]; then
    echo "$TRIGGER_MSG"
  else
    echo "NONE"
  fi
else
  echo "NONE"
fi

# --- EVAL CONTEXT ---
echo ""
echo "=== EVAL_CONTEXT ==="
echo "handoff_existed: $HANDOFF_EXISTS"
echo "items_count: $ITEMS_COUNT"

# --- USER MESSAGE ---
echo ""
echo "=== USER_MESSAGE ==="
echo "$MESSAGE"
