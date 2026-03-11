#!/usr/bin/env bash
# update.sh — Self-contained agent-persona framework update.
#
# Clones the latest release, syncs framework files, and re-runs init.
# User data is never touched.
#
# Usage:
#   bash agent-persona/scripts/update.sh
#   bash agent-persona/scripts/update.sh --dry-run

set -euo pipefail

RELEASE_REPO="https://github.com/anyapetrovskaya/agent-persona.git"

# ── Defaults ──────────────────────────────────────────────────────────────────
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLONE_DIR=""

DEFAULT_PERSONALITIES="bubbly-chatty.md concise-unbiased.md critic.md expert-laconic.md supportive.md README.md"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--dry-run]"
      echo ""
      echo "Update agent-persona framework files from the latest release."
      echo "User data (data/, config.json) is never touched."
      echo ""
      echo "Options:"
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

# ── Resolve paths ────────────────────────────────────────────────────────────
# Script lives in agent-persona/scripts/, so AP_DIR is one level up.
if [[ -d "$SCRIPT_DIR/../tasks" && -d "$SCRIPT_DIR/../scripts" ]]; then
  AP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  echo "Error: Cannot locate agent-persona/ directory from script path." >&2
  echo "Expected tasks/ and scripts/ alongside this script's parent." >&2
  exit 1
fi

# ── Cleanup trap ─────────────────────────────────────────────────────────────
cleanup() {
  if [[ -n "$CLONE_DIR" && -d "$CLONE_DIR" ]]; then
    rm -rf "$CLONE_DIR"
  fi
}
trap cleanup EXIT

# ── Clone release repo ───────────────────────────────────────────────────────
CLONE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agent-persona-update.XXXXXX")"

echo "============================================================"
echo "  agent-persona update"
echo "============================================================"
echo ""
echo "  Target:   $AP_DIR"
echo "  Source:    $RELEASE_REPO"
if $DRY_RUN; then
  echo "  Mode:     DRY RUN (no changes will be made)"
fi
echo ""

echo "Cloning latest release..."
if ! git clone --depth 1 --quiet "$RELEASE_REPO" "$CLONE_DIR" 2>/dev/null; then
  echo "Error: Failed to clone $RELEASE_REPO" >&2
  echo "Check your network connection and try again." >&2
  exit 1
fi
echo "  done."
echo ""

# Determine source layout — the clone may have agent-persona/ as a subdirectory
# or may itself be the agent-persona directory.
if [[ -d "$CLONE_DIR/agent-persona/tasks" ]]; then
  SOURCE_AP="$CLONE_DIR/agent-persona"
elif [[ -d "$CLONE_DIR/tasks" ]]; then
  SOURCE_AP="$CLONE_DIR"
else
  echo "Error: Cloned repo does not look like an agent-persona release." >&2
  echo "Expected tasks/ directory inside the clone." >&2
  exit 1
fi

# ── Counters ─────────────────────────────────────────────────────────────────
ADDED_COUNT=0
UPDATED_COUNT=0
REMOVED_COUNT=0
UNCHANGED_COUNT=0

# ── Helper: sync a single file with reporting ───────────────────────────────
sync_file() {
  local src="$1"
  local dst="$2"
  local label="$3"

  if [[ ! -f "$src" ]]; then
    return
  fi

  if [[ -f "$dst" ]] && diff -q "$src" "$dst" > /dev/null 2>&1; then
    UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
    return
  fi

  if [[ -f "$dst" ]]; then
    if $DRY_RUN; then
      echo "  [dry-run] would update: $label"
    else
      cp "$src" "$dst"
      echo "  updated: $label"
    fi
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
  else
    if $DRY_RUN; then
      echo "  [dry-run] would add: $label"
    else
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      echo "  added: $label"
    fi
    ADDED_COUNT=$((ADDED_COUNT + 1))
  fi

  if ! $DRY_RUN && [[ -x "$src" ]]; then
    chmod +x "$dst"
  fi
}

# ── Helper: remove a file/dir with reporting ─────────────────────────────────
remove_path() {
  local path="$1"
  local label="$2"

  if $DRY_RUN; then
    echo "  [dry-run] would remove: $label (no longer in source)"
  else
    rm -rf "$path"
    echo "  removed: $label (no longer in source)"
  fi
  REMOVED_COUNT=$((REMOVED_COUNT + 1))
}

# ── 1. Tasks (recursive) ─────────────────────────────────────────────────────
echo "Tasks (tasks/):"

for src_dir in "$SOURCE_AP"/tasks/*/; do
  [[ -d "$src_dir" ]] || continue
  dir_name="$(basename "$src_dir")"
  $DRY_RUN || mkdir -p "$AP_DIR/tasks/$dir_name"

  for src_file in "$src_dir"*; do
    [[ -f "$src_file" ]] || continue
    base="$(basename "$src_file")"
    sync_file "$src_file" "$AP_DIR/tasks/$dir_name/$base" "tasks/$dir_name/$base"
  done

  # Remove files inside this task dir that no longer exist in source
  if [[ -d "$AP_DIR/tasks/$dir_name" ]]; then
    for dst_file in "$AP_DIR/tasks/$dir_name/"*; do
      [[ -f "$dst_file" ]] || continue
      base="$(basename "$dst_file")"
      if [[ ! -f "$src_dir/$base" ]]; then
        remove_path "$dst_file" "tasks/$dir_name/$base"
      fi
    done
  fi
done

# Remove task directories that no longer exist in source
for dst_dir in "$AP_DIR"/tasks/*/; do
  [[ -d "$dst_dir" ]] || continue
  dir_name="$(basename "$dst_dir")"
  if [[ ! -d "$SOURCE_AP/tasks/$dir_name" ]]; then
    remove_path "$dst_dir" "tasks/$dir_name/"
  fi
