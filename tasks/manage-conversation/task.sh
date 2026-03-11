#!/usr/bin/env bash
# manage-conversation/task.sh — named conversation management
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$BASE/config.json"
STAGING="$BASE/data/.staging"

# --- Parse args ---
ACTION="" NAME="" SUMMARY="" SESSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)  ACTION="$2"; shift 2 ;;
    --name)    NAME="$2"; shift 2 ;;
    --summary) SUMMARY="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    *)         echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -z "$ACTION" ]] && { echo "ERROR: --action required (save|load|new|list)" >&2; exit 1; }
if [[ "$ACTION" != "list" ]] && [[ -z "$NAME" ]]; then
  echo "ERROR: --name required for action '$ACTION'" >&2; exit 1
fi

# --- Stage args ---
STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
mkdir -p "$STAGING_DIR"
jq -n --arg action "$ACTION" --arg name "${NAME:-}" --arg summary "${SUMMARY:-}" \
  '{action: $action, name: $name, summary: $summary}' > "$STAGING_DIR/manage-conversation.json"

# --- Debug flag ---
DEBUG=false
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG")
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false

echo "=== INSTRUCTIONS ==="
echo "spawn: Read agent-persona/tasks/manage-conversation/task.md and execute."
if [[ -n "$SESSION" ]]; then
  echo "session: $SESSION"
fi
echo ""
echo "=== FLAGS ==="
echo "debug: $DEBUG"
