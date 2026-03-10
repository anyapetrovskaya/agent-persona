#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f data/.first_run ] || exit 1

GREETING=$(cat data/first_greeting.txt)
PERSONALITY="open-to-anything"
[ -f data/active_personality.txt ] && PERSONALITY=$(cat data/active_personality.txt)

DIRECTIVE=""
PERSONALITY_FILE="personalities/${PERSONALITY}.md"
[ -f "$PERSONALITY_FILE" ] && DIRECTIVE=$(cat "$PERSONALITY_FILE")

rm data/.first_run

echo "$GREETING"
echo "---"
echo "personality: $PERSONALITY"
if [ -n "$DIRECTIVE" ]; then
  echo "directive:"
  echo "$DIRECTIVE"
fi
