#!/usr/bin/env bash
set -euo pipefail

INPUT="$(cat)"

extract_section() {
  local name="$1"
  printf '%s\n' "$INPUT" | awk -v m="=== ${name} ===" '
    $0 == m { found=1; next }
    found && /^=== .+ ===$/ { exit }
    found { print }
  '
}

# ── PERSONA ──────────────────────────────────────────────
printf '=== PERSONA ===\n'
extract_section "PERSONALITY_DIRECTIVE"

# ── CONTEXT ──────────────────────────────────────────────
printf '=== CONTEXT ===\n'
handoff="$(extract_section "HANDOFF")"
if echo "$handoff" | grep -q '^exists: true'; then
  echo "$handoff" | tail -n +2
else
  echo "No prior session."
fi

# ── KNOWLEDGE PRIMING (omit section if NONE / empty) ─────
priming="$(extract_section "KNOWLEDGE_PRIMING")"
if [[ -n "$priming" ]] && [[ "$priming" != "NONE" ]]; then
  printf '\n=== Relevant knowledge ===\n'
  echo "$priming"
fi

# ── NOTES (omit section if nothing active or pending) ────
proc="$(extract_section "PROCEDURAL_NOTES")"
active_json="$(echo "$proc" | sed -n 's/^active: //p')"
pending_json="$(echo "$proc" | sed -n 's/^pending_approval: //p')"
: "${active_json:=[]}"
: "${pending_json:=[]}"

active_n="$(echo "$active_json" | jq 'length' 2>/dev/null || echo 0)"
pending_n="$(echo "$pending_json" | jq 'length' 2>/dev/null || echo 0)"

if (( active_n + pending_n > 0 )); then
  printf '\n=== NOTES ===\n'
  if (( active_n > 0 )); then
    echo "$active_json" | jq -r '.[] | "- \(.content)"'
  fi
  if (( pending_n > 0 )); then
    echo "$pending_json" | jq -r '.[] | "- [pending] \(.content)"'
  fi
fi

# ── STATUS ───────────────────────────────────────────────
mode_sec="$(extract_section "MODE")"
mode="$(echo "$mode_sec" | sed -n 's/^mode: //p')"
debug="$(echo "$mode_sec" | sed -n 's/^debug: //p')"

consol_sec="$(extract_section "CONSOLIDATION")"
consol="$(echo "$consol_sec" | sed -n 's/^status: //p')"

save_sec="$(extract_section "SAVE_BOUNDARY")"
next_save="$(echo "$save_sec" | sed -n 's/^next: //p')"

printf '\n=== STATUS ===\n'
printf 'mode: %s\n' "${mode:-normal}"
printf 'debug: %s\n' "${debug:-false}"
printf 'consolidation: %s\n' "${consol:-current}"
printf 'next_save: %s\n' "${next_save:---:--}"

# ── BACKLOG ──────────────────────────────────────────────
backlog_raw="$(extract_section "BACKLOG")"
printf '\n=== BACKLOG ===\n'

