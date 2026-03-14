#!/usr/bin/env bash
# write_knowledge.sh — sanctioned writer for knowledge.json
# One of only 3 authorized writers: infer-knowledge (pipeline),
# write_knowledge.sh (seeding/manual), forgetting.sh (management).
# Agents must NEVER write to knowledge.json directly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR/.."
KNOWLEDGE="$BASE/data/knowledge/knowledge.json"

VALID_TYPES="preference convention fact rule trait"
VALID_SCOPES="user project global"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Sanctioned writer for knowledge.json — add, seed, or validate knowledge items.

Commands:
  add        Add a single knowledge item
  seed       Bulk-add from a JSON array file
  validate   Dry-run validation of a seed file

Run '$(basename "$0") <command> --help' for command-specific options.
EOF
  exit 0
}

ensure_file() {
  local file="$1" default="$2"
  if [[ ! -f "$file" ]]; then
    mkdir -p "$(dirname "$file")"
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

contains() {
  local item="$1" list="$2"
  [[ " $list " == *" $item "* ]]
}

# Build a knowledge item JSON object from validated parameters
build_item() {
  local type="$1" content="$2" scope="$3" source="$4" source_type="$5" polarity="$6" pinned="$7" emotional_value="$8"
  local created
  created=$(today)

  jq -n \
    --arg type "$type" \
    --arg content "$content" \
    --arg scope "$scope" \
    --arg source "$source" \
    --arg source_type "$source_type" \
    --arg polarity "$polarity" \
    --argjson pinned "$pinned" \
    --arg emotional_value "$emotional_value" \
    --arg created "$created" \
    '{
      type: $type,
      content: $content,
      scope: $scope,
      source: $source,
      source_type: $source_type,
      created: $created,
      strength: 1,
      last_accessed: null,
      access_count: 0,
      pinned: $pinned,
      emotional_value: (if $emotional_value == "" then null else ($emotional_value | tonumber) end),
      retention_score: 1.0
    }
    + (if $polarity != "" then {polarity: $polarity} else {} end)'
}

# Validate a single item's fields. Returns 0 if valid, 1 if not.
# On failure, prints the error to stderr.
validate_item() {
  local type="$1" content="$2" scope="$3" polarity="$4"

  if [[ -z "$type" ]]; then
    echo "missing --type" >&2; return 1
  fi
  if ! contains "$type" "$VALID_TYPES"; then
    echo "invalid type '$type' (must be: $VALID_TYPES)" >&2; return 1
  fi
  if [[ -z "$content" ]]; then
    echo "missing or empty --content" >&2; return 1
  fi
  if ! contains "$scope" "$VALID_SCOPES"; then
    echo "invalid scope '$scope' (must be: $VALID_SCOPES)" >&2; return 1
  fi
  if [[ -n "$polarity" ]]; then
    if [[ "$type" != "preference" ]]; then
      echo "polarity only applies to type 'preference', got '$type'" >&2; return 1
    fi
    if [[ "$polarity" != "like" && "$polarity" != "dislike" ]]; then
      echo "invalid polarity '$polarity' (must be: like, dislike)" >&2; return 1
    fi
  fi
  return 0
}

# --- add ---
cmd_add() {
  local type="" content="" scope="project" source="" source_type="self_reported"
  local polarity="" pinned="false" emotional_value=""

  if [[ $# -eq 0 ]]; then
    cat <<EOF
Usage: $(basename "$0") add --type TYPE --content "CONTENT" [options]

Required:
  --type TYPE           One of: preference, convention, fact, rule, trait
  --content "CONTENT"   The knowledge content (non-empty)

Optional:
  --scope SCOPE         One of: user, project, global (default: project)
  --source SOURCE       Source label (default: manual-YYYY-MM-DD)
  --source-type TYPE    Source type (default: self_reported)
  --polarity POLARITY   like or dislike (preference type only)
  --pinned              Mark as pinned (immune to decay)
  --emotional-value N   Numeric emotional value
EOF
    exit 0
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) type="$2"; shift 2 ;;
      --content) content="$2"; shift 2 ;;
      --scope) scope="$2"; shift 2 ;;
      --source) source="$2"; shift 2 ;;
      --source-type) source_type="$2"; shift 2 ;;
      --polarity) polarity="$2"; shift 2 ;;
      --pinned) pinned="true"; shift ;;
      --emotional-value) emotional_value="$2"; shift 2 ;;
      -h|--help)
        cmd_add
        ;;
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done

  [[ -z "$source" ]] && source="manual-$(today)"
  [[ "$type" == "trait" ]] && scope="user"

  if ! validate_item "$type" "$content" "$scope" "$polarity"; then
    exit 1
  fi

  local item
  item=$(build_item "$type" "$content" "$scope" "$source" "$source_type" "$polarity" "$pinned" "$emotional_value")

  jq --argjson new_item "$item" '.items += [$new_item]' "$KNOWLEDGE" | write_json "$KNOWLEDGE"

  echo "added: \"$(preview "$content")\""
}

