#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AP_DIR="$SCRIPT_DIR/.."
CONFIG="$AP_DIR/config.json"
BACKLOG="$AP_DIR/data/backlog.json"

TZ="$(jq -r '.timezone // "UTC"' "$CONFIG")"
export TZ

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Manage the agent-persona backlog and reminders.

Commands:
  add       Add a new item (task, reminder, or idea)
  list      List items (filtered/sorted)
  done      Mark an item as done (auto-recurs if recurring)
  update    Update fields on an item
  remove    Remove an item entirely
  show      Show full details of an item
  alarms    Show items whose alarm is firing now

Run '$(basename "$0") <command> --help' for command-specific options.
EOF
  exit 0
}

ensure_backlog() {
  if [[ ! -f "$BACKLOG" ]]; then
    echo '{"items":[]}' > "$BACKLOG"
  fi
}

next_id() {
  local max
  max=$(jq -r '[ .items[].id | ltrimstr("bl_") | tonumber ] | if length == 0 then 0 else max end' "$BACKLOG")
  printf "bl_%03d" $((max + 1))
}

write_backlog() {
  local tmp="$BACKLOG.tmp"
  jq '.' > "$tmp" < /dev/stdin
  mv "$tmp" "$BACKLOG"
}

find_item() {
  local id="$1"
  jq -e --arg id "$id" '.items[] | select(.id == $id)' "$BACKLOG" > /dev/null 2>&1
}

today() {
  date +%Y-%m-%d
}

now_time() {
  date +%H:%M
}

validate_time() {
  local t="$1"
  if [[ ! "$t" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
    echo "ERROR: --due-time must be HH:MM format (got '$t')" >&2
    exit 1
  fi
  local hh="${t%%:*}"
  if (( 10#$hh > 23 )); then
    echo "ERROR: --due-time hour must be 00-23 (got '$t')" >&2
    exit 1
  fi
}

validate_recurrence() {
  local r="$1"
  case "$r" in
    daily|weekly|monthly|yearly) ;;
    *) echo "ERROR: --recurrence must be daily|weekly|monthly|yearly (got '$r')" >&2; exit 1 ;;
  esac
}

validate_type() {
  local t="$1"
  case "$t" in
    task|reminder|idea) ;;
    *) echo "ERROR: --type must be task|reminder|idea (got '$t')" >&2; exit 1 ;;
  esac
}

validate_status() {
  local s="$1"
  case "$s" in
    open|in_progress|done|blocked|cancelled) ;;
    *) echo "ERROR: --status must be open|in_progress|done|blocked|cancelled (got '$s')" >&2; exit 1 ;;
  esac
}

date_add_days() {
  date -d "$1 + $2 days" +%Y-%m-%d
}

date_add_months() {
  date -d "$1 + $2 months" +%Y-%m-%d
}

date_add_years() {
  date -d "$1 + $2 years" +%Y-%m-%d
}

next_due_date() {
  local current_due="$1" recurrence="$2"
  case "$recurrence" in
    daily)   date_add_days "$current_due" 1 ;;
    weekly)  date_add_days "$current_due" 7 ;;
    monthly) date_add_months "$current_due" 1 ;;
    yearly)  date_add_years "$current_due" 1 ;;
  esac
}

json_str_or_null() {
  local val="$1"
  if [[ "$val" == "null" ]]; then
    echo "null"
  else
    jq -n --arg v "$val" '$v'
  fi
}

json_int_or_null() {
  local val="$1"
  if [[ "$val" == "null" ]]; then
    echo "null"
  else
    echo "$val"
  fi
}

# --- add ---
cmd_add() {
  local title="" category="project" priority="medium" due="null" context="null" source="user"
  local type="task" due_time="null" recurrence="null" advance_notice="null"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)          title="$2"; shift 2 ;;
      --category)       category="$2"; shift 2 ;;
      --priority)       priority="$2"; shift 2 ;;
      --due)            due="$2"; shift 2 ;;
      --context)        context="$2"; shift 2 ;;
      --source)         source="$2"; shift 2 ;;
      --type)           type="$2"; shift 2 ;;
      --due-time)       due_time="$2"; shift 2 ;;
      --recurrence)     recurrence="$2"; shift 2 ;;
      --advance-notice) advance_notice="$2"; shift 2 ;;
      -h|--help)
        cat <<EOF
Usage: $(basename "$0") add --title "..." [options]

Options:
  --title <text>            (required) Short description
  --category <cat>          project|personal|reminder (default: project)
  --priority <pri>          high|medium|low (default: medium)
  --due <YYYY-MM-DD>        Due date (default: none)
  --context <text>          Additional notes
  --source <text>           Where captured from (default: user)
  --type <type>             task|reminder|idea (default: task)
  --due-time <HH:MM>        Time of day for alarm-type reminders
  --recurrence <freq>       daily|weekly|monthly|yearly
  --advance-notice <min>    Minutes before due_time to fire (default: 5 for reminders)
