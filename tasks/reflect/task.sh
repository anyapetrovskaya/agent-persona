#!/usr/bin/env bash
# reflect/task.sh — slim instructions for main agent
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$BASE/config.json"
STAGING="$BASE/data/.staging"

# --- Parse args → stage for pre.sh ---
EPISODES=""
SESSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --episodes) EPISODES="$2"; shift 2 ;;
    --session)  SESSION="$2"; shift 2 ;;
    *)          echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
mkdir -p "$STAGING_DIR"
if [[ -n "$EPISODES" ]]; then
  printf '%s' "$EPISODES" > "$STAGING_DIR/reflect.args"
else
  rm -f "$STAGING_DIR/reflect.args"
fi

# --- Debug flag (for main's footer) ---
DEBUG=false
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG")
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false

echo "=== INSTRUCTIONS ==="
echo "spawn: Read agent-persona/tasks/reflect/task.md and execute."
[[ -n "$SESSION" ]] && echo "session: $SESSION"
echo ""
echo "=== FLAGS ==="
echo "debug: $DEBUG"
