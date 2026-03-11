#!/usr/bin/env bash
# manage-conversation/post.sh — write conversation file (run by sub-agent)
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
DATA="$BASE/data"
STAGING="$DATA/.staging"
CONVOS="$DATA/conversations"

# --- Parse args ---
SESSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION="$2"; shift 2 ;;
    *)         shift ;;
  esac
done

# --- Read result from sub-agent ---
RESULT_FILE="$STAGING/manage-conversation-result.json"
if [[ ! -f "$RESULT_FILE" ]]; then
  echo "error: no result file found" >&2
  exit 1
fi

ACTION=$(jq -r '.action' "$RESULT_FILE")
NAME=$(jq -r '.name' "$RESULT_FILE")
CONTENT=$(jq -r '.content' "$RESULT_FILE")

mkdir -p "$CONVOS"

CONVO_FILE="$CONVOS/${NAME}.md"
printf '%s\n' "$CONTENT" > "$CONVO_FILE"

rm -f "$RESULT_FILE"

echo "wrote: $CONVO_FILE"
echo "action: $ACTION"
echo "name: $NAME"
