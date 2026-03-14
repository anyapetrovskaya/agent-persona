#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR/.."
KNOWLEDGE="$BASE/data/knowledge/knowledge.json"
ARCHIVED_KNOWLEDGE="$BASE/data/knowledge/archived_knowledge.json"
SURFACE_QUEUE="$BASE/data/knowledge/surface_queue.json"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Phase 3 graceful forgetting — manage knowledge decay, archival, and surfacing.

Commands:
  status    Show decay status report
  pin       Pin a knowledge item (immune to decay)
  unpin     Unpin a knowledge item
  forget    Archive a knowledge item
  surface   Show items needing attention
  restore   Restore an archived item
  archive   Show all archived items

Run '$(basename "$0") <command> --help' for command-specific options.
EOF
  exit 0
}

ensure_file() {
  local file="$1" default="$2"
  if [[ ! -f "$file" ]]; then
    echo "$default" > "$file"
  fi
}

write_json() {
  local target="$1"
  local tmp="$target.tmp"
  jq '.' > "$tmp" < /dev/stdin
  mv "$tmp" "$target"
}

today() {
  date +%Y-%m-%d
}

preview() {
  local content="$1" max="${2:-60}"
  echo "${content:0:$max}"
}

validate_index() {
  local file="$1" index="$2" label="${3:-items}"
  local count
  count=$(jq '.items | length' "$file")
  if [[ "$index" -lt 0 || "$index" -ge "$count" ]]; then
    echo "ERROR: index $index out of range (0..$((count - 1))) in $label" >&2
    exit 1
  fi
}

