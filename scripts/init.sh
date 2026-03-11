#!/usr/bin/env bash
# Initialize the agent-persona repo for in-place use.
#
# Usage:
#   ./agent-persona/scripts/init.sh

set -euo pipefail

# ── Resolve paths ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$AP_DIR/.." && pwd)"

# ── Parse arguments ──────────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      echo "Usage: $0"
      echo ""
      echo "Initializes agent-persona for in-place use."
      echo ""
      echo "Flags:"
      echo "  -h, --help   Show this help message"
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $arg" >&2
      echo "Usage: $0" >&2
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

# ── Ensure conversations directory ───────────────────────────────────────────

CONV_DIR="$AP_DIR/data/conversations"
if [ ! -d "$CONV_DIR" ]; then
  mkdir -p "$CONV_DIR"
  cat > "$CONV_DIR/_default.md" << 'HANDOFF'
# Session Handoff

*Last updated: (new install)*

## Current topic / goal
Fresh install — no prior sessions yet.

## Key points
- Agent-persona initialized
- No episodic memory or knowledge yet — these build over time

## Open questions
- None yet
HANDOFF
  echo "conversations/ seeded with _default.md. OK"
fi

# ── Detect timezone ──────────────────────────────────────────────────────────

DETECTED_TZ="UTC"
if command -v timedatectl &>/dev/null; then
  DETECTED_TZ=$(timedatectl show -p Timezone --value 2>/dev/null || echo "UTC")
elif [ -f /etc/timezone ]; then
  DETECTED_TZ=$(cat /etc/timezone)
elif [ -L /etc/localtime ]; then
  DETECTED_TZ=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
fi
DETECTED_TZ="${DETECTED_TZ:-UTC}"

CONFIG="$AP_DIR/config.json"
if [ -f "$CONFIG" ]; then
  if grep -q '"timezone"' "$CONFIG"; then
    sed -i "s|\"timezone\": \"[^\"]*\"|\"timezone\": \"$DETECTED_TZ\"|" "$CONFIG"
  else
    sed -i "s|}$|,\n  \"timezone\": \"$DETECTED_TZ\"\n}|" "$CONFIG"
  fi
fi

# ── Set up Cursor rules ─────────────────────────────────────────────────────

mkdir -p "$REPO_ROOT/.cursor/rules"

RULE_STATUS="not found -- skipped"
if [ -f "$AP_DIR/rules/agent-persona.mdc" ]; then
  cp "$AP_DIR/rules/agent-persona.mdc" "$REPO_ROOT/.cursor/rules/agent-persona.mdc"
  RULE_STATUS="Agent rule installed"
fi

# ── Update parent .gitignore ─────────────────────────────────────────────────

if [ "$AP_DIR" != "$REPO_ROOT" ]; then
  GITIGNORE="$REPO_ROOT/.gitignore"
  ENTRY="agent-persona/"
  if [ -f "$GITIGNORE" ]; then
    if ! grep -qxF "$ENTRY" "$GITIGNORE"; then
      printf '\n%s\n' "$ENTRY" >> "$GITIGNORE"
      echo "Added $ENTRY to .gitignore"
    fi
  else
    printf '%s\n' "$ENTRY" > "$GITIGNORE"
    echo "Created .gitignore with $ENTRY"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
if [ "$SEEDED" = true ]; then
  echo "agent-persona initialized (fresh install)."
else
  echo "agent-persona re-initialized (framework update)."
fi
echo ""
echo "  data/          $DATA_STATUS"
echo "  .cursor/rules/ $RULE_STATUS"
echo "  timezone       $DETECTED_TZ"
echo ""
echo "Open this folder in Cursor and say hi."
