#!/usr/bin/env bash
# Export agent-persona (framework + user data) to another project.
# Installs the framework AND copies your existing data to the target.
#
# Usage:
#   ./agent-persona/scripts/export-to-project.sh /path/to/other-project
#   ./agent-persona/scripts/export-to-project.sh --force /path/to/other-project
#   ./agent-persona/scripts/export-to-project.sh --force --git-init /path/to/other-project

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────

FORCE=false
GIT_INIT=false
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --force)    FORCE=true ;;
    --git-init) GIT_INIT=true ;;
    -h|--help)
      echo "Usage: $0 [--force] [--git-init] <target-project-dir>"
      echo ""
      echo "Exports agent-persona framework and user data to another project."
      echo ""
      echo "Flags:"
      echo "  --force      Overwrite existing agent-persona in target without prompting"
      echo "  --git-init   Initialize a git repo in the exported data/ directory"
      echo "  -h, --help   Show this help message"
      exit 0
      ;;
    -*)
      echo "Error: unknown flag: $arg" >&2
      echo "Usage: $0 [--force] [--git-init] <target-project-dir>" >&2
      exit 1
      ;;
    *)
      if [ -n "$TARGET" ]; then
        echo "Error: multiple target directories specified" >&2
        exit 1
      fi
      TARGET="$arg"
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Error: target directory is required" >&2
  echo "Usage: $0 [--force] [--git-init] <target-project-dir>" >&2
  exit 1
fi

# ── Resolve paths ────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Validations ──────────────────────────────────────────────────────────────

if [ ! -d "$ROOT/agent-persona" ]; then
  echo "Error: agent-persona/ not found in $ROOT" >&2
  echo "Run this script from a project that contains agent-persona/." >&2
  exit 1
fi

if [ ! -d "$TARGET" ]; then
  echo "Error: target directory does not exist: $TARGET" >&2
  exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"

if [ "$TARGET" = "$ROOT" ]; then
  echo "Error: target is the same as the source project" >&2
  exit 1
fi

# ── Overwrite check ──────────────────────────────────────────────────────────

if [ -d "$TARGET/agent-persona" ]; then
  if [ "$FORCE" = true ]; then
    echo "⚠  agent-persona/ already exists in target — overwriting (--force)."
  else
    echo "⚠  agent-persona/ already exists in: $TARGET"
    read -rp "Overwrite? [y/N] " confirm
    case "$confirm" in
      [yY][eE][sS]|[yY]) ;;
      *)
        echo "Aborted."
        exit 0
        ;;
    esac
  fi
fi

echo ""
echo "Exporting agent-persona to: $TARGET"
echo ""

# ── Helper: copy directory contents if source exists ─────────────────────────

copy_dir_if_exists() {
  local src="$1" dst="$2"
  if [ -d "$src" ]; then
    mkdir -p "$dst"
    cp -r "$src/." "$dst/"
    return 0
  fi
  return 1
}

# ── 1. Copy framework files ─────────────────────────────────────────────────

echo "Copying framework files..."

copy_dir_if_exists "$ROOT/agent-persona/tasks"         "$TARGET/agent-persona/tasks" \
  && echo "  ✓ tasks/"

copy_dir_if_exists "$ROOT/agent-persona/scripts"       "$TARGET/agent-persona/scripts" \
  && echo "  ✓ scripts/"

copy_dir_if_exists "$ROOT/agent-persona/rules"         "$TARGET/agent-persona/rules" \
  && echo "  ✓ rules/"

copy_dir_if_exists "$ROOT/agent-persona/docs"          "$TARGET/agent-persona/docs" \
  && echo "  ✓ docs/"

copy_dir_if_exists "$ROOT/agent-persona/personalities" "$TARGET/agent-persona/personalities" \
  && echo "  ✓ personalities/" \
  || echo "  – personalities/ not found, skipping"

if [ -f "$ROOT/agent-persona/.framework-version" ]; then
  cp "$ROOT/agent-persona/.framework-version" "$TARGET/agent-persona/.framework-version"
  echo "  ✓ .framework-version"
else
  echo "  – .framework-version not found, skipping"
fi

# ── 2. Copy user data ───────────────────────────────────────────────────────

echo "Copying user data..."

mkdir -p "$TARGET/agent-persona/data"

if command -v rsync &>/dev/null; then
  rsync -a --exclude='.git' "$ROOT/agent-persona/data/" "$TARGET/agent-persona/data/"
else
  cp -r "$ROOT/agent-persona/data/." "$TARGET/agent-persona/data/"
  rm -rf "$TARGET/agent-persona/data/.git" 2>/dev/null || true
fi

echo "  ✓ data/ (excluding .git)"

# ── 3. Copy cursor rule ─────────────────────────────────────────────────────

echo "Copying cursor rule..."

if [ -f "$ROOT/agent-persona/rules/agent-persona.mdc" ]; then
  mkdir -p "$TARGET/.cursor/rules"
  cp "$ROOT/agent-persona/rules/agent-persona.mdc" "$TARGET/.cursor/rules/agent-persona.mdc"
  echo "  ✓ .cursor/rules/agent-persona.mdc (from agent-persona/rules/)"
else
  echo "  ⚠ agent-persona/rules/agent-persona.mdc not found — skipping"
fi

# ── 4. Update target .gitignore ──────────────────────────────────────────────

echo "Updating .gitignore..."

GITIGNORE="$TARGET/.gitignore"
ENTRY="agent-persona/"

if [ -f "$GITIGNORE" ]; then
  if grep -qxF "$ENTRY" "$GITIGNORE"; then
    echo "  ✓ $ENTRY already in .gitignore"
  else
    printf '\n# Agent persona (data managed separately)\n%s\n' "$ENTRY" >> "$GITIGNORE"
    echo "  ✓ Added $ENTRY to .gitignore"
  fi
else
  printf '# Agent persona (data managed separately)\n%s\n' "$ENTRY" > "$GITIGNORE"
  echo "  ✓ Created .gitignore with $ENTRY"
fi

# ── 5. Optional: init git in data/ ──────────────────────────────────────────

if [ "$GIT_INIT" = true ]; then
  echo "Initializing git in data/..."
  git -C "$TARGET/agent-persona/data" init -q
  echo "  ✓ git init in agent-persona/data/"
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Export complete!"
echo "══════════════════════════════════════════════════════"
echo ""
echo "  Target: $TARGET"
echo ""
echo "  Next steps:"
echo "    1. Open $TARGET in Cursor"
echo "    2. The agent will pick up your data and personality"
echo ""
if [ "$GIT_INIT" != true ]; then
  echo "  To version-control your agent data separately:"
  echo "    cd $TARGET/agent-persona/data"
  echo "    git init && git add . && git commit -m 'Import agent-persona data'"
  echo ""
fi
