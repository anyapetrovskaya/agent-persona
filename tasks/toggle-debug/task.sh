#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/../../config.json"

if [[ ! -f "$CONFIG" ]]; then
  echo "error: config.json not found at $CONFIG" >&2
  exit 1
fi

case "${1:-}" in
  on)  val=true  ;;
  off) val=false ;;
  *)
    echo "usage: task.sh on|off" >&2
    exit 1
    ;;
esac

tmp="$(mktemp)"
if ! jq --argjson v "$val" '.debug = $v' "$CONFIG" > "$tmp"; then
  rm -f "$tmp"
  echo "error: failed to update config.json" >&2
  exit 1
fi
mv "$tmp" "$CONFIG"

echo "debug: $1"
