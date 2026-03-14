#!/usr/bin/env bash
# manage-conversation/pre.sh — gather context (run by sub-agent)
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
DATA="$BASE/data"
STAGING="$DATA/.staging"
CONVOS="$DATA/conversations"

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
  ARGS_FILE="$STAGING_DIR/manage-conversation-${INVOCATION}.json"
else
  ARGS_FILE="$STAGING_DIR/manage-conversation.json"
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

mkdir -p "$CONVOS"

case "$ACTION" in
  load)
    echo ""
    echo "=== CONVERSATION ==="
    CONVO_FILE="$CONVOS/${NAME}.md"
    if [[ -f "$CONVO_FILE" ]]; then
      echo "exists: true"
      echo "path: $CONVO_FILE"
      echo ""
      cat "$CONVO_FILE"
    else
      echo "exists: false"
    fi

    # Paired living doc
    LIVING_DOC="$DATA/living-docs/${NAME}.md"
    echo ""
    echo "=== PAIRED_LIVING_DOC ==="
    if [[ -f "$LIVING_DOC" ]]; then
      echo "exists: true"
      echo "name: $NAME"
      lines=$(wc -l < "$LIVING_DOC")
      echo "lines: $lines"
      echo ""
      cat "$LIVING_DOC"
    else
      echo "exists: false"
    fi
    ;;

  save)
    echo ""
    echo "=== EXISTING ==="
    CONVO_FILE="$CONVOS/${NAME}.md"
    if [[ -f "$CONVO_FILE" ]]; then
      echo "exists: true"
      cat "$CONVO_FILE"
    else
      echo "exists: false"
    fi
    echo ""
    echo "=== CURRENT_DEFAULT ==="
    DEFAULT="$CONVOS/main_1.md"
    if [[ -f "$DEFAULT" ]]; then
      cat "$DEFAULT"
    else
      echo "NONE"
    fi
    ;;

  new)
    echo ""
    echo "=== SUMMARY ==="
    echo "$SUMMARY"
    ;;

  fork-main)
    echo ""
    echo "=== CURRENT_DEFAULT ==="
    DEFAULT="$CONVOS/main_1.md"
    if [[ -f "$DEFAULT" ]]; then
      cat "$DEFAULT"
    else
      echo "NONE"
    fi

    echo ""
    echo "=== SIBLING_THREADS ==="
    for f in "$CONVOS"/main_*.md; do
      [[ -f "$f" ]] || continue
      fname=$(basename "$f")
      firstline=$(head -1 "$f" 2>/dev/null || echo "")
      echo "- $fname: $firstline"
    done

    echo ""
    echo "=== NEW_THREAD ==="
    # Determine next main thread number
    MAX=1
    for f in "$CONVOS"/main_*.md; do
      [[ -f "$f" ]] || continue
      num=$(basename "$f" .md | sed 's/^main_//')
      if [[ "$num" =~ ^[0-9]+$ ]] && (( num > MAX )); then
        MAX=$num
      fi
    done
    NEXT=$(( MAX + 1 ))
    echo "main_${NEXT}"
    ;;

  list)
    echo ""
    echo "=== CONVERSATIONS ==="
    if [[ -d "$CONVOS" ]]; then
      for f in "$CONVOS"/*.md; do
        [[ -f "$f" ]] || continue
        name=$(basename "$f" .md)
        firstline=$(head -1 "$f" 2>/dev/null || echo "")
        echo "- $name: $firstline"
      done
    else
      echo "(none)"
    fi
    ;;
esac
