#!/usr/bin/env bash
set -e

# ── Resolve source (agent-persona/ dir, parent of scripts/) ─────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RELEASE_DIR="$HOME/cursor/agent-persona-release"
COMMIT_MSG="${1:-Update release from dev tree}"

# ── Guard: release repo must be initialized ─────────────────────────────────
if [ ! -d "$RELEASE_DIR/.git" ]; then
  echo "Error: $RELEASE_DIR/.git does not exist. Initialize the release repo first:"
  echo "  mkdir -p $RELEASE_DIR && cd $RELEASE_DIR && git init"
  exit 1
fi

# ── Remove old content (preserve .git) ───────────────────────────────────────
cd "$RELEASE_DIR"
find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} + 2>/dev/null || true

# ── Copy from dev tree ──────────────────────────────────────────────────────
for dir in tasks scripts data-empty personalities rules docs; do
  if [ -d "$SOURCE_DIR/$dir" ]; then
    cp -r "$SOURCE_DIR/$dir" .
  fi
done

[ -f "$SOURCE_DIR/LICENSE" ] && cp "$SOURCE_DIR/LICENSE" .
[ -f "$SOURCE_DIR/README.md" ] && cp "$SOURCE_DIR/README.md" .
[ -f "$SOURCE_DIR/.gitignore" ] && cp "$SOURCE_DIR/.gitignore" .
[ -f "$SOURCE_DIR/config.json" ] && cp "$SOURCE_DIR/config.json" .

# ── Commit and push ─────────────────────────────────────────────────────────
git add -A
if git diff --cached --quiet; then
  echo "No changes to commit; release is up to date."
else
  git status --short
  git commit -m "$COMMIT_MSG"
  git push origin main
  echo ""
  echo "Release pushed to $RELEASE_DIR (origin main)."
fi
echo ""
