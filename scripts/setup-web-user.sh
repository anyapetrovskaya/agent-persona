#!/usr/bin/env bash
# Set up a Cursor Web agent-persona instance for a specific user.
#
# Usage:
#   ./scripts/setup-web-user.sh <username>
#
# Creates ~/cursor/<username>-agent-persona/ as the outer project,
# clones agent-persona nested inside it, runs init, applies web config,
# then pushes to a private GitHub repo anyapetrovskaya/<username>-agent-persona.

set -euo pipefail

# ── Validate arguments ───────────────────────────────────────────────────────

if [ $# -lt 1 ]; then
  echo "Usage: $0 <username>" >&2
  echo "  username: lowercase alphanumeric + hyphens" >&2
  exit 1
fi

USERNAME="$1"

if ! [[ "$USERNAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "Error: username must be lowercase alphanumeric (hyphens allowed, not at start/end)" >&2
  exit 1
fi

# ── Set variables ────────────────────────────────────────────────────────────

REPO_NAME="${USERNAME}-agent-persona"
WORK_DIR="$HOME/cursor/$REPO_NAME"
SOURCE_REPO="https://github.com/anyapetrovskaya/agent-persona.git"

# ── Check prerequisites ─────────────────────────────────────────────────────

if ! command -v gh &>/dev/null; then
  echo "Error: gh (GitHub CLI) is required but not found" >&2
  exit 1
fi

if gh repo view "anyapetrovskaya/$REPO_NAME" &>/dev/null; then
  echo "Error: repo anyapetrovskaya/$REPO_NAME already exists" >&2
  exit 1
fi

if [ -d "$WORK_DIR" ]; then
  echo "Error: $WORK_DIR already exists locally" >&2
  exit 1
fi

# ── Create outer project directory ───────────────────────────────────────────

echo "Creating project directory $WORK_DIR ..."
mkdir "$WORK_DIR"
cd "$WORK_DIR"

# ── Clone agent-persona nested inside ────────────────────────────────────────

echo "Cloning agent-persona into $WORK_DIR/agent-persona ..."
git clone "$SOURCE_REPO" agent-persona
rm -rf agent-persona/.git

# ── Initialize agent-persona ─────────────────────────────────────────────────

echo "Running init.sh ..."
bash agent-persona/scripts/init.sh

# ── Apply web-specific config ────────────────────────────────────────────────

echo "Applying web configuration ..."
sed -i 's/"git_sync": false/"git_sync": true/' agent-persona/config.json
sed -i 's/"default_mode": "[^"]*"/"default_mode": "open-to-anything"/' agent-persona/data/base_persona.json
printf 'open-to-anything\n' > agent-persona/data/active_personality.txt

# ── Create repo and push ────────────────────────────────────────────────────

echo "Creating private repo anyapetrovskaya/$REPO_NAME ..."
git init
git add -A
git commit -m "Initial agent-persona setup for $USERNAME"
gh repo create "anyapetrovskaya/$REPO_NAME" --private --source=. --push

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "Done! Agent-persona set up for: $USERNAME"
echo ""
echo "  Repo:    github.com/anyapetrovskaya/$REPO_NAME"
echo "  Layout:  $REPO_NAME/agent-persona/ (nested)"
echo "  Access:  Private -- add $USERNAME as collaborator if needed"
echo "  Usage:   Open in Cursor Web, select Opus 4.6, and start chatting"
echo ""
echo "To add collaborator:"
echo "  gh repo collaborator add anyapetrovskaya/$REPO_NAME <github-username>"
echo ""
