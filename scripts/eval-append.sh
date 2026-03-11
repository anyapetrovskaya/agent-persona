#!/usr/bin/env bash
# eval-append.sh — append a typed event to eval_log.json
# Usage: eval-append.sh --type <event_type> [--session <id>] [--key value ...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVAL_FILE="$SCRIPT_DIR/../data/eval/eval_log.json"

TYPE="" SESSION=""
DATA_KEYS=()
DATA_VALS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)    TYPE="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    --*)
      DATA_KEYS+=("${1#--}")
      DATA_VALS+=("$2")
      shift 2
      ;;
    *) shift ;;
  esac
done

[[ -z "$TYPE" ]] && { echo "ERROR: --type required" >&2; exit 1; }

# Create eval_log if missing
if [[ ! -f "$EVAL_FILE" ]]; then
  mkdir -p "$(dirname "$EVAL_FILE")"
  echo '{"schema_version": 1, "events": []}' > "$EVAL_FILE"
fi

TS=$(date -Iseconds)
EVT_ID="evt_$(date +%Y-%m-%dT%H:%M:%S%z)"

# Build data object from key-value pairs
# Convert "true"/"false" to boolean, numeric strings to number, else keep as string
DATA_OBJ="{}"
for ((i=0; i<${#DATA_KEYS[@]}; i++)); do
  DATA_OBJ=$(echo "$DATA_OBJ" | jq --arg k "${DATA_KEYS[$i]}" --arg v "${DATA_VALS[$i]}" \
    '. + {($k): (if $v == "true" then true elif $v == "false" then false elif ($v | test("^[0-9]+$")) then ($v | tonumber) else $v end)}')
done

# Build event (with optional top-level session field)
if [[ -n "$SESSION" ]]; then
  EVENT=$(jq -n \
    --arg id "$EVT_ID" \
    --arg ts "$TS" \
    --arg type "$TYPE" \
    --arg session "$SESSION" \
    --argjson data "$DATA_OBJ" \
    '{id: $id, ts: $ts, type: $type, session: $session, data: $data}')
else
  EVENT=$(jq -n \
    --arg id "$EVT_ID" \
    --arg ts "$TS" \
    --arg type "$TYPE" \
    --argjson data "$DATA_OBJ" \
    '{id: $id, ts: $ts, type: $type, data: $data}')
fi

# Append to events array (atomic via tmp file)
jq --argjson evt "$EVENT" '.events += [$evt]' "$EVAL_FILE" > "${EVAL_FILE}.tmp" \
  && mv "${EVAL_FILE}.tmp" "$EVAL_FILE"

echo "Appended $TYPE event"
