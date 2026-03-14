#!/usr/bin/env bash
# query-knowledge/pre.sh — gather knowledge stores for query (run by sub-agent)
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

# --- Read staged args ---
STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
QUERY=""
GRAPH_MODE="on"
if [[ -n "$INVOCATION" ]]; then
  ARGS_FILE="$STAGING_DIR/query-knowledge-${INVOCATION}.json"
else
  ARGS_FILE="$STAGING_DIR/query-knowledge.json"
fi
if [[ -f "$ARGS_FILE" ]]; then
  QUERY=$(jq -r '.query // ""' "$ARGS_FILE")
  GRAPH_MODE=$(jq -r '.graph_mode // "on"' "$ARGS_FILE")
  rm -f "$ARGS_FILE"
fi

echo "=== QUERY ==="
echo "$QUERY"

echo ""
echo "=== GRAPH_MODE ==="
echo "$GRAPH_MODE"

# --- Knowledge store ---
KNOWLEDGE_FILE="$DATA/knowledge/knowledge.json"
LAST_INFER=""
ITEMS="[]"
if [[ -f "$KNOWLEDGE_FILE" ]]; then
  LAST_INFER=$(jq -r '.last_infer_date // ""' "$KNOWLEDGE_FILE")
  ITEMS=$(jq -c '.items // []' "$KNOWLEDGE_FILE")
fi

echo ""
echo "=== LAST_INFER_DATE ==="
echo "${LAST_INFER:-never}"

echo ""
echo "=== KNOWLEDGE_ITEMS ==="
echo "$ITEMS"

# --- Unconsolidated episodes ---
echo ""
echo "=== UNCONSOLIDATED_EPISODES ==="

found_any=false
for dir in "$DATA/episodic" "$DATA/episodic/archived"; do
  [[ -d "$dir" ]] || continue
  for f in "$dir"/episode_*.json; do
    [[ -f "$f" ]] || continue
    fname=$(basename "$f" .json)
    ep_date="${fname#episode_}"
    ep_date="${ep_date%%_T*}"
    if [[ -n "$LAST_INFER" ]] && [[ "$ep_date" < "$LAST_INFER" ]]; then
      continue
    fi
    found_any=true
    echo "--- $fname ---"
    jq -c '.records // []' "$f"
  done
done

$found_any || echo "none"

# --- Memory graph ---
echo ""
echo "=== MEMORY_GRAPH ==="
GRAPH_FILE="$DATA/knowledge/memory_graph.json"
if [[ "$GRAPH_MODE" == "on" ]] && [[ -f "$GRAPH_FILE" ]]; then
  jq -c '.' "$GRAPH_FILE"
elif [[ "$GRAPH_MODE" == "on" ]]; then
  echo "not found"
else
  echo "disabled"
fi

# --- Short-term memory search (non-blocking) ---
echo ""
echo "=== SHORT_TERM_MATCHES ==="
if [[ -n "$QUERY" ]]; then
  ST_RESULTS=$("$BASE/scripts/read-short-term.sh" --query "$QUERY" --json 2>/dev/null || true)
  if [[ -n "$ST_RESULTS" ]]; then
    echo "$ST_RESULTS" | head -10
  else
    echo "none"
  fi
else
  echo "none"
fi
