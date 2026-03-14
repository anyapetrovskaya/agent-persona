#!/usr/bin/env bash
# import-email/pre.sh — parse mbox and gather context for extraction
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="$AP_DIR/data"
CONFIG="$AP_DIR/config.json"
STAGING="$DATA_DIR/.staging"

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
FILE="" PREVIEW=false LIMIT="" SINCE="" BATCH_OFFSET=0 BATCH_SIZE=50
if [[ -n "$INVOCATION" ]]; then
  ARGS_FILE="$STAGING_DIR/import-email-${INVOCATION}.json"
else
  ARGS_FILE="$STAGING_DIR/import-email.json"
fi
if [[ -f "$ARGS_FILE" ]]; then
  FILE=$(jq -r '.file // ""' "$ARGS_FILE")
  PREVIEW=$(jq -r '.preview // false' "$ARGS_FILE")
  LIMIT=$(jq -r '.limit // ""' "$ARGS_FILE")
  SINCE=$(jq -r '.since // ""' "$ARGS_FILE")
  BATCH_OFFSET=$(jq -r '.batch_offset // 0' "$ARGS_FILE")
  BATCH_SIZE=$(jq -r '.batch_size // 50' "$ARGS_FILE")
  rm -f "$ARGS_FILE"
fi
[[ "$PREVIEW" == "true" ]] && PREVIEW=true || PREVIEW=false

# --- Config / debug ---
DEBUG=false
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG")
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false

echo "=== CONFIG ==="
echo "preview=$PREVIEW"

# --- Parse mbox ---
echo ""
echo "=== PARSED_EMAILS ==="
PARSE_CMD=(python3 "$SCRIPT_DIR/parse-mbox.py" --file "$FILE")
[[ -n "$LIMIT" && "$LIMIT" != "null" ]]  && PARSE_CMD+=(--limit "$LIMIT")
[[ -n "$SINCE" && "$SINCE" != "null" ]]  && PARSE_CMD+=(--since "$SINCE")
PARSE_CMD+=(--batch-offset "$BATCH_OFFSET" --batch-size "$BATCH_SIZE")
"${PARSE_CMD[@]}"

# --- Existing knowledge (for dedup) ---
echo ""
echo "=== EXISTING_KNOWLEDGE ==="
KNOWLEDGE_FILE="$DATA_DIR/knowledge/knowledge.json"
if [[ -f "$KNOWLEDGE_FILE" ]]; then
  cat "$KNOWLEDGE_FILE"
else
  echo "[]"
fi

# --- Existing graph entities (for entity verification) ---
echo ""
echo "=== EXISTING_GRAPH_ENTITIES ==="
GRAPH_FILE="$DATA_DIR/knowledge/memory_graph.json"
if [[ -f "$GRAPH_FILE" ]]; then
  jq -r '.nodes[].id' "$GRAPH_FILE"
else
  echo "NONE"
fi

# --- Flags ---
echo ""
echo "=== FLAGS ==="
echo "debug=$DEBUG"
echo "preview=$PREVIEW"
