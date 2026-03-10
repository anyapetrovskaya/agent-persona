#!/usr/bin/env bash
cd "$(dirname "$0")/.."
TZ=$(grep -o '"timezone"[[:space:]]*:[[:space:]]*"[^"]*"' config.json 2>/dev/null | grep -o '"[^"]*"$' | tr -d '"')
if [ "$1" = "--debug" ]; then
  TZ="${TZ:-UTC}" date +%H:%M:%S
else
  TZ="${TZ:-UTC}" date +%H:%M
fi