EOF
        exit 0 ;;
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$title" ]]; then
    echo "ERROR: --title is required" >&2
    exit 1
  fi

  validate_type "$type"
  [[ "$due_time" != "null" ]] && validate_time "$due_time"
  [[ "$recurrence" != "null" ]] && validate_recurrence "$recurrence"

  # Default advance_notice for reminders with a due_time
  if [[ "$type" == "reminder" && "$due_time" != "null" && "$advance_notice" == "null" ]]; then
    advance_notice="5"
  fi

  local id
  id="$(next_id)"
  local created
  created="$(today)"

  jq --arg id "$id" \
     --arg title "$title" \
     --arg category "$category" \
     --arg priority "$priority" \
     --arg created "$created" \
     --argjson due "$(json_str_or_null "$due")" \
     --argjson context "$(json_str_or_null "$context")" \
     --arg source "$source" \
     --arg type "$type" \
     --argjson due_time "$(json_str_or_null "$due_time")" \
     --argjson recurrence "$(json_str_or_null "$recurrence")" \
     --argjson advance_notice "$(json_int_or_null "$advance_notice")" \
     '.items += [{
       id: $id,
       title: $title,
       category: $category,
       priority: $priority,
       status: "open",
       created: $created,
       due: $due,
       context: $context,
       source: $source,
       type: $type,
       due_time: $due_time,
       recurrence: $recurrence,
       advance_notice: $advance_notice
     }]' "$BACKLOG" | write_backlog

  echo "added: $id \"$title\""
}

# --- list ---
cmd_list() {
  local cat_filter="" status_filter="open_ip" pri_filter="" json_out=false
  local type_filter="" due_today=false due_soon=false due_soon_days=7

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --category) cat_filter="$2"; shift 2 ;;
      --status)   status_filter="$2"; shift 2 ;;
      --priority) pri_filter="$2"; shift 2 ;;
      --type)     type_filter="$2"; shift 2 ;;
      --due-today) due_today=true; shift ;;
      --due-soon)
        due_soon=true
        if [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]]; then
          due_soon_days="$2"; shift 2
        else
          shift
        fi
        ;;
      --json)     json_out=true; shift ;;
      -h|--help)
        cat <<EOF
Usage: $(basename "$0") list [options]

Options:
  --category <cat>     Filter by category
  --status <status>    open|in_progress|done|blocked|cancelled|all (default: open+in_progress)
  --priority <pri>     Filter by priority
  --type <type>        Filter by type (task|reminder|idea)
  --due-today          Show only items due today
  --due-soon [N]       Show items due within N days (default: 7)
  --json               Machine-readable JSON output