if echo "$backlog_raw" | grep -q '^\['; then
  TODAY="${TODAY:-$(date +%Y-%m-%d)}"
  backlog_out="$(echo "$backlog_raw" | jq -r --arg today "$TODAY" '
    def pri_ge_medium: (.priority | ascii_upcase) as $p | ($p == "HIGH" or $p == "MEDIUM" or $p == "MED");
    def days_remaining:
      if .due == null or .due == "" then null
      else (($today | strptime("%Y-%m-%d") | mktime) as $t |
            ((.due | tostring) | strptime("%Y-%m-%d")? | mktime) as $d |
            if $d then (($d - $t) / 86400 | floor) else null end)
      end;
    def has_due_time: ((.due_time // "") | type == "string") and ((.due_time // "") | length > 0);

    [.[] | select(.status == "open" or .status == "in_progress")]
    | map(. + {
        days: days_remaining,
        pri_up: (.priority | ascii_upcase),
        is_med_or_higher: pri_ge_medium
      })
    | . as $all
    | ($all | map(select(.days != null)) | sort_by(.days)) as $with_due
    | [
        ($with_due[] | select(.days < 0)  | {sort: 0, line: "- [OVERDUE] \(.title) (was due \(.due))"}),
        ($with_due[] | select(.days == 0) | if has_due_time then {sort: 1, line: "- [REMINDER] \(.title) at \(.due_time)"} else {sort: 2, line: "- [DUE TODAY] \(.title)"} end),
        ($with_due[] | select(.days > 0 and .days <= 7)  | {sort: 3, line: "- [DUE in \(.days) days] \(.title) (\(.due))"}),
        ($with_due[] | select(.days > 7 and .days <= 30) | if .is_med_or_higher then {sort: 4, line: "- [DUE in \(.days) days] \(.title) (\(.due))"} else empty end),
        ($all[] | select(.days == null and .pri_up == "HIGH") | {sort: 5, line: "- [HIGH] \(.title)"})
      ]
    | sort_by(.sort) | .[].line
  ' 2>/dev/null || true)"

  med_count="$(echo "$backlog_raw" | jq -r --arg today "$TODAY" '
    [.[] | select((.status == "open" or .status == "in_progress") and
      ((.priority | ascii_upcase) == "MEDIUM" or (.priority | ascii_upcase) == "MED") and
      (.due == null or .due == "" or (
        (($today | strptime("%Y-%m-%d") | mktime) as $t |
         ((.due | tostring) | strptime("%Y-%m-%d")? | mktime) as $d |
         if $d then (($d - $t) / 86400 | floor) > 30 else true end)
      ))
    )] | length
  ' 2>/dev/null || echo 0)"

  low_count="$(echo "$backlog_raw" | jq -r --arg today "$TODAY" '
    [.[] | select((.status == "open" or .status == "in_progress") and
      ((.priority | ascii_upcase) == "LOW") and
      (.due == null or .due == "" or (
        (($today | strptime("%Y-%m-%d") | mktime) as $t |
         ((.due | tostring) | strptime("%Y-%m-%d")? | mktime) as $d |
         if $d then (($d - $t) / 86400 | floor) > 30 else true end)
      ))
    )] | length
  ' 2>/dev/null || echo 0)"

  printed=false
  if [[ -n "$backlog_out" ]]; then
    echo "$backlog_out"; printed=true
  fi
  if (( med_count > 0 )); then
    echo "${med_count} medium-priority items"; printed=true
  fi
  if (( low_count > 0 )); then
    echo "${low_count} low-priority items"; printed=true
  fi
  if [[ "$printed" == false ]]; then
    echo "Empty."
  fi
else
  echo "Empty."
fi

# ── SURFACING (omit section if no candidates) ───────────
BASE="$(cd "$(dirname "$0")/../.." && pwd)"
SURFACE_QUEUE="$BASE/data/knowledge/surface_queue.json"
if [[ -f "$SURFACE_QUEUE" ]]; then
  surf_count="$(jq '.candidates | length' "$SURFACE_QUEUE" 2>/dev/null || echo 0)"
  if (( surf_count > 0 )); then
    printf '\n=== SURFACING ===\n'
    echo "Items fading from memory (review with 'surface fading'):"
    jq -r '.candidates[:2][] | "- [\(.index)] (\(.retention_score)) \(.type): \(.content_preview)"' "$SURFACE_QUEUE" 2>/dev/null || true
  fi
fi

# ── SIBLING_THREADS (omit section entirely if NONE) ─────
sibling_raw="$(extract_section "SIBLING_MAIN_THREADS")"
if [[ -n "$sibling_raw" ]] && ! echo "$sibling_raw" | grep -qx 'NONE'; then
  sibling_out="$(echo "$sibling_raw" | awk '
    function flush() {
      if (name == "") return
      sub(/\n+$/, "", topic)
      sub(/\n+$/, "", intents)
      fresh_topic  = (topic == "" || index(topic, "(none") == 1)
      fresh_intent = (intents == "" || index(intents, "(none") == 1)
      if (fresh_topic && fresh_intent) {
        printf "[%s] (fresh — no recent work)\n", name
      } else {
        printf "[%s]\n", name
        if (!fresh_topic) printf "Goal: %s\n", topic
        if (!fresh_intent) printf "Recent intents:\n%s\n", intents
      }
      name = ""; topic = ""; intents = ""
    }
    /^file: / {
      if (name != "") flush()
      name = $0; sub(/^file: /, "", name); sub(/\.md$/, "", name)
      in_topic = 0; in_intents = 0
      topic = ""; intents = ""
      next
    }
    /^---$/ { flush(); next }
    /^### Current topic \/ goal/ { in_topic = 1; in_intents = 0; next }
    /^### Last 3 user intents/  { in_intents = 1; in_topic = 0; next }
    /^#/ { in_topic = 0; in_intents = 0; next }
    in_topic  && /[^ \t]/ { topic = topic $0 "\n" }
    in_intents && /[^ \t]/ { intents = intents $0 "\n" }
    END { flush() }
  ')"

  if [[ -n "$sibling_out" ]]; then
    printf '\n=== SIBLING_THREADS ===\n'
    echo "$sibling_out"
  fi
fi

# ── INITIATIVE (omit section if NONE) ───────────────────
initiative="$(extract_section "INITIATIVE")"
if [[ -n "$initiative" ]] && ! echo "$initiative" | grep -qx 'NONE'; then
  printf '\n=== INITIATIVE ===\n'
  echo "$initiative"
fi
