#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

BASE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA="$BASE/data"
CONFIG="$BASE/config.json"
STAGING="$DATA/.staging"

PLATFORM="ide"
[[ -f "$CONFIG" ]] && PLATFORM=$(jq -r '.platform // "ide"' "$CONFIG" 2>/dev/null || echo ide)

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

  # --- Identity block from base_persona (who you are, what you can do) ---
  IDENTITY=""
  if [[ -f "$DATA/base_persona.json" ]]; then
    IDENTITY=$(jq -r '.identity // empty | if type == "object" then (.summary // "") + (if .capabilities then "\nCapabilities: " + .capabilities else "" end) + (if .name then "\nName: " + .name else "" end) + (if .pronouns then " (" + .pronouns + ")" else "" end) else "" end' "$DATA/base_persona.json" 2>/dev/null || true)
  fi

  # --- Silent housekeeping (no stdout) before greeting ---
  # On web platform, defer ALL file modifications to turn 1 to avoid
  # triggering Cursor's auto-initiated second turn from visible changes.
  if [[ "$PLATFORM" != "web" ]]; then
    rm -f "$DATA/.first_run"
    [[ ! -f "$DATA/backlog.json" ]] && echo '{"items":[]}' > "$DATA/backlog.json"
    mkdir -p "$DATA/eval"
    [[ ! -f "$DATA/eval/eval_log.json" ]] && echo '{"records":[]}' > "$DATA/eval/eval_log.json"

    if command -v git &>/dev/null && [[ -d "$BASE/../../.git" ]]; then
      GIT_SYNC=$(jq -r '.git_sync // false' "$CONFIG" 2>/dev/null)
      if [[ "$GIT_SYNC" == "true" ]]; then
        (cd "$BASE/../.." && git add -A && git commit -m "First-run initialization" && git push) &>/dev/null || true
      fi
    fi
  fi

  # --- Greeting output ---
  echo "$GREETING"
  echo "---"
  if [[ -n "$IDENTITY" ]]; then
    echo "identity:"
    echo "$IDENTITY"
    echo "---"
  fi
  echo "personality: $PERSONALITY"
  if [[ -n "$DIRECTIVE" ]]; then
    echo "directive:"
    echo "$DIRECTIVE"
  fi
  echo "---"
  HHMM=$(date +%H:%M)
  echo "Output the greeting above verbatim. Follow personality directive for the session. Do NOT run the footer. Do NOT make any git commits, file changes, or additional tool calls. Your ONLY action is to output the greeting."
  [[ "$PLATFORM" == "web" ]] && echo "Your LAST line of response must be: — $HHMM —"
  exit 0
fi

# =============================================================
# RETURNING PATH — run pre.sh + format.sh inline
# =============================================================
[[ -z "$TIME" ]] && TIME=$(date +%H:%M:%S)

MODE="default"
if [[ -n "$MESSAGE" ]]; then
  case "$MESSAGE" in
    *"anon mode"*)       MODE="anon" ;;
    *"standalone mode"*) MODE="standalone" ;;
  esac
fi

if [[ -z "$SESSION" ]]; then
  SESSION="$(date +%s)-${RANDOM}"
fi

# Stage args for pre.sh
STAGING_DIR="$STAGING/$SESSION"
mkdir -p "$STAGING_DIR"
INVOCATION_ID="$(date +%s%N)-${RANDOM}"
jq -n --arg message "$MESSAGE" --arg time "$TIME" --arg mode "$MODE" --arg conversation "${CONVERSATION:-}" \
  '{message: $message, time: $time, mode: $mode, conversation: $conversation}' > "$STAGING_DIR/conversation-start-${INVOCATION_ID}.json"

# Run pre.sh → format.sh pipeline (all bash, no LLM)
PRE_OUTPUT=$(bash "$SCRIPT_DIR/pre.sh" --session "$SESSION" --invocation "$INVOCATION_ID")
FORMATTED=$(echo "$PRE_OUTPUT" | bash "$SCRIPT_DIR/format.sh")

# --- Eval logging (bash heuristic, no LLM grading) ---
HANDOFF_EXISTED=$(echo "$PRE_OUTPUT" | awk '/^=== HANDOFF ===/{found=1; next} found && /^exists:/{print $2; exit}')
ITEMS_COUNT=$(echo "$PRE_OUTPUT" | awk '/^=== EVAL_CONTEXT ===/{found=1; next} found && /^items_count:/{print $2; exit}')
HANDOFF_EXISTED="${HANDOFF_EXISTED:-false}"
ITEMS_COUNT="${ITEMS_COUNT:-0}"

# Heuristic quality: if handoff exists and has >10 lines, good; >0 lines, fair; else poor
if [[ "$HANDOFF_EXISTED" == "true" ]]; then
  if (( ITEMS_COUNT > 10 )); then
    HQ="good"; HR="partial"
  else
    HQ="fair"; HR="partial"
  fi
else
  HQ="poor"; HR="none"
fi

bash "$SCRIPT_DIR/post.sh" --mode "$MODE" --handoff-existed "$HANDOFF_EXISTED" \
  --items-count "$ITEMS_COUNT" --handoff-quality "$HQ" --handoff-relevance "$HR" \
  --reason "heuristic" <<< "" &>/dev/null &

# --- Debug flag ---
DEBUG=false
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG")
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false
if [[ -n "$MESSAGE" ]] && [[ "$MESSAGE" == *"debug on"* ]]; then
  DEBUG=true
fi

# --- Output clean context for main agent ---
echo "$FORMATTED"
echo ""
echo "=== SESSION ==="
echo "session: $SESSION"
echo "debug: $DEBUG"
echo ""
echo "=== INSTRUCTIONS ==="
echo "Output is your session context — absorb it, no sub-agent needed."
