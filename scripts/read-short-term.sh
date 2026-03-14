#!/usr/bin/env bash
# read-short-term.sh — read/search short-term memory store
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AP_DIR="$SCRIPT_DIR/.."
CONFIG="$AP_DIR/config.json"
ST_DIR="$AP_DIR/data/short-term"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Read and search short-term memory.

Options:
  --query <text>    Search for text pattern (case-insensitive)
  --session <id>    Show all content from a session (uuid prefix match)
  --list            List available sessions with metadata
  --days <N>        Limit to last N days (default: from config)
  --json            Output as JSON instead of human-readable
  -h, --help        Show this help
EOF
  exit 0
}

QUERY="" SESSION="" LIST=false DAYS="" JSON_OUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query)   QUERY="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    --list)    LIST=true; shift ;;
    --days)    DAYS="$2"; shift 2 ;;
    --json)    JSON_OUT=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$QUERY" && -z "$SESSION" && "$LIST" != "true" ]]; then
  echo "ERROR: specify --query, --session, or --list" >&2
  exit 1
fi

TZ="$(jq -r '.timezone // "UTC"' "$CONFIG")"
export TZ

if [[ -z "$DAYS" ]]; then
  DAYS="$(jq -r '.short_term_retention_days // 3' "$CONFIG")"
fi

cutoff_date() {
  date -d "$DAYS days ago" +%Y-%m-%d
}

file_in_range() {
  local fname="$1" cutoff="$2"
  local fdate="${fname:0:10}"
  [[ "$fdate" > "$cutoff" || "$fdate" == "$cutoff" ]]
}

get_files_in_range() {
  local cutoff
  cutoff="$(cutoff_date)"
  for f in "$ST_DIR"/*.jsonl; do
    [[ ! -f "$f" ]] && continue
    local base
    base="$(basename "$f")"
    if file_in_range "$base" "$cutoff"; then
      echo "$f"
    fi
  done
}

do_list() {
  local cutoff
  cutoff="$(cutoff_date)"

  if [[ "$JSON_OUT" == "true" ]]; then
    local first=true
    echo "["
  else
    printf "%-12s %-10s %6s  %s\n" "DATE" "ID" "TURNS" "SOURCE_ID"
    printf "%-12s %-10s %6s  %s\n" "----" "--" "-----" "---------"
  fi

  for f in "$ST_DIR"/*.jsonl; do
    [[ ! -f "$f" ]] && continue
    local base
    base="$(basename "$f")"
    file_in_range "$base" "$cutoff" || continue

    local fdate sid short_id turns
    fdate="${base:0:10}"
    short_id="${base:11}"
    short_id="${short_id%.jsonl}"
    sid="$(head -1 "$f" | jq -r '.source_id // ""')"
    turns="$(tail -n +2 "$f" | jq -c 'select(.role=="user")' | wc -l)"

    if [[ "$JSON_OUT" == "true" ]]; then
      [[ "$first" == "true" ]] && first=false || echo ","
      jq -n --arg date "$fdate" --arg id "$short_id" --arg source_id "$sid" --argjson turns "$turns" \
        '{"date":$date,"id":$id,"source_id":$source_id,"turns":$turns}'
    else
      printf "%-12s %-10s %6d  %s\n" "$fdate" "$short_id" "$turns" "$sid"
    fi
  done

  if [[ "$JSON_OUT" == "true" ]]; then
    echo "]"
  fi
}

do_session() {
  local target="$1"
  local found=""

  for f in "$ST_DIR"/*.jsonl; do
    [[ ! -f "$f" ]] && continue
    local base="${f##*/}"
    if [[ "$base" == *"$target"* ]]; then
      found="$f"
      break
    fi
  done

  if [[ -z "$found" ]]; then
    echo "No session matching '$target'" >&2
    exit 1
  fi

  local base fdate short_id turns
  base="$(basename "$found")"
  fdate="${base:0:10}"
  short_id="${base:11}"
  short_id="${short_id%.jsonl}"
  turns="$(tail -n +2 "$found" | jq -c 'select(.role=="user")' | wc -l)"

  if [[ "$JSON_OUT" == "true" ]]; then
    tail -n +2 "$found"
  else
    echo "=== $fdate $short_id ($turns turns) ==="
    tail -n +2 "$found" | while IFS= read -r line; do
      local role turn content
      role="$(echo "$line" | jq -r '.role')"
      turn="$(echo "$line" | jq -r '.turn')"
      content="$(echo "$line" | jq -r '.content')"
      # Truncate long content for display
      if [[ "${#content}" -gt 200 ]]; then
        content="${content:0:200}..."
      fi
      echo "[turn $turn, $role] $content"
    done
  fi
}

do_query() {
  local pattern="$1"
  local count=0 max_results=20

  # Tokenize query: extract words >3 chars and build OR pattern
  local search_pat=""
  local grep_flags="-i"
  for word in $pattern; do
    if [[ "${#word}" -gt 3 ]]; then
      if [[ -z "$search_pat" ]]; then
        search_pat="$word"
      else
        search_pat="$search_pat|$word"
      fi
    fi
  done

  if [[ -n "$search_pat" ]]; then
    grep_flags="-iE"
  else
    search_pat="$pattern"
  fi

  while IFS= read -r file; do
    [[ ! -f "$file" ]] && continue
    local base fdate short_id
    base="$(basename "$file")"
    fdate="${base:0:10}"
    short_id="${base:11}"
    short_id="${short_id%.jsonl}"

    local header_shown=false
    while IFS= read -r line; do
      [[ "$count" -ge "$max_results" ]] && break
      local role turn content
      role="$(echo "$line" | jq -r '.role')"
      turn="$(echo "$line" | jq -r '.turn')"
      content="$(echo "$line" | jq -r '.content')"

      if [[ "$JSON_OUT" == "true" ]]; then
        jq -n --arg date "$fdate" --arg id "$short_id" \
              --arg role "$role" --argjson turn "$turn" --arg content "$content" \
          '{"date":$date,"session":$id,"role":$role,"turn":$turn,"content":$content}'
      else
        if [[ "$header_shown" == "false" ]]; then
          echo "=== $fdate $short_id ==="
          header_shown=true
        fi
        local display="$content"
        if [[ "${#display}" -gt 200 ]]; then
          display="${display:0:200}..."
        fi
        echo "[turn $turn, $role] $display"
      fi
      count=$((count + 1))
    done < <(tail -n +2 "$file" | grep $grep_flags "$search_pat" || true)

    [[ "$count" -ge "$max_results" ]] && break
  done < <(get_files_in_range)

  if [[ "$count" -eq 0 ]]; then
    echo "No results for '$pattern'"
  elif [[ "$JSON_OUT" != "true" ]]; then
    echo "--- $count results ---"
  fi
}

if [[ "$LIST" == "true" ]]; then
  do_list
elif [[ -n "$SESSION" ]]; then
  do_session "$SESSION"
elif [[ -n "$QUERY" ]]; then
  do_query "$QUERY"
fi
