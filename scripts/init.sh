#!/usr/bin/env bash
# Initialize the agent-persona repo for in-place use.
#
# Usage:
#   ./agent-persona/scripts/init.sh
#   ./agent-persona/scripts/init.sh --web

set -euo pipefail

# ── Resolve paths ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$AP_DIR" && git rev-parse --show-toplevel 2>/dev/null || echo "$AP_DIR")"

# ── Parse arguments ──────────────────────────────────────────────────────────

WEB_MODE=false

for arg in "$@"; do
  case "$arg" in
    --web) WEB_MODE=true ;;
    -h|--help)
      echo "Usage: $0 [--web]"
      echo ""
      echo "Initializes agent-persona for in-place use."
      echo ""
      echo "Flags:"
      echo "  --web        Set up for Cursor Web (enables git sync, open-to-anything personality)"
      echo "  -h, --help   Show this help message"
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $arg" >&2
      echo "Usage: $0 [--web]" >&2
      exit 1
      ;;
  esac
done

# ── Seed data ────────────────────────────────────────────────────────────────

DATA_STATUS="Already existed"
SEEDED=false

if [ -d "$AP_DIR/data" ]; then
  echo "Existing data/ found -- skipping seed."
else
  if [ -d "$AP_DIR/data-empty" ]; then
    cp -r "$AP_DIR/data-empty" "$AP_DIR/data"
    SEEDED=true
    DATA_STATUS="Seeded from data-empty/"
    echo "data/ seeded from data-empty/. OK"
  else
    echo "Error: data-empty/ not found in $AP_DIR" >&2
    exit 1
  fi
fi

# ── Create .first_run sentinel ───────────────────────────────────────────────

if [ "$SEEDED" = true ]; then
  touch "$AP_DIR/data/.first_run"
fi

# ── Set up Cursor rules ─────────────────────────────────────────────────────

mkdir -p "$REPO_ROOT/.cursor/rules"

RULE_STATUS="not found -- skipped"
if [ -f "$AP_DIR/rules/agent-persona.mdc" ]; then
  cp "$AP_DIR/rules/agent-persona.mdc" "$REPO_ROOT/.cursor/rules/agent-persona.mdc"
  RULE_STATUS="Agent rule installed"
fi

# ── Handle --web mode ────────────────────────────────────────────────────────

CONFIG_STATUS=""
if [ "$WEB_MODE" = true ]; then
  CONFIG="$AP_DIR/config.json"
  if [ -f "$CONFIG" ]; then
    sed -i 's/"git_sync": false/"git_sync": true/' "$CONFIG"
  else
    echo '{"git_sync": true}' > "$CONFIG"
  fi
  CONFIG_STATUS="git_sync: true"

  # Set default personality to open-to-anything
  PERSONA="$AP_DIR/data/base_persona.json"
  if [ -f "$PERSONA" ]; then
    sed -i 's/"default_mode": "[^"]*"/"default_mode": "open-to-anything"/' "$PERSONA"
  fi

  # Set active personality
  echo "open-to-anything" > "$AP_DIR/data/active_personality.txt"

  CONFIG_STATUS="git_sync: true, personality: open-to-anything"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "agent-persona initialized."
echo ""
echo "  data/          $DATA_STATUS"
echo "  .cursor/rules/ $RULE_STATUS"
if [ -n "$CONFIG_STATUS" ]; then
  echo "  config         $CONFIG_STATUS"
fi
echo ""
echo "Open this folder in Cursor and say hi."
