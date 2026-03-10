#!/usr/bin/env bash
cd "$(dirname "$0")/.."
TZ=$(grep -o '"timezone"[[:space:]]*:[[:space:]]*"[^"]*"' config.json 2>/dev/null | grep -o '"[^"]*"$' | tr -d '"')
TZ="${TZ:-UTC}" date +%H:%M
