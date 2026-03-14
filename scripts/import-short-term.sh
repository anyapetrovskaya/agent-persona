#!/usr/bin/env bash
# import-short-term.sh — import Cursor IDE transcripts into short-term memory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AP_DIR="$SCRIPT_DIR/.."
CONFIG="$AP_DIR/config.json"
DATA_DIR="$AP_DIR/data"
ST_DIR="$DATA_DIR/short-term"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Import Cursor IDE conversation transcripts into short-term memory.

Options:
  --id <uuid-prefix>   Import a specific session by UUID prefix
  --source <dir>       Override transcript source directory
  --force              Re-import even if session already exists
  -h, --help           Show this help
EOF
  exit 0
}

ID_FILTER="" SOURCE_OVERRIDE="" FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)     ID_FILTER="$2"; shift 2 ;;
    --source) SOURCE_OVERRIDE="$2"; shift 2 ;;
    --force)  FORCE=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$ST_DIR"

TZ="$(jq -r '.timezone // "UTC"' "$CONFIG")"
export TZ

resolve_source_dir() {
  local configured
  configured="$(jq -r '.transcript_source_dir // ""' "$CONFIG")"
  if [[ -n "$configured" ]]; then
    echo "$configured"
    return
  fi
  if [[ -n "${CURSOR_TRANSCRIPTS_DIR:-}" ]]; then
    echo "$CURSOR_TRANSCRIPTS_DIR"
    return
  fi
  # Derive project dir from workspace path: /home/anya/cursor/agent-persona-dev -> home-anya-cursor-agent-persona-dev
  local workspace_root project_dir candidate
  workspace_root="$(git rev-parse --show-toplevel 2>/dev/null)" || workspace_root="$(cd "$SCRIPT_DIR/../.." && pwd)"
  project_dir="${workspace_root#/}"
  project_dir="${project_dir//\//-}"
  candidate="$HOME/.cursor/projects/$project_dir/agent-transcripts"
  if [[ -d "$candidate" ]]; then
    echo "$candidate"
    return
  fi
  echo "ERROR: cannot auto-detect transcript directory. Set transcript_source_dir in config or CURSOR_TRANSCRIPTS_DIR env var." >&2
  exit 1
}

if [[ -n "$SOURCE_OVERRIDE" ]]; then
  SRC_DIR="$SOURCE_OVERRIDE"
else
  SRC_DIR="$(resolve_source_dir)"
fi

if [[ ! -d "$SRC_DIR" ]]; then
  echo "ERROR: source directory does not exist: $SRC_DIR" >&2
  exit 1
fi

imported=0
skipped=0

strip_system_tags() {
  # Remove XML-like system tags and their content, keep only meaningful user text
  # Tags to strip: user_info, open_and_recently_viewed_files, system_reminder,
  #   rules, agent_transcripts, agent_skills, git_status, etc.
  # Preserves content inside <user_query> tags (tags themselves stripped separately)
  sed -E '
    /<user_info>/,/<\/user_info>/d
    /<open_and_recently_viewed_files>/,/<\/open_and_recently_viewed_files>/d
    /<system_reminder>/,/<\/system_reminder>/d
    /<rules>/,/<\/rules>/d
    /<agent_transcripts>/,/<\/agent_transcripts>/d
    /<agent_skills>/,/<\/agent_skills>/d
    /<git_status>/,/<\/git_status>/d
    /<always_applied_workspace_rules>/,/<\/always_applied_workspace_rules>/d
  '
}

clean_user_content() {
  local raw="$1"
  local extracted
  # Try to extract content within <user_query> tags
  extracted="$(echo "$raw" | sed -n '/<user_query>/,/<\/user_query>/p' | sed '1s/.*<user_query>//' | sed '$s/<\/user_query>.*//')"
  if [[ -n "$(echo "$extracted" | tr -d '[:space:]')" ]]; then
    echo "$extracted" | sed '/^$/d'
  else
    echo "$raw" | strip_system_tags | sed '/^$/d'
  fi
}

clean_assistant_content() {
  local raw="$1"
  echo "$raw" | grep -v '^— [0-9]' || true
}

process_transcript() {
  local uuid="$1"
  local src_file="$SRC_DIR/$uuid/$uuid.jsonl"

  if [[ ! -f "$src_file" ]]; then
    return
  fi

  # Check if already imported
  if [[ "$FORCE" != "true" ]]; then
    local existing
    existing="$(find "$ST_DIR" -maxdepth 1 -name "*_${uuid:0:8}.jsonl" 2>/dev/null | head -1)"
    if [[ -n "$existing" ]]; then
      skipped=$((skipped + 1))
      return
    fi
  fi

  local file_epoch file_date
  file_epoch="$(stat --format=%Y "$src_file")"
  file_date="$(date -d "@$file_epoch" +%Y-%m-%d)"

  local out_file="$ST_DIR/${file_date}_${uuid:0:8}.jsonl"
  local tmp_file="${out_file}.tmp"

  local ts_now
  ts_now="$(date -Iseconds)"

  jq -c -n --arg sid "$uuid" --arg ts "$ts_now" \
    '{"_meta":true,"source_id":$sid,"imported_at":$ts,"source":"cursor_transcript"}' > "$tmp_file"

  local turn=0 last_role="" line_count
  line_count="$(wc -l < "$src_file")"
  local turns_written=0

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    local role content
    role="$(echo "$line" | jq -r '.role // empty' 2>/dev/null)" || continue
    [[ -z "$role" ]] && continue
    content="$(echo "$line" | jq -r '[.message.content[]? | select(.type=="text") | .text] | join("\n")' 2>/dev/null)" || continue
    [[ -z "$content" ]] && continue

    local cleaned
    if [[ "$role" == "user" ]]; then
      turn=$((turn + 1))
      cleaned="$(clean_user_content "$content")"
    elif [[ "$role" == "assistant" ]]; then
      cleaned="$(clean_assistant_content "$content")"
    else
      continue
    fi

    # Strip leading/trailing whitespace
    cleaned="$(echo "$cleaned" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d')"

    # Skip if cleaned content too short
    if [[ "${#cleaned}" -lt 3 ]]; then
      continue
    fi

    jq -c -n --arg role "$role" --arg content "$cleaned" --argjson turn "$turn" \
      '{"role":$role,"content":$content,"turn":$turn}' >> "$tmp_file"
    turns_written=1
  done < "$src_file"

  if [[ "$turns_written" -eq 0 ]]; then
    rm -f "$tmp_file"
    skipped=$((skipped + 1))
    return
  fi

  mv "$tmp_file" "$out_file"

  local n_turns
  n_turns="$turn"
  echo "imported: ${uuid:0:8} ($file_date, $n_turns turns)"
  imported=$((imported + 1))
}

for dir in "$SRC_DIR"/*/; do
  [[ ! -d "$dir" ]] && continue
  uuid="$(basename "$dir")"

  # Validate UUID-like format
  [[ ! "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] && continue

  if [[ -n "$ID_FILTER" ]]; then
    [[ "$uuid" != "$ID_FILTER"* ]] && continue
  fi

  process_transcript "$uuid"
done

echo "total: $imported imported, $skipped skipped"
