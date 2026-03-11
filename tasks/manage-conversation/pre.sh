#!/usr/bin/env bash
# manage-conversation/pre.sh — gather context (run by sub-agent)
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

# --- Read staged args ---
STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
ARGS_FILE="$STAGING_DIR/manage-conversation.json"

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
    DEFAULT="$CONVOS/_default.md"
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
