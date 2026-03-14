#!/usr/bin/env bash
# import-email/task.sh — slim instructions for main agent
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$BASE/config.json"
STAGING="$BASE/data/.staging"

# --- Parse args → stage for sub-agent ---
FILE=""
PREVIEW=false
LIMIT=""
SINCE=""
BATCH_OFFSET=0
BATCH_SIZE=50
SESSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)         FILE="$2"; shift 2 ;;
    --preview)      PREVIEW=true; shift ;;
    --limit)        LIMIT="$2"; shift 2 ;;
    --since)        SINCE="$2"; shift 2 ;;
    --batch-offset) BATCH_OFFSET="$2"; shift 2 ;;
    --batch-size)   BATCH_SIZE="$2"; shift 2 ;;
    --session)      SESSION="$2"; shift 2 ;;
    *)              echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$FILE" ]]; then
  echo "Error: --file PATH is required" >&2
  exit 1
fi

STAGING_DIR="$STAGING"
[[ -n "$SESSION" ]] && STAGING_DIR="$STAGING/$SESSION"
mkdir -p "$STAGING_DIR"
INVOCATION_ID="$(date +%s%N)-${RANDOM}"

jq -n \
  --arg file "$FILE" \
  --argjson preview "$PREVIEW" \
  --arg limit "$LIMIT" \
  --arg since "$SINCE" \
  --argjson batch_offset "$BATCH_OFFSET" \
  --argjson batch_size "$BATCH_SIZE" \
  '{file: $file, preview: $preview, limit: $limit, since: $since, batch_offset: $batch_offset, batch_size: $batch_size}' \
  > "$STAGING_DIR/import-email-${INVOCATION_ID}.json"

# --- Debug flag ---
DEBUG=false
if [[ -f "$CONFIG" ]]; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG")
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false

echo "=== INSTRUCTIONS ==="
echo "spawn: Read agent-persona/tasks/import-email/task.md and execute."
[[ -n "$SESSION" ]] && echo "session: $SESSION"
echo "invocation: $INVOCATION_ID"
echo ""
echo "=== FLAGS ==="
echo "debug: $DEBUG"
