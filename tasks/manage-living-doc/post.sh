#!/usr/bin/env bash
# manage-living-doc/post.sh — write document file (run by sub-agent)
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
DATA="$BASE/data"
STAGING="$DATA/.staging"
DOCS="$DATA/living-docs"

# --- Parse args ---
SESSION=""
INVOCATION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session)    SESSION="$2"; shift 2 ;;
    --invocation) INVOCATION="$2"; shift 2 ;;
    *)            shift ;;
  esac
done

# --- Read result from sub-agent ---
STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
if [[ -n "$INVOCATION" ]]; then
  RESULT_FILE="$STAGING_DIR/manage-living-doc-result-${INVOCATION}.json"
else
  RESULT_FILE="$STAGING_DIR/manage-living-doc-result.json"
fi
if [[ ! -f "$RESULT_FILE" ]]; then
  echo "error: no result file found at $RESULT_FILE" >&2
  exit 1
fi

ACTION=$(jq -r '.action' "$RESULT_FILE")
NAME=$(jq -r '.name' "$RESULT_FILE")
CONTENT=$(jq -r '.content' "$RESULT_FILE")

mkdir -p "$DOCS"

DOC_FILE="$DOCS/${NAME}.md"
printf '%s\n' "$CONTENT" > "$DOC_FILE"

rm -f "$RESULT_FILE"

echo "wrote: $DOC_FILE"
echo "action: $ACTION"
echo "name: $NAME"
