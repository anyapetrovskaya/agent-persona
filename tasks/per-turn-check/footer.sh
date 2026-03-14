#!/usr/bin/env bash
# per-turn-check/footer.sh — generate turn footer
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
CONFIG="$BASE/config.json"

# Parse optional args
epoch=0
agents=0
calls=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --epoch)  epoch="${2:-0}"; shift 2 ;;
    --agents) agents="${2:-0}"; shift 2 ;;
    --calls)  calls="${2:-0}"; shift 2 ;;
    *) shift ;;
  esac
done

# Read config
DEBUG=false
TZ_VAL=""
if [[ -f "$CONFIG" ]] && command -v jq &>/dev/null; then
  DEBUG=$(jq -r '.debug // false' "$CONFIG" 2>/dev/null || echo false)
  TZ_VAL=$(jq -r '.timezone // empty' "$CONFIG" 2>/dev/null || true)
fi
[[ "$DEBUG" == "true" ]] && DEBUG=true || DEBUG=false
export TZ="${TZ_VAL:-UTC}"

# Current time as HH:MM
HHMM=$(date +%H:%M)

current_epoch=$(date +%s)
dt=$((current_epoch - epoch))

if $DEBUG; then
  printf '— %s — wall: %ds | agents: %s | calls: %s\n' "$HHMM" "$dt" "$agents" "$calls"
else
  printf '— %s\n' "$HHMM"
fi

if (( dt > 0 )); then
  bash "$BASE/scripts/eval-append.sh" --type turn_metric \
    --wall_seconds "$dt" --agents "$agents" --calls "$calls" &>/dev/null &
fi

# Completion chime (background, fail-silent)
SOUND="/usr/share/sounds/freedesktop/stereo/complete.oga"
if [[ -f "$SOUND" ]]; then
  paplay "$SOUND" &>/dev/null &
fi