# --- seed ---
cmd_seed() {
  local file="" dry_run="false"

  if [[ $# -eq 0 ]]; then
    cat <<EOF
Usage: $(basename "$0") seed --file PATH

Bulk-add knowledge items from a JSON array file.
Each object must have at least "type" and "content".
Optional fields: scope, source, source_type, polarity, pinned, emotional_value.
Items that fail validation are skipped with a warning.
EOF
    exit 0
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) file="$2"; shift 2 ;;
      --dry-run) dry_run="true"; shift ;;
      -h|--help) cmd_seed; ;;
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$file" ]]; then
    echo "ERROR: --file is required" >&2; exit 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "ERROR: file not found: $file" >&2; exit 1
  fi

  local count valid=0 invalid=0
  count=$(jq 'length' "$file")

  if [[ "$count" -eq 0 ]]; then
    echo "seeded 0 items from $file"
    return
  fi

  local current_knowledge
  current_knowledge=$(cat "$KNOWLEDGE")

  for (( i=0; i<count; i++ )); do
    local raw
    raw=$(jq --argjson i "$i" '.[$i]' "$file")

    local type content scope source source_type polarity pinned emotional_value
    type=$(echo "$raw" | jq -r '.type // ""')
    content=$(echo "$raw" | jq -r '.content // ""')
    scope=$(echo "$raw" | jq -r '.scope // "project"')
    source=$(echo "$raw" | jq -r '.source // ""')
    source_type=$(echo "$raw" | jq -r '.source_type // "self_reported"')
    polarity=$(echo "$raw" | jq -r '.polarity // ""')
    pinned=$(echo "$raw" | jq -r 'if .pinned == true then "true" else "false" end')
    emotional_value=$(echo "$raw" | jq -r '.emotional_value // ""')

    [[ -z "$source" ]] && source="manual-$(today)"
    [[ "$type" == "trait" ]] && scope="user"

    if ! validate_item "$type" "$content" "$scope" "$polarity" 2>/tmp/wk_err; then
      local err
      err=$(cat /tmp/wk_err)
      echo "WARN: skipping item $i: $err" >&2
      ((invalid++)) || true
      continue
    fi

    if [[ "$dry_run" == "false" ]]; then
      local item
      item=$(build_item "$type" "$content" "$scope" "$source" "$source_type" "$polarity" "$pinned" "$emotional_value")
      current_knowledge=$(echo "$current_knowledge" | jq --argjson new_item "$item" '.items += [$new_item]')
    fi

    ((valid++)) || true
  done

  if [[ "$dry_run" == "false" ]]; then
    echo "$current_knowledge" | write_json "$KNOWLEDGE"
    echo "seeded $valid items from $file"
  else
    echo "$valid valid, $invalid invalid"
  fi
  [[ "$invalid" -gt 0 ]] && echo "($invalid items skipped due to validation errors)" >&2
  return 0
}

# --- validate ---
cmd_validate() {
  local file=""

  if [[ $# -eq 0 ]]; then
    cat <<EOF
Usage: $(basename "$0") validate --file PATH

Dry-run validation of a seed file. Reports valid/invalid counts and errors.
EOF
    exit 0
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) file="$2"; shift 2 ;;
      -h|--help) cmd_validate; ;;
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$file" ]]; then
    echo "ERROR: --file is required" >&2; exit 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "ERROR: file not found: $file" >&2; exit 1
  fi

  cmd_seed --file "$file" --dry-run
}

# --- main ---
ensure_file "$KNOWLEDGE" '{"items":[]}'

if [[ $# -lt 1 ]]; then
  usage
fi

CMD="$1"; shift
case "$CMD" in
  add)      cmd_add "$@" ;;
  seed)     cmd_seed "$@" ;;
  validate) cmd_validate "$@" ;;
  -h|--help) usage ;;
  *) echo "Unknown command: $CMD" >&2; usage ;;
esac
