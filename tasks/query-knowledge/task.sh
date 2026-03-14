#!/usr/bin/env bash
# query-knowledge/task.sh — slim instructions for main agent
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$BASE/config.json"
STAGING="$BASE/data/.staging"

# --- Parse args → stage for pre.sh ---
QUERY=""
GRAPH_MODE="on"
SESSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --query)      QUERY="$2"; shift 2 ;;
    --graph-mode) GRAPH_MODE="$2"; shift 2 ;;
    --session)    SESSION="$2"; shift 2 ;;
    *)            echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -z "$QUERY" ]] && { echo "ERROR: --query required" >&2; exit 1; }

STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
mkdir -p "$STAGING_DIR"
INVOCATION_ID="$(date +%s%N)-${RANDOM}"
jq -n --arg query "$QUERY" --arg graph_mode "$GRAPH_MODE" \
  '{query: $query, graph_mode: $graph_mode}' > "$STAGING_DIR/query-knowledge-${INVOCATION_ID}.json"

# --- Debug flag ---
DEBUG=false
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG")
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false

echo "=== INSTRUCTIONS ==="
echo "spawn: Read agent-persona/tasks/query-knowledge/task.md and execute."
[[ -n "$SESSION" ]] && echo "session: $SESSION"
echo "invocation: $INVOCATION_ID"
echo ""
echo "=== FLAGS ==="
echo "debug: $DEBUG"
