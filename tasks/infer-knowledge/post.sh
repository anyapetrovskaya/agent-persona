#!/usr/bin/env bash
# infer-knowledge/post.sh — append short-term cleanup output to report
set -euo pipefail

AP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT=$(cat)

# Run short-term cleanup (non-blocking: log warning on failure, don't fail post.sh)
set +e
CLEANUP_OUT=$(bash "$AP_DIR/scripts/cleanup-short-term.sh" 2>&1)
CLEANUP_EXIT=$?
set -e
if [[ $CLEANUP_EXIT -ne 0 ]]; then
  echo "post.sh: warning: short-term cleanup failed" >&2
  CLEANUP_OUT="${CLEANUP_OUT:-cleanup failed}"
fi

# Output report + cleanup section
echo "$REPORT"
echo ""
echo "## Short-term cleanup"
echo "$CLEANUP_OUT"
