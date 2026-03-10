#!/usr/bin/env bash
# Delete a Cursor Web agent-persona instance for a specific user.
#
# Usage:
#   ./scripts/delete-web-user.sh <username> [--force]
#
# Deletes the GitHub repo anyapetrovskaya/<username>-agent-persona
# and the local directory at ~/cursor/<username>-agent-persona.

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────

FORCE=false
USERNAME=""

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *) USERNAME="$arg" ;;
  esac
done

if [ -z "$USERNAME" ]; then
  echo "Usage: $0 <username> [--force]" >&2
  echo "  username: lowercase alphanumeric + hyphens" >&2
  exit 1
fi

# ── Set variables ────────────────────────────────────────────────────────────

REPO_NAME="${USERNAME}-agent-persona"
REPO_FULL="anyapetrovskaya/$REPO_NAME"
WORK_DIR="$HOME/cursor/$REPO_NAME"

# ── Check what exists ────────────────────────────────────────────────────────

REPO_EXISTS=false
DIR_EXISTS=false

if gh repo view "$REPO_FULL" &>/dev/null; then
  REPO_EXISTS=true
fi

if [ -d "$WORK_DIR" ]; then
  DIR_EXISTS=true
fi

if ! $REPO_EXISTS && ! $DIR_EXISTS; then
  echo "Nothing to delete — repo $REPO_FULL and directory $WORK_DIR not found."
  exit 0
fi

# ── Confirm ──────────────────────────────────────────────────────────────────

echo "Will delete:"
$REPO_EXISTS && echo "  GitHub repo:  $REPO_FULL"
$DIR_EXISTS  && echo "  Local dir:    $WORK_DIR"
echo ""

if ! $FORCE; then
  read -rp "Continue? (y/N) " answer
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# ── Delete ───────────────────────────────────────────────────────────────────

if $REPO_EXISTS; then
  echo "Deleting GitHub repo $REPO_FULL ..."
  gh repo delete "$REPO_FULL" --yes
  echo "  ✓ Repo deleted"
fi

if $DIR_EXISTS; then
  echo "Removing local directory $WORK_DIR ..."
  rm -rf "$WORK_DIR"
  echo "  ✓ Directory removed"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "Done! Cleaned up agent-persona for: $USERNAME"
$REPO_EXISTS && echo "  Repo deleted:  $REPO_FULL"
$DIR_EXISTS  && echo "  Dir removed:   $WORK_DIR"
echo ""
