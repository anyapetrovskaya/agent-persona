#!/usr/bin/env bash
# manage-living-doc/pre.sh — gather context (run by sub-agent)
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

# --- Read staged args ---
STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
if [[ -n "$INVOCATION" ]]; then
  ARGS_FILE="$STAGING_DIR/manage-living-doc-${INVOCATION}.json"
else
  ARGS_FILE="$STAGING_DIR/manage-living-doc.json"
fi

ACTION="" NAME="" SUMMARY=""
if [[ -f "$ARGS_FILE" ]]; then
  ACTION=$(jq -r '.action // ""' "$ARGS_FILE")
  NAME=$(jq -r '.name // ""' "$ARGS_FILE")
  SUMMARY=$(jq -r '.summary // ""' "$ARGS_FILE")
  rm -f "$ARGS_FILE"
fi

echo "=== ARGS ==="
echo "action: $ACTION"
echo "name: $NAME"

mkdir -p "$DOCS"

case "$ACTION" in
  read)
    echo ""
    echo "=== DOCUMENT ==="
    DOC_FILE="$DOCS/${NAME}.md"
    if [[ -f "$DOC_FILE" ]]; then
      echo "exists: true"
      echo "path: $DOC_FILE"
      echo ""
      cat "$DOC_FILE"
    else
      echo "exists: false"
    fi
    ;;

  create)
    echo ""
    echo "=== EXISTING ==="
    DOC_FILE="$DOCS/${NAME}.md"
    if [[ -f "$DOC_FILE" ]]; then
      echo "exists: true"
      echo ""
      cat "$DOC_FILE"
    else
      echo "exists: false"
    fi
    echo ""
    echo "=== SUMMARY ==="
    echo "$SUMMARY"
    ;;

  update)
    echo ""
    echo "=== DOCUMENT ==="
    DOC_FILE="$DOCS/${NAME}.md"
    if [[ -f "$DOC_FILE" ]]; then
      echo "exists: true"
      echo "path: $DOC_FILE"
      echo ""
      cat "$DOC_FILE"
    else
      echo "exists: false"
    fi
    # Paired conversation thread (if it exists)
    CONVO_FILE="$DATA/conversations/${NAME}.md"
    echo ""
    echo "=== PAIRED_CONVERSATION ==="
    if [[ -f "$CONVO_FILE" ]]; then
      echo "exists: true"
      echo "path: $CONVO_FILE"
    else
      echo "exists: false"
    fi
    ;;

  list)
    echo ""
    echo "=== DOCUMENTS ==="
    if [[ -d "$DOCS" ]]; then
      found=false
      for f in "$DOCS"/*.md; do
        [[ -f "$f" ]] || continue
        found=true
        name=$(basename "$f" .md)
        lines=$(wc -l < "$f")
        modified=$(date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown")
        firstline=$(head -1 "$f" 2>/dev/null | sed 's/^# //' || echo "")
        echo "- $name: $firstline ($lines lines, updated $modified)"
      done
      if [[ "$found" == false ]]; then
        echo "(none)"
      fi
    else
      echo "(none)"
    fi
    ;;
esac
