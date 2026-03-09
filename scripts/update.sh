#!/usr/bin/env bash
# update.sh — Update agent-persona framework files without touching user data.
#
# Usage:
#   ./update.sh --source /path/to/agent-persona-repo
#   ./agent-persona/scripts/update.sh                    # from a project with agent-persona installed
#
# Flags:
#   --source DIR   Path to the agent-persona source (repo checkout)
#   --dry-run      Show what would change without making changes

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
SOURCE_DIR=""
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default personalities shipped with the framework
DEFAULT_PERSONALITIES="bubbly-chatty.md concise-unbiased.md critic.md expert-laconic.md supportive.md README.md"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--source DIR] [--dry-run]"
      echo ""
      echo "Update agent-persona framework files in the current project."
      echo ""
      echo "Options:"
      echo "  --source DIR   Path to agent-persona source repo"
      echo "  --dry-run      Show what would change without modifying anything"
      echo "  -h, --help     Show this help"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Run $0 --help for usage." >&2
      exit 1
      ;;
  esac
done

# ── Locate target project ────────────────────────────────────────────────────
# The target is the project we're updating. If this script lives inside
# agent-persona/scripts/, the target is two levels up. Otherwise, look
# for agent-persona/ in the current directory.

TARGET_DIR=""
if [[ -d "$SCRIPT_DIR/../tasks" && -d "$SCRIPT_DIR/../data" ]]; then
  # Script is running from inside agent-persona/scripts/
  TARGET_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
elif [[ -d "./agent-persona/tasks" ]]; then
  TARGET_DIR="$(pwd)"
else
  echo "Error: Cannot find agent-persona/ in current directory." >&2
  echo "Run this script from a project root that has agent-persona/ installed," >&2
  echo "or run it as ./agent-persona/scripts/update.sh" >&2
  exit 1
fi

AP_DIR="$TARGET_DIR/agent-persona"

# ── Locate source ────────────────────────────────────────────────────────────
if [[ -z "$SOURCE_DIR" ]]; then
  echo "============================================================"
  echo "  agent-persona update"
  echo "============================================================"
  echo ""
  echo "No --source specified."
  echo ""
  echo "To update, provide the path to an agent-persona repo checkout:"
  echo ""
  echo "  $0 --source /path/to/agent-persona-repo"
  echo ""
  echo "You can get the latest source with:"
  echo ""
  echo "  git clone https://github.com/USER/agent-persona.git /tmp/agent-persona"
  echo "  $0 --source /tmp/agent-persona"
  echo ""
  exit 1
fi

# Validate source directory
if [[ ! -d "$SOURCE_DIR/agent-persona/tasks" ]]; then
  echo "Error: Source directory does not look like an agent-persona repo." >&2
  echo "Expected to find agent-persona/tasks/ in: $SOURCE_DIR" >&2
  exit 1
fi

# ── Read current version ─────────────────────────────────────────────────────
VERSION_FILE="$TARGET_DIR/.framework-version"
CURRENT_VERSION="unknown"
if [[ -f "$VERSION_FILE" ]]; then
  CURRENT_VERSION="$(cat "$VERSION_FILE")"
fi

SOURCE_VERSION="unknown"
if [[ -f "$SOURCE_DIR/.framework-version" ]]; then
  SOURCE_VERSION="$(cat "$SOURCE_DIR/.framework-version")"
fi

echo "============================================================"
echo "  agent-persona update"
echo "============================================================"
echo ""
echo "  Target:          $TARGET_DIR"
echo "  Source:           $SOURCE_DIR"
echo "  Current version: $CURRENT_VERSION"
echo "  Source version:   $SOURCE_VERSION"
if $DRY_RUN; then
  echo "  Mode:            DRY RUN (no changes will be made)"
fi
echo ""

# ── Helper: copy with reporting ──────────────────────────────────────────────
UPDATED_COUNT=0
SKIPPED_COUNT=0

copy_file() {
  local src="$1"
  local dst="$2"
  local label="$3"

  if [[ ! -f "$src" ]]; then
    return
  fi

  # Check if file differs
  if [[ -f "$dst" ]] && diff -q "$src" "$dst" > /dev/null 2>&1; then
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    return
  fi

  local past_action="updated"
  local inf_action="update"
  if [[ ! -f "$dst" ]]; then
    past_action="added"
    inf_action="add"
  fi

  if $DRY_RUN; then
    echo "  [dry-run] would $inf_action: $label"
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  $past_action: $label"
  fi
  UPDATED_COUNT=$((UPDATED_COUNT + 1))
}

