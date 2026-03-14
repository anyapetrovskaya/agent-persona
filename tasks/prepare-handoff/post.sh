#!/usr/bin/env bash
# prepare-handoff/post.sh — persist all handoff artifacts (zero LLM tokens)
# Reads structured agent output from stdin, writes episode + handoff + eval.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$AP_DIR/data"
EVAL_APPEND="$AP_DIR/scripts/eval-append.sh"

# --- Parse args ---
EPISODE="" BOUNDARY="" GIT_SYNC=false CONVERSATION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --episode)      EPISODE="$2"; shift 2 ;;
    --boundary)     BOUNDARY="$2"; shift 2 ;;
    --git-sync)     GIT_SYNC=true; shift ;;
    --conversation) CONVERSATION="$2"; shift 2 ;;
    *)              echo "Unknown arg: $1" >&2; shift ;;
  esac
done
[[ -z "$EPISODE" ]]  && { echo "ERROR: --episode required" >&2; exit 1; }
[[ -z "$BOUNDARY" ]] && { echo "ERROR: --boundary required" >&2; exit 1; }

# --- Read stdin ---
INPUT=$(cat)

extract_section() {
  local name="$1"
  local marker="=== ${name} ==="
  echo "$INPUT" | awk -v m="$marker" '
    $0 == m { found=1; next }
    found && /^=== .+ ===$/ { exit }
    found { print }
  '
}

RECORDS_JSON=$(extract_section "EPISODE_RECORDS")
HANDOFF_MD=$(extract_section "HANDOFF_CONTENT")
INITIATIVE=$(extract_section "INITIATIVE" | sed '/^$/d' | head -1)
EVAL_LINE=$(extract_section "EVAL_DATA" | sed '/^$/d' | head -1)

ISO_TS=$(date -Iseconds)
SESSION_ID=$(basename "$EPISODE" .json)
REPORT=""

# --- 1. Episode file ---
ep_status="skipped"
if [[ -n "$RECORDS_JSON" ]] && echo "$RECORDS_JSON" | jq empty 2>/dev/null; then
  mkdir -p "$(dirname "$EPISODE")"
  if [[ -f "$EPISODE" ]]; then
    if jq --argjson new "$RECORDS_JSON" --arg ts "$ISO_TS" \
        '.records += $new | .updated = $ts' "$EPISODE" > "${EPISODE}.tmp"; then
      mv "${EPISODE}.tmp" "$EPISODE"
      TOTAL=$(jq '.records | length' "$EPISODE")
      ep_status="appended ($TOTAL total)"
    else
      ep_status="FAILED: jq merge"
      rm -f "${EPISODE}.tmp"
    fi
  else
    if jq -n --arg session "$SESSION_ID" --arg created "$ISO_TS" --arg updated "$ISO_TS" \
        --argjson records "$RECORDS_JSON" \
        '{session: $session, created: $created, updated: $updated, records: $records}' > "$EPISODE"; then
      TOTAL=$(jq '.records | length' "$EPISODE")
      ep_status="created ($TOTAL records)"
    else
      ep_status="FAILED: create"
    fi
  fi
fi
REPORT+="Episode: $EPISODE ($ep_status)"$'\n'

# --- 2. Handoff file ---
handoff_status="skipped"
if [[ -n "$CONVERSATION" ]]; then
  HANDOFF_FILE="$DATA_DIR/conversations/${CONVERSATION}.md"
  mkdir -p "$DATA_DIR/conversations"
else
  HANDOFF_FILE="$DATA_DIR/conversations/main_1.md"
  mkdir -p "$DATA_DIR/conversations"
fi
if [[ -n "$HANDOFF_MD" ]]; then
  {
    echo "Last updated: $(date +"%Y-%m-%d %H:%M %Z")"
    echo "**Latest episode:** $SESSION_ID"
    echo ""
    echo "$HANDOFF_MD"
  } > "$HANDOFF_FILE" && handoff_status="updated" || handoff_status="FAILED: write"
fi
REPORT+="Handoff: $HANDOFF_FILE ($handoff_status)"$'\n'

# --- 3. Save boundary ---
boundary_status="skipped"
SAVE_FILE="$DATA_DIR/last_proactive_save.txt"
if echo "$BOUNDARY" > "$SAVE_FILE"; then
  boundary_status="$BOUNDARY"
else
  boundary_status="FAILED: write"
fi
REPORT+="Boundary: $boundary_status"$'\n'

# --- 4. Eval logging ---
eval_status="skipped"
if [[ -n "$EVAL_LINE" ]]; then
  CORRECTIONS=$(echo "$EVAL_LINE" | grep -oP 'corrections=\K[0-9]+' || echo "0")
  TOTAL_REC=$(echo "$EVAL_LINE" | grep -oP 'total_records=\K[0-9]+' || echo "0")
  if bash "$EVAL_APPEND" --type session_summary --session "$SESSION_ID" \
      --corrections "$CORRECTIONS" --total_records "$TOTAL_REC" \
      --episode_id "$SESSION_ID" 2>/dev/null; then
    eval_status="logged"
  else
    eval_status="FAILED: eval-append"
  fi
fi
REPORT+="Eval: $eval_status"$'\n'

# --- 5. Git sync ---
if [[ "$GIT_SYNC" == "true" ]]; then
  git_status="FAILED"
  if (cd "$AP_DIR/.." && git add agent-persona/data/ && \
      git commit -m "agent-persona session update" 2>/dev/null && \
      git push 2>/dev/null); then
    git_status="pushed"
  else
    git_status="FAILED: commit or push"
  fi
  REPORT+="Git sync: $git_status"$'\n'
else
  REPORT+="Git sync: skipped"$'\n'
fi

# --- 6. Initiative ---
if [[ -n "$INITIATIVE" && "$INITIATIVE" != "NOTHING" ]]; then
  REPORT+="Initiative: $INITIATIVE"$'\n'
else
  REPORT+="Initiative: none"$'\n'
fi

echo "$REPORT"

# --- 7. Short-term memory import ---
echo "## Short-term import"
if IMPORT_OUTPUT=$(bash "$AP_DIR/scripts/import-short-term.sh" 2>&1); then
  echo "$IMPORT_OUTPUT"
else
  echo "warning: short-term import failed"
  [[ -n "${IMPORT_OUTPUT:-}" ]] && echo "$IMPORT_OUTPUT"
fi
