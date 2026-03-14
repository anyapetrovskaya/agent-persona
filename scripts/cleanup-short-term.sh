#!/usr/bin/env bash
# cleanup-short-term.sh — delete short-term files older than retention window
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AP_DIR="$SCRIPT_DIR/.."
CONFIG="$AP_DIR/config.json"
ST_DIR="$AP_DIR/data/short-term"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Delete short-term memory files older than the retention window.

Options:
  --dry-run    Show what would be deleted without deleting
  -h, --help   Show this help
EOF
  exit 0
}

DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

TZ="$(jq -r '.timezone // "UTC"' "$CONFIG")"
export TZ

RETENTION="$(jq -r '.short_term_retention_days // 3' "$CONFIG")"
CUTOFF="$(date -d "$RETENTION days ago" +%Y-%m-%d)"

removed=0
remaining=0

for f in "$ST_DIR"/*.jsonl; do
  [[ ! -f "$f" ]] && continue
  base="$(basename "$f")"
  fdate="${base:0:10}"

  if [[ "$fdate" < "$CUTOFF" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "would remove: $base"
    else
      rm "$f"
    fi
    removed=$((removed + 1))
  else
    remaining=$((remaining + 1))
  fi
done

if [[ "$DRY_RUN" == "true" ]]; then
  echo "dry-run: $removed files would be removed ($remaining remaining)"
else
  echo "cleaned: $removed files removed ($remaining remaining)"
fi