# Resolve index from either numeric argument or --match "text"
# Outputs the index to stdout; may print notes to stderr
resolve_index() {
  local file="$1"
  shift
  if [[ $# -eq 1 && "$1" =~ ^[0-9]+$ ]]; then
    echo "$1"
    return
  fi
  if [[ $# -eq 2 && "$1" == "--match" ]]; then
    local search="$2"
    local search_lower
    search_lower=$(echo "$search" | tr '[:upper:]' '[:lower:]')
    local matches
    matches=$(jq -r --arg s "$search_lower" '
      [.items | to_entries[] | select((.value.content | tostring | ascii_downcase | index($s)) != null) | .key]
    ' "$file")
    local count
    count=$(echo "$matches" | jq 'length')
    if [[ "$count" -eq 0 ]]; then
      echo "ERROR: no item found matching \"$search\"" >&2
      exit 1
    fi
    local first
    first=$(echo "$matches" | jq '.[0]')
    if [[ "$count" -gt 1 ]]; then
      echo "Note: $count items match; using first match." >&2
    fi
    echo "$first"
    return
  fi
  echo "ERROR: provide <index> or --match \"text\"" >&2
  exit 1
}

# --- status ---
cmd_status() {
  local category="all"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --category) category="$2"; shift 2 ;;
      -h|--help)
        cat <<EOF
Usage: $(basename "$0") status [--category pinned|healthy|fading|forgotten|all]

Show a compact decay report. Retention scores are pre-computed by compute-decay.sh.

Thresholds:
  pinned    = item.pinned == true
  healthy   = retention_score >= 1.5
  fading    = 0.5 <= retention_score < 1.5
  forgotten = retention_score < 0.5
EOF
        exit 0 ;;
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done

  local total pinned healthy fading forgotten
  total=$(jq '.items | length' "$KNOWLEDGE")
  pinned=$(jq '[.items[] | select(.pinned == true)] | length' "$KNOWLEDGE")
  healthy=$(jq '[.items[] | select(.pinned != true and (.retention_score // 0) >= 1.5)] | length' "$KNOWLEDGE")
  fading=$(jq '[.items[] | select(.pinned != true and (.retention_score // 0) >= 0.5 and (.retention_score // 0) < 1.5)] | length' "$KNOWLEDGE")
  forgotten=$(jq '[.items[] | select(.pinned != true and (.retention_score // 0) < 0.5)] | length' "$KNOWLEDGE")

  echo "=== Decay Status ==="
  echo "Total: $total | Pinned: $pinned | Healthy: $healthy | Fading: $fading | Forgotten: $forgotten"

  if [[ "$category" == "all" ]]; then
    return
  fi

  echo ""

  case "$category" in
    pinned)
      echo "--- Pinned ---"
      jq -r '
        .items | to_entries[]
        | select(.value.pinned == true)
        | "  [\(.key)] \(.value.type // "?"): \(.value.content[0:80])"
      ' "$KNOWLEDGE"
      ;;
    healthy)
      echo "--- Healthy (score >= 1.5) ---"
      jq -r '
        [.items | to_entries[] | select(.value.pinned != true and (.value.retention_score // 0) >= 1.5)]
        | sort_by(-.value.retention_score)
        | .[] | "  [\(.key)] (\(.value.retention_score // "?")) \(.value.type // "?"): \(.value.content[0:80])"
      ' "$KNOWLEDGE"
      ;;
    fading)
      echo "--- Fading (0.5 <= score < 1.5) ---"
      jq -r '
        [.items | to_entries[] | select(.value.pinned != true and (.value.retention_score // 0) >= 0.5 and (.value.retention_score // 0) < 1.5)]
        | sort_by(.value.retention_score)
        | .[] | "  [\(.key)] (\(.value.retention_score // "?")) \(.value.type // "?"): \(.value.content[0:80])"
      ' "$KNOWLEDGE"
      ;;
    forgotten)
      echo "--- Forgotten (score < 0.5) ---"
      jq -r '
        [.items | to_entries[] | select(.value.pinned != true and (.value.retention_score // 0) < 0.5)]
        | sort_by(.value.retention_score)
        | .[] | "  [\(.key)] (\(.value.retention_score // "?")) \(.value.type // "?"): \(.value.content[0:80])"
      ' "$KNOWLEDGE"
      ;;
    *)
      echo "ERROR: unknown category '$category' (use pinned|healthy|fading|forgotten|all)" >&2
      exit 1
      ;;
  esac
}

# --- pin ---
cmd_pin() {
  if [[ $# -lt 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<EOF
Usage: $(basename "$0") pin <index>
       $(basename "$0") pin --match "<text>"

Pin a knowledge item by index or by content match (case-insensitive).
EOF
    exit 0
  fi

  local index
  index=$(resolve_index "$KNOWLEDGE" "$@")
  validate_index "$KNOWLEDGE" "$index"

  local content
  content=$(jq -r --argjson i "$index" '.items[$i].content[0:60]' "$KNOWLEDGE")

  jq --argjson i "$index" '.items[$i].pinned = true' "$KNOWLEDGE" | write_json "$KNOWLEDGE"

  echo "Pinned [$index]: \"$content\""
}

# --- unpin ---
cmd_unpin() {
  if [[ $# -lt 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<EOF
Usage: $(basename "$0") unpin <index>
       $(basename "$0") unpin --match "<text>"

Unpin a knowledge item by index or by content match (case-insensitive).
EOF
    exit 0
  fi

  local index
  index=$(resolve_index "$KNOWLEDGE" "$@")
  validate_index "$KNOWLEDGE" "$index"

  local content
  content=$(jq -r --argjson i "$index" '.items[$i].content[0:60]' "$KNOWLEDGE")

  jq --argjson i "$index" '.items[$i].pinned = false' "$KNOWLEDGE" | write_json "$KNOWLEDGE"

  echo "Unpinned [$index]: \"$content\""
}

# --- forget ---
cmd_forget() {
  if [[ $# -lt 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<EOF
Usage: $(basename "$0") forget <index>
       $(basename "$0") forget --match "<text>"

Archive a knowledge item by index or by content match (case-insensitive).
EOF
    exit 0
  fi

  local index
  index=$(resolve_index "$KNOWLEDGE" "$@")
  validate_index "$KNOWLEDGE" "$index"

  local item
  item=$(jq --argjson i "$index" '.items[$i]' "$KNOWLEDGE")

  local content
  content=$(echo "$item" | jq -r '.content[0:60]')

  local archived_date
  archived_date=$(today)

  # Add to archive
  local archived_item
  archived_item=$(echo "$item" | jq --arg date "$archived_date" --arg reason "user_request" \
    '. + {archived_date: $date, reason: $reason}')

  jq --argjson new_item "$archived_item" \
    '.items += [$new_item] | .archived_count += 1' "$ARCHIVED_KNOWLEDGE" | write_json "$ARCHIVED_KNOWLEDGE"

  # Remove from knowledge
  jq --argjson i "$index" 'del(.items[$i])' "$KNOWLEDGE" | write_json "$KNOWLEDGE"

  echo "Archived [$index]: \"$content\" → archived_knowledge.json"
  echo "Note: indices above $index have shifted down by 1."
}

# --- surface ---
cmd_surface() {
  local limit=5

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      -h|--help)
        cat <<EOF
Usage: $(basename "$0") surface [--limit N]  (default 5)

Show fading and forgotten items that may need attention.
EOF
        exit 0 ;;
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done

  echo "=== Items Needing Attention ==="

  local forgotten_count
  forgotten_count=$(jq '[.items[] | select(.pinned != true and (.retention_score // 0) < 0.5)] | length' "$KNOWLEDGE")

  if [[ "$forgotten_count" -gt 0 ]]; then
    echo ""
    echo "--- Forgotten (score < 0.5) — consider pinning or archiving ---"
    jq -r '
      [.items | to_entries[] | select(.value.pinned != true and (.value.retention_score // 0) < 0.5)]
      | sort_by(.value.retention_score)
      | .[] | "  [\(.key)] (\(.value.retention_score // "?")) \(.value.type // "?"): \(.value.content[0:80])"
    ' "$KNOWLEDGE"
  fi

  echo ""
  echo "--- Fading (lowest scores) — review these ---"
  jq -r --argjson limit "$limit" '
    [.items | to_entries[] | select(.value.pinned != true and (.value.retention_score // 0) >= 0.5 and (.value.retention_score // 0) < 1.5)]
    | sort_by(.value.retention_score)
    | .[:$limit]
    | .[] | "  [\(.key)] (\(.value.retention_score // "?")) \(.value.type // "?"): \(.value.content[0:80])"
  ' "$KNOWLEDGE"

  echo ""
  echo "Actions: pin <index> | forget <index> | (leave to continue fading)"
}

# --- restore ---
cmd_restore() {
  if [[ $# -lt 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $(basename "$0") restore <index>"
    exit 0
  fi

  local index="$1"
  validate_index "$ARCHIVED_KNOWLEDGE" "$index" "archived_knowledge"

  local item
  item=$(jq --argjson i "$index" '.items[$i]' "$ARCHIVED_KNOWLEDGE")

  local content
  content=$(echo "$item" | jq -r '.content[0:60]')

  # Strip archive metadata before restoring
  local restored_item
  restored_item=$(echo "$item" | jq 'del(.archived_date, .reason)')

  jq --argjson new_item "$restored_item" '.items += [$new_item]' "$KNOWLEDGE" | write_json "$KNOWLEDGE"

  # Remove from archive
  jq --argjson i "$index" 'del(.items[$i]) | .archived_count -= 1' "$ARCHIVED_KNOWLEDGE" | write_json "$ARCHIVED_KNOWLEDGE"

  echo "Restored: \"$content\" → knowledge.json"
}

# --- archive ---
cmd_archive() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $(basename "$0") archive"
    exit 0
  fi

  local count
  count=$(jq '.items | length' "$ARCHIVED_KNOWLEDGE")

  echo "=== Archived Knowledge ==="

  if [[ "$count" -eq 0 ]]; then
    echo "(no archived items)"
  else
    jq -r '
      .items | to_entries[]
      | "  [\(.key)] (\(.value.archived_date // "?")) \(.value.type // "?"): \(.value.content[0:80])"
    ' "$ARCHIVED_KNOWLEDGE"
  fi

  echo "Total: $count archived items"
}

# --- main ---
ensure_file "$KNOWLEDGE" '{"items":[]}'
ensure_file "$ARCHIVED_KNOWLEDGE" '{"items":[], "archived_count": 0}'

if [[ $# -lt 1 ]]; then
  usage
fi

CMD="$1"; shift
case "$CMD" in
  status)  cmd_status "$@" ;;
  pin)     cmd_pin "$@" ;;
  unpin)   cmd_unpin "$@" ;;
  forget)  cmd_forget "$@" ;;
  surface) cmd_surface "$@" ;;
  restore) cmd_restore "$@" ;;
  archive) cmd_archive "$@" ;;
  -h|--help) usage ;;
  *) echo "Unknown command: $CMD" >&2; usage ;;
esac