EOF
        exit 0 ;;
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done

  local today_date
  today_date="$(today)"

  local jq_filter='.items'

  if [[ "$status_filter" == "all" ]]; then
    : # no status filter
  elif [[ "$status_filter" == "open_ip" ]]; then
    jq_filter="$jq_filter | map(select(.status == \"open\" or .status == \"in_progress\"))"
  else
    jq_filter="$jq_filter | map(select(.status == \"$status_filter\"))"
  fi

  if [[ -n "$cat_filter" ]]; then
    jq_filter="$jq_filter | map(select(.category == \"$cat_filter\"))"
  fi

  if [[ -n "$pri_filter" ]]; then
    jq_filter="$jq_filter | map(select(.priority == \"$pri_filter\"))"
  fi

  if [[ -n "$type_filter" ]]; then
    jq_filter="$jq_filter | map(select((.type // \"task\") == \"$type_filter\"))"
  fi

  if [[ "$due_today" == "true" ]]; then
    jq_filter="$jq_filter | map(select(.due == \"$today_date\"))"
  fi

  if [[ "$due_soon" == "true" ]]; then
    local cutoff
    cutoff="$(date_add_days "$today_date" "$due_soon_days")"
    jq_filter="$jq_filter | map(select(.due != null and .due <= \"$cutoff\"))"
  fi

  # Sort: items with due_time soonest first, then by due date proximity, then priority
  local pri_sort='{"high":1,"medium":2,"low":3}'
  jq_filter="$jq_filter | sort_by(
    (if .due == null then \"9999-99-99\" else .due end),
    (if (.due_time // null) == null then \"99:99\" else .due_time end),
    ($pri_sort)[.priority],
    .created
  )"

  if [[ "$json_out" == "true" ]]; then
    jq "$jq_filter" "$BACKLOG"
    return
  fi

  local items
  items="$(jq -r "$jq_filter | .[] | [.id, .priority, (.type // \"task\"), .category, (.due // \"—\"), (.due_time // \"—\"), .title] | @tsv" "$BACKLOG")"

  if [[ -z "$items" ]]; then
    echo "(no items)"
    return
  fi

  printf "%-8s %-6s %-9s %-10s %-12s %-6s %s\n" "ID" "PRI" "TYPE" "CAT" "DUE" "TIME" "TITLE"
  while IFS=$'\t' read -r id pri type cat due due_time title; do
    local pri_short="$pri"
    [[ "$pri" == "medium" ]] && pri_short="med"
    printf "%-8s %-6s %-9s %-10s %-12s %-6s %s\n" "$id" "$pri_short" "$type" "$cat" "$due" "$due_time" "$title"
  done <<< "$items"
}

# --- done ---
cmd_done() {
  if [[ $# -lt 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $(basename "$0") done <id>"
    exit 0
  fi

  local id="$1"
  if ! find_item "$id"; then
    echo "ERROR: item '$id' not found" >&2
    exit 1
  fi

  local item_json
  item_json="$(jq -r --arg id "$id" '.items[] | select(.id == $id)' "$BACKLOG")"

  local title recurrence due due_time type category priority advance_notice context source
  title="$(echo "$item_json" | jq -r '.title')"
  recurrence="$(echo "$item_json" | jq -r '.recurrence // empty')"
  due="$(echo "$item_json" | jq -r '.due // empty')"
  due_time="$(echo "$item_json" | jq -r '.due_time // empty')"
  type="$(echo "$item_json" | jq -r '.type // "task"')"
  category="$(echo "$item_json" | jq -r '.category')"
  priority="$(echo "$item_json" | jq -r '.priority')"
  advance_notice="$(echo "$item_json" | jq -r '.advance_notice // empty')"
  context="$(echo "$item_json" | jq -r '.context // empty')"
  source="$(echo "$item_json" | jq -r '.source // "user"')"

  jq --arg id "$id" '(.items[] | select(.id == $id)).status = "done"' "$BACKLOG" | write_backlog

  if [[ -n "$recurrence" && -n "$due" ]]; then
    local new_due
    new_due="$(next_due_date "$due" "$recurrence")"

    local new_id
    new_id="$(next_id)"
    local created
    created="$(today)"

    jq --arg id "$new_id" \
       --arg title "$title" \
       --arg category "$category" \
       --arg priority "$priority" \
       --arg created "$created" \
       --argjson due "$(json_str_or_null "$new_due")" \
       --argjson context "$(json_str_or_null "${context:-null}")" \
       --arg source "$source" \
       --arg type "$type" \
       --argjson due_time "$(json_str_or_null "${due_time:-null}")" \
       --argjson recurrence "$(json_str_or_null "$recurrence")" \
       --argjson advance_notice "$(json_int_or_null "${advance_notice:-null}")" \
       '.items += [{
         id: $id,
         title: $title,
         category: $category,
         priority: $priority,
         status: "open",
         created: $created,
         due: $due,
         context: $context,
         source: $source,
         type: $type,
         due_time: $due_time,
         recurrence: $recurrence,
         advance_notice: $advance_notice
       }]' "$BACKLOG" | write_backlog

    echo "done: $id \"$title\" (next: $new_id due $new_due)"
  else
    echo "done: $id \"$title\""
  fi
}

# --- update ---
cmd_update() {
  if [[ $# -lt 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<EOF
Usage: $(basename "$0") update <id> [options]

Options:
  --title <text>            Update title
  --category <cat>          Update category
  --priority <pri>          Update priority
  --status <status>         Update status (open|in_progress|done|blocked|cancelled)
  --due <YYYY-MM-DD>        Update due date (use "null" to clear)
  --context <text>          Update context (use "null" to clear)
  --type <type>             Update type (task|reminder|idea)
  --due-time <HH:MM>        Update due time (use "null" to clear)
  --recurrence <freq>       Update recurrence (daily|weekly|monthly|yearly, "null" to clear)
  --advance-notice <min>    Update advance notice minutes (use "null" to clear)
EOF
    exit 0
  fi

  local id="$1"; shift
  if ! find_item "$id"; then
    echo "ERROR: item '$id' not found" >&2
    exit 1
  fi

  local updates=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)    updates="$updates | (.items[] | select(.id == \$id)).title = $(jq -n --arg v "$2" '$v')"; shift 2 ;;
      --category) updates="$updates | (.items[] | select(.id == \$id)).category = $(jq -n --arg v "$2" '$v')"; shift 2 ;;
      --priority) updates="$updates | (.items[] | select(.id == \$id)).priority = $(jq -n --arg v "$2" '$v')"; shift 2 ;;
      --status)
        validate_status "$2"
        updates="$updates | (.items[] | select(.id == \$id)).status = $(jq -n --arg v "$2" '$v')"
        shift 2 ;;
      --type)
        validate_type "$2"
        updates="$updates | (.items[] | select(.id == \$id)).type = $(jq -n --arg v "$2" '$v')"
        shift 2 ;;
      --due)
        if [[ "$2" == "null" ]]; then
          updates="$updates | (.items[] | select(.id == \$id)).due = null"
        else
          updates="$updates | (.items[] | select(.id == \$id)).due = $(jq -n --arg v "$2" '$v')"
        fi
        shift 2 ;;
      --context)
        if [[ "$2" == "null" ]]; then
          updates="$updates | (.items[] | select(.id == \$id)).context = null"
        else
          updates="$updates | (.items[] | select(.id == \$id)).context = $(jq -n --arg v "$2" '$v')"
        fi
        shift 2 ;;
      --due-time)
        if [[ "$2" == "null" ]]; then
          updates="$updates | (.items[] | select(.id == \$id)).due_time = null"
        else
          validate_time "$2"
          updates="$updates | (.items[] | select(.id == \$id)).due_time = $(jq -n --arg v "$2" '$v')"
        fi
        shift 2 ;;
      --recurrence)
        if [[ "$2" == "null" ]]; then
          updates="$updates | (.items[] | select(.id == \$id)).recurrence = null"
        else
          validate_recurrence "$2"
          updates="$updates | (.items[] | select(.id == \$id)).recurrence = $(jq -n --arg v "$2" '$v')"
        fi
        shift 2 ;;
      --advance-notice)
        if [[ "$2" == "null" ]]; then
          updates="$updates | (.items[] | select(.id == \$id)).advance_notice = null"
        else
          updates="$updates | (.items[] | select(.id == \$id)).advance_notice = $2"
        fi
        shift 2 ;;
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$updates" ]]; then
    echo "ERROR: no fields to update" >&2
    exit 1
  fi

  updates="${updates# | }"
  jq --arg id "$id" "$updates" "$BACKLOG" | write_backlog

  echo "updated: $id"
}

