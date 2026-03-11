#!/usr/bin/env bash
cd "$(dirname "$0")/.."
TZ=$(jq -r '.timezone // empty' config.json 2>/dev/null || true)
DEBUG=$(jq -r '.debug // false' config.json 2>/dev/null || echo false)
if [ "$DEBUG" = "true" ]; then
  TZ="${TZ:-UTC}" date +%H:%M:%S
  date +%s
else
  TZ="${TZ:-UTC}" date +%H:%M
fi