# ── 1. Tasks ─────────────────────────────────────────────────────────────────
echo "Tasks (agent-persona/tasks/):"
for src_file in "$SOURCE_DIR"/agent-persona/tasks/*.md; do
  [[ -f "$src_file" ]] || continue
  base="$(basename "$src_file")"
  copy_file "$src_file" "$AP_DIR/tasks/$base" "tasks/$base"
done

# Remove task files that no longer exist in source
for dst_file in "$AP_DIR"/tasks/*.md; do
  [[ -f "$dst_file" ]] || continue
  base="$(basename "$dst_file")"
  if [[ ! -f "$SOURCE_DIR/agent-persona/tasks/$base" ]]; then
    if $DRY_RUN; then
      echo "  [dry-run] would remove: tasks/$base (no longer in source)"
    else
      rm "$dst_file"
      echo "  removed: tasks/$base (no longer in source)"
    fi
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
  fi
done
echo ""

# ── 2. Scripts ───────────────────────────────────────────────────────────────
echo "Scripts (agent-persona/scripts/):"
for src_file in "$SOURCE_DIR"/agent-persona/scripts/*; do
  [[ -f "$src_file" ]] || continue
  base="$(basename "$src_file")"
  copy_file "$src_file" "$AP_DIR/scripts/$base" "scripts/$base"
  # Preserve executable bit
  if ! $DRY_RUN && [[ -x "$src_file" ]]; then
    chmod +x "$AP_DIR/scripts/$base"
  fi
done
echo ""

# ── 3. Personalities (replace defaults, keep user-added) ─────────────────────
echo "Personalities (agent-persona/personalities/):"
for src_file in "$SOURCE_DIR"/agent-persona/personalities/*; do
  [[ -f "$src_file" ]] || continue
  base="$(basename "$src_file")"

  is_default=false
  for dp in $DEFAULT_PERSONALITIES; do
    [[ "$base" == "$dp" ]] && is_default=true && break
  done

  if $is_default; then
    copy_file "$src_file" "$AP_DIR/personalities/$base" "personalities/$base"
  else
    # New personality from source — only add if not present
    if [[ ! -f "$AP_DIR/personalities/$base" ]]; then
      copy_file "$src_file" "$AP_DIR/personalities/$base" "personalities/$base (new default)"
    fi
  fi
done

# Report user-added personalities that are preserved
for dst_file in "$AP_DIR"/personalities/*; do
  [[ -f "$dst_file" ]] || continue
  base="$(basename "$dst_file")"
  if [[ ! -f "$SOURCE_DIR/agent-persona/personalities/$base" ]]; then
    echo "  kept: personalities/$base (user-added)"
  fi
done
echo ""

# ── 4. Rules ──────────────────────────────────────────────────────────────────
echo "Rules (agent-persona/rules/):"
for src_file in "$SOURCE_DIR"/agent-persona/rules/*; do
  [[ -f "$src_file" ]] || continue
  base="$(basename "$src_file")"
  copy_file "$src_file" "$AP_DIR/rules/$base" "rules/$base"
done

for dst_file in "$AP_DIR"/rules/*; do
  [[ -f "$dst_file" ]] || continue
  base="$(basename "$dst_file")"
  if [[ ! -f "$SOURCE_DIR/agent-persona/rules/$base" ]]; then
    if $DRY_RUN; then
      echo "  [dry-run] would remove: rules/$base (no longer in source)"
    else
      rm "$dst_file"
      echo "  removed: rules/$base (no longer in source)"
    fi
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
  fi
done
echo ""

# ── 5. Cursor rule (copy into .cursor/rules/) ────────────────────────────────
echo "Cursor rules:"
if [[ -f "$SOURCE_DIR/agent-persona/rules/agent-persona.mdc" ]]; then
  copy_file "$SOURCE_DIR/agent-persona/rules/agent-persona.mdc" \
            "$TARGET_DIR/.cursor/rules/agent-persona.mdc" \
            ".cursor/rules/agent-persona.mdc"
fi
echo ""

# ── 6. Docs ───────────────────────────────────────────────────────────────────
echo "Docs (agent-persona/docs/):"
for src_file in "$SOURCE_DIR"/agent-persona/docs/*; do
  [[ -f "$src_file" ]] || continue
  base="$(basename "$src_file")"
  copy_file "$src_file" "$AP_DIR/docs/$base" "docs/$base"
done

for dst_file in "$AP_DIR"/docs/*; do
  [[ -f "$dst_file" ]] || continue
  base="$(basename "$dst_file")"
  if [[ ! -f "$SOURCE_DIR/agent-persona/docs/$base" ]]; then
    if $DRY_RUN; then
      echo "  [dry-run] would remove: docs/$base (no longer in source)"
    else
      rm "$dst_file"
      echo "  removed: docs/$base (no longer in source)"
    fi
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
  fi
done
echo ""

# ── NEVER touch agent-persona/data/ (except personalities above) ─────────────
echo "Protected (NOT touched):"
echo "  agent-persona/data/episodic/"
echo "  agent-persona/data/knowledge/"
echo "  agent-persona/data/base_persona.json"
echo "  agent-persona/data/learned_triggers.json"
echo "  agent-persona/data/current_session_handoff.md"
echo "  agent-persona/data/procedural_notes.json"
echo ""

# ── 7. Write new version ────────────────────────────────────────────────────
if [[ "$SOURCE_VERSION" != "unknown" ]]; then
  if $DRY_RUN; then
    echo "Version: would update .framework-version to $SOURCE_VERSION"
  else
    echo "$SOURCE_VERSION" > "$VERSION_FILE"
    echo "Version: updated .framework-version to $SOURCE_VERSION"
  fi
elif [[ -f "$SOURCE_DIR/.framework-version" ]]; then
  : # Source has version file but it's empty — skip
else
  if $DRY_RUN; then
    echo "Version: no .framework-version in source — would skip"
  else
    echo "Version: no .framework-version in source — skipped"
  fi
fi
echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo "============================================================"
if $DRY_RUN; then
  echo "  Dry run complete: $UPDATED_COUNT file(s) would change, $SKIPPED_COUNT unchanged"
else
  echo "  Update complete: $UPDATED_COUNT file(s) updated, $SKIPPED_COUNT unchanged"
fi
echo "============================================================"