done

echo ""

# ── 2. Scripts ───────────────────────────────────────────────────────────────
echo "Scripts (scripts/):"

for src_file in "$SOURCE_AP"/scripts/*; do
  [[ -f "$src_file" ]] || continue
  base="$(basename "$src_file")"
  sync_file "$src_file" "$AP_DIR/scripts/$base" "scripts/$base"
done

for dst_file in "$AP_DIR"/scripts/*; do
  [[ -f "$dst_file" ]] || continue
  base="$(basename "$dst_file")"
  if [[ ! -f "$SOURCE_AP/scripts/$base" ]]; then
    remove_path "$dst_file" "scripts/$base"
  fi
done

echo ""

# ── 3. Docs ──────────────────────────────────────────────────────────────────
echo "Docs (docs/):"

for src_file in "$SOURCE_AP"/docs/*; do
  [[ -f "$src_file" ]] || continue
  base="$(basename "$src_file")"
  sync_file "$src_file" "$AP_DIR/docs/$base" "docs/$base"
done

for dst_file in "$AP_DIR"/docs/*; do
  [[ -f "$dst_file" ]] || continue
  base="$(basename "$dst_file")"
  if [[ ! -f "$SOURCE_AP/docs/$base" ]]; then
    remove_path "$dst_file" "docs/$base"
  fi
done

echo ""

# ── 4. Rules ─────────────────────────────────────────────────────────────────
echo "Rules (rules/):"

for src_file in "$SOURCE_AP"/rules/*; do
  [[ -f "$src_file" ]] || continue
  base="$(basename "$src_file")"
  sync_file "$src_file" "$AP_DIR/rules/$base" "rules/$base"
done

for dst_file in "$AP_DIR"/rules/*; do
  [[ -f "$dst_file" ]] || continue
  base="$(basename "$dst_file")"
  if [[ ! -f "$SOURCE_AP/rules/$base" ]]; then
    remove_path "$dst_file" "rules/$base"
  fi
done

echo ""

# ── 5. Personalities (sync defaults, keep user-added) ────────────────────────
echo "Personalities (personalities/):"

for src_file in "$SOURCE_AP"/personalities/*; do
  [[ -f "$src_file" ]] || continue
  base="$(basename "$src_file")"

  is_default=false
  for dp in $DEFAULT_PERSONALITIES; do
    [[ "$base" == "$dp" ]] && is_default=true && break
  done

  if $is_default; then
    sync_file "$src_file" "$AP_DIR/personalities/$base" "personalities/$base"
  else
    if [[ ! -f "$AP_DIR/personalities/$base" ]]; then
      sync_file "$src_file" "$AP_DIR/personalities/$base" "personalities/$base (new default)"
    else
      UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
    fi
  fi
done

for dst_file in "$AP_DIR"/personalities/*; do
  [[ -f "$dst_file" ]] || continue
  base="$(basename "$dst_file")"
  if [[ ! -f "$SOURCE_AP/personalities/$base" ]]; then
    echo "  kept: personalities/$base (user-added)"
  fi
done

echo ""

# ── 6. Data seed template ───────────────────────────────────────────────────
echo "Data seed template (data-empty/):"

if [[ -d "$SOURCE_AP/data-empty" ]]; then
  $DRY_RUN || mkdir -p "$AP_DIR/data-empty"
  for src_file in "$SOURCE_AP"/data-empty/*; do
    [[ -f "$src_file" ]] || continue
    base="$(basename "$src_file")"
    sync_file "$src_file" "$AP_DIR/data-empty/$base" "data-empty/$base"
  done
else
  echo "  (not present in source)"
fi

echo ""

# ── Protected paths ──────────────────────────────────────────────────────────
echo "Protected (NOT touched):"
echo "  data/"
echo "  config.json"
echo ""

# ── Re-run init ──────────────────────────────────────────────────────────────
if ! $DRY_RUN; then
  echo "Running init.sh to apply any new setup steps..."
  echo ""
  bash "$SCRIPT_DIR/init.sh"
  echo ""
fi

# ── Summary ──────────────────────────────────────────────────────────────────
TOTAL_CHANGES=$((ADDED_COUNT + UPDATED_COUNT + REMOVED_COUNT))

echo "============================================================"
if $DRY_RUN; then
  echo "  Dry run complete"
else
  echo "  Update complete"
fi
echo ""
echo "  Added:     $ADDED_COUNT"
echo "  Updated:   $UPDATED_COUNT"
echo "  Removed:   $REMOVED_COUNT"
echo "  Unchanged: $UNCHANGED_COUNT"
echo ""
if [[ $TOTAL_CHANGES -eq 0 ]]; then
  echo "  Already up to date."
else
  echo "  $TOTAL_CHANGES file(s) changed."
fi
echo "============================================================"
