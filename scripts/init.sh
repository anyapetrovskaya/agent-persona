#!/usr/bin/env bash
# Initialize the agent-persona repo for in-place use.
#
# Usage:
#   ./agent-persona/scripts/init.sh
#   ./agent-persona/scripts/init.sh --git-sync

set -euo pipefail

# ── Resolve paths ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$AP_DIR" && git rev-parse --show-toplevel 2>/dev/null || echo "$AP_DIR")"

# ── Parse arguments ──────────────────────────────────────────────────────────

GIT_SYNC=false

for arg in "$@"; do
  case "$arg" in
    --git-sync) GIT_SYNC=true ;;
    -h|--help)
      echo "Usage: $0 [--git-sync]"
      echo ""
      echo "Initializes agent-persona for in-place use."
      echo ""
      echo "Flags:"
      echo "  --git-sync   Enable git_sync in config.json"
      echo "  -h, --help   Show this help message"
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $arg" >&2
      echo "Usage: $0 [--git-sync]" >&2
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

# ── Handle --git-sync ────────────────────────────────────────────────────────

CONFIG_STATUS=""
if [ "$GIT_SYNC" = true ]; then
  CONFIG="$AP_DIR/config.json"
  if [ -f "$CONFIG" ]; then
    sed -i 's/"git_sync": false/"git_sync": true/' "$CONFIG"
  else
    echo '{"git_sync": true}' > "$CONFIG"
  fi
  CONFIG_STATUS="git_sync: true"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "agent-persona initialized."
echo ""
echo "  data/          $DATA_STATUS"
echo "  .cursor/rules/ $RULE_STATUS"
if [ -n "$CONFIG_STATUS" ]; then
  echo "  config.json    $CONFIG_STATUS"
fi
echo ""
echo "Open this folder in Cursor and say hi."
