#!/usr/bin/env bash
set -euo pipefail

# ── Resolve source (agent-persona/ dir, one level up from scripts/) ─────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Resolve target (where we're installing into) ───────────────────────────
TARGET_DIR="${1:-.}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
  echo "Error: target directory '${1:-.}' does not exist or is not a directory."
  exit 1
}

REPO_ROOT_CHECK="$(cd "$SOURCE_DIR/.." && pwd)"
if [ "$TARGET_DIR" = "$REPO_ROOT_CHECK" ] || [ "$TARGET_DIR" = "$SOURCE_DIR" ]; then
  echo "Error: cannot install into the framework source directory itself."
  echo "Usage: ./install.sh /path/to/your-project"
  exit 1
fi

echo "Installing agent-persona into: $TARGET_DIR"

# ── Read framework version ─────────────────────────────────────────────────
REPO_ROOT="$(cd "$SOURCE_DIR/.." && pwd)"
if [ -f "$REPO_ROOT/.framework-version" ]; then
  VERSION="$(cat "$REPO_ROOT/.framework-version")"
else
  VERSION="0.3.0"
fi

AP_DIR="$TARGET_DIR/agent-persona"
DATA_DIR="$AP_DIR/data"

# ── Guard: don't clobber existing data ─────────────────────────────────────
if [ -d "$DATA_DIR" ]; then
  echo ""
  echo "Existing data/ found — preserving user data."
  EXISTING_DATA=true
else
  EXISTING_DATA=false
fi

# ── Create directory structure ─────────────────────────────────────────────
mkdir -p "$AP_DIR/tasks"
mkdir -p "$AP_DIR/scripts"
mkdir -p "$AP_DIR/personalities"

# ── Copy framework files (always overwrite — these are "code") ─────────────

# Tasks
if [ -d "$SOURCE_DIR/tasks" ]; then
  cp "$SOURCE_DIR"/tasks/*.md "$AP_DIR/tasks/" 2>/dev/null || true
fi

# Scripts
if [ -d "$SOURCE_DIR/scripts" ]; then
  cp "$SOURCE_DIR"/scripts/* "$AP_DIR/scripts/" 2>/dev/null || true
fi

# Personalities
if [ -d "$SOURCE_DIR/personalities" ]; then
  cp "$SOURCE_DIR"/personalities/* "$AP_DIR/personalities/" 2>/dev/null || true
fi

# Rules (canonical source is agent-persona/rules/)
mkdir -p "$AP_DIR/rules"
if [ -d "$SOURCE_DIR/rules" ]; then
  cp -r "$SOURCE_DIR"/rules/* "$AP_DIR/rules/" 2>/dev/null || true
fi
mkdir -p "$TARGET_DIR/.cursor/rules"
if [ -f "$SOURCE_DIR/rules/agent-persona.mdc" ]; then
  cp "$SOURCE_DIR/rules/agent-persona.mdc" "$TARGET_DIR/.cursor/rules/agent-persona.mdc"
fi

# Docs
mkdir -p "$AP_DIR/docs"
if [ -d "$SOURCE_DIR/docs" ]; then
  cp -r "$SOURCE_DIR"/docs/* "$AP_DIR/docs/" 2>/dev/null || true
fi

# Framework version
echo "$VERSION" > "$AP_DIR/.framework-version"

# ── Seed data (only on fresh install) ──────────────────────────────────────
if [ "$EXISTING_DATA" = false ]; then
  cp -r "$SOURCE_DIR/data-empty" "$DATA_DIR"

  # ── Initialize git repo for data ──────────────────────────────────────
  (
    cd "$DATA_DIR"
    git init -q
    git add -A
    git commit -q -m "Initial seed data"
  )
fi

# ── .gitignore in target project ───────────────────────────────────────────
GITIGNORE="$TARGET_DIR/.gitignore"
if [ -f "$GITIGNORE" ]; then
  if ! grep -qxF 'agent-persona/' "$GITIGNORE"; then
    echo "" >> "$GITIGNORE"
    echo "agent-persona/" >> "$GITIGNORE"
  fi
else
  echo "agent-persona/" > "$GITIGNORE"
fi

# ── Done ───────────────────────────────────────────────────────────────────
echo ""
echo "agent-persona installed in: $TARGET_DIR"
echo ""
echo "  agent-persona/          Framework + your data"
echo "  .cursor/rules/          Agent rules (for Cursor)"
echo ""
echo "Open this project in Cursor and say hi."
echo ""
echo "Optional: version your agent data"
echo "  cd $TARGET_DIR/agent-persona/data"
echo "  git remote add origin <your-private-repo>"
echo "  git push -u origin main"