# --- remove ---
cmd_remove() {
  if [[ $# -lt 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $(basename "$0") remove <id>"
    exit 0
  fi

  local id="$1"
  if ! find_item "$id"; then
    echo "ERROR: item '$id' not found" >&2
    exit 1
  fi

  local title
  title="$(jq -r --arg id "$id" '.items[] | select(.id == $id) | .title' "$BACKLOG")"

  jq --arg id "$id" '.items |= map(select(.id != $id))' "$BACKLOG" | write_backlog

  echo "removed: $id \"$title\""
}

# --- show ---
cmd_show() {
  if [[ $# -lt 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $(basename "$0") show <id>"
    exit 0
  fi

  local id="$1"
  if ! find_item "$id"; then
    echo "ERROR: item '$id' not found" >&2
    exit 1
  fi

  jq -r --arg id "$id" '
    .items[] | select(.id == $id) |
    "ID:             \(.id)
Title:          \(.title)
Type:           \(.type // "task")
Category:       \(.category)
Priority:       \(.priority)
Status:         \(.status)
Created:        \(.created)
Due:            \(.due // "—")
Due time:       \(.due_time // "—")
Recurrence:     \(.recurrence // "—")
Advance notice: \(if .advance_notice != null then "\(.advance_notice) min" else "—" end)
Context:        \(.context // "—")
Source:         \(.source)"
  ' "$BACKLOG"
}

# --- alarms ---
cmd_alarms() {
  local today_date now_hhmm
  today_date="$(today)"
  now_hhmm="$(now_time)"

  # Convert HH:MM to minutes since midnight
  local now_min
  now_min=$(( 10#${now_hhmm%%:*} * 60 + 10#${now_hhmm##*:} ))

  jq -r --arg today "$today_date" --argjson now_min "$now_min" '
    .items[]
    | select(.status == "open" or .status == "in_progress")
    | select(.due == $today)
    | select(.due_time != null and .due_time != "")
    | (.advance_notice // 5) as $adv
    | ((.due_time | split(":") | (.[0] | tonumber) * 60 + (.[1] | tonumber))) as $fire_min
    | select($now_min >= ($fire_min - $adv) and $now_min <= $fire_min)
    | "\(.id) \(.due_time) \(.title)"
  ' "$BACKLOG"
}

# --- main ---
ensure_backlog

if [[ $# -lt 1 ]]; then
  usage
fi

CMD="$1"; shift
case "$CMD" in
  add)    cmd_add "$@" ;;
  list)   cmd_list "$@" ;;
  done)   cmd_done "$@" ;;
  update) cmd_update "$@" ;;
  remove) cmd_remove "$@" ;;
  show)   cmd_show "$@" ;;
  alarms) cmd_alarms "$@" ;;
  -h|--help) usage ;;
  *) echo "Unknown command: $CMD" >&2; usage ;;
esac
