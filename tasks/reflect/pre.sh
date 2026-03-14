#!/usr/bin/env bash
# reflect/pre.sh — gather all data for reflection (run by sub-agent)
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
DATA="$BASE/data"
STAGING="$DATA/.staging"

# --- Parse script args ---
SESSION=""
INVOCATION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session)    SESSION="$2"; shift 2 ;;
    --invocation) INVOCATION="$2"; shift 2 ;;
    *)            shift ;;
  esac
done

# --- Read staged args from task.sh ---
STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
EPISODES=""
if [[ -n "$INVOCATION" ]]; then
  ARGS_FILE="$STAGING_DIR/reflect-${INVOCATION}.args"
else
  ARGS_FILE="$STAGING_DIR/reflect.args"
fi
if [[ -f "$ARGS_FILE" ]]; then
  EPISODES=$(<"$ARGS_FILE")
  rm -f "$ARGS_FILE"
fi

# --- Last reflection date ---
echo "=== LAST_REFLECTION ==="
REFLECTIONS_FILE="$DATA/eval/reflections.json"
LAST_REF_DATE=""
if [[ -f "$REFLECTIONS_FILE" ]]; then
  LAST_REF_DATE=$(jq -r '
    if type == "array" then (last // {}) | .date // ""
    elif .reflections then (.reflections | last // {}) | .date // ""
    else ""
    end
  ' "$REFLECTIONS_FILE")
fi
echo "date: ${LAST_REF_DATE:-never}"

# --- Episodic records ---
echo ""
echo "=== EPISODES ==="

if [[ -n "$EPISODES" ]]; then
  IFS=',' read -ra EP_IDS <<< "$EPISODES"
  for ep_id in "${EP_IDS[@]}"; do
    ep_id=$(echo "$ep_id" | tr -d '[:space:]')
    for dir in "$DATA/episodic" "$DATA/episodic/archived"; do
      f="$dir/${ep_id}.json"
      [[ -f "$f" ]] || continue
      echo "--- $ep_id ---"
      jq -c '.' "$f"
    done
  done
else
  found_any=false
  for dir in "$DATA/episodic" "$DATA/episodic/archived"; do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/episode_*.json; do
      [[ -f "$f" ]] || continue
      fname=$(basename "$f" .json)
      ep_date="${fname#episode_}"
      ep_date="${ep_date%%_T*}"
      if [[ -n "$LAST_REF_DATE" ]] && [[ "$ep_date" < "$LAST_REF_DATE" ]]; then
        continue
      fi
      found_any=true
      echo "--- $fname ---"
      jq -c '.' "$f"
    done
  done
  $found_any || echo "none"
fi

# --- Eval log ---
echo ""
echo "=== EVAL_LOG ==="
EVAL_FILE="$DATA/eval/eval_log.json"
if [[ -f "$EVAL_FILE" ]]; then
  jq -c '.' "$EVAL_FILE"
else
  echo "not found"
fi

# --- Eval baseline ---
echo ""
echo "=== EVAL_BASELINE ==="
BASELINE_FILE="$DATA/eval/baseline.json"
if [[ -f "$BASELINE_FILE" ]]; then
  jq -c '.' "$BASELINE_FILE"
else
  echo "not found"
fi

# --- Previous reflections ---
echo ""
echo "=== REFLECTIONS ==="
if [[ -f "$REFLECTIONS_FILE" ]]; then
  jq -c '.' "$REFLECTIONS_FILE"
else
  echo "not found"
fi

# --- Procedural notes ---
echo ""
echo "=== PROCEDURAL_NOTES ==="
NOTES_FILE="$DATA/procedural_notes.json"
if [[ -f "$NOTES_FILE" ]]; then
  jq -c '.' "$NOTES_FILE"
else
  echo "not found"
fi
