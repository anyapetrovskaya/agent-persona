#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f data/.first_run ] || exit 1

rm data/.first_run
PERSONALITY="open-to-anything"
[ -f data/active_personality.txt ] && PERSONALITY=$(cat data/active_personality.txt)
cat data/first_greeting.txt
echo "---"
echo "personality: $PERSONALITY"
