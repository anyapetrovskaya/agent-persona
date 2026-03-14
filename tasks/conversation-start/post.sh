#!/usr/bin/env bash
# conversation-start/post.sh — parse sub-agent output, log handoff_check, pass clean report
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
EVAL_FILE="$BASE/data/eval/eval_log.json"
EVAL_APPEND="$BASE/scripts/eval-append.sh"

# --- Parse args ---
MODE="" HANDOFF_EXISTED="" ITEMS_COUNT=""
HANDOFF_QUALITY="" HANDOFF_RELEVANCE="" REASON="" KNOWLEDGE_FALLBACK=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)              MODE="$2"; shift 2 ;;
    --handoff-existed)   HANDOFF_EXISTED="$2"; shift 2 ;;
    --items-count)       ITEMS_COUNT="$2"; shift 2 ;;
    --handoff-quality)   HANDOFF_QUALITY="$2"; shift 2 ;;
    --handoff-relevance) HANDOFF_RELEVANCE="$2"; shift 2 ;;
    --reason)            REASON="$2"; shift 2 ;;
    --knowledge-fallback-items) KNOWLEDGE_FALLBACK="$2"; shift 2 ;;
    *)                   echo "Unknown arg: $1" >&2; shift ;;
  esac
done
[[ -z "$MODE" ]] && { echo "ERROR: --mode required" >&2; exit 1; }
[[ -z "$HANDOFF_EXISTED" ]] && { echo "ERROR: --handoff-existed required" >&2; exit 1; }
[[ -z "$ITEMS_COUNT" ]] && { echo "ERROR: --items-count required" >&2; exit 1; }

# --- Read stdin ---
INPUT=$(cat)

# --- Extract EVAL_DATA section ---
extract_section() {
  local name="$1"
  local marker="=== ${name} ==="
  echo "$INPUT" | awk -v m="$marker" '
    $0 == m { found=1; next }
    found && /^=== .+ ===$/ { exit }
    found { print }
  '
}

EVAL_SECTION=$(extract_section "EVAL_DATA")

# New fields (prefer CLI args, fall back to EVAL_DATA section from stdin)
if [[ -z "$HANDOFF_QUALITY" ]]; then
  HANDOFF_QUALITY=$(echo "$EVAL_SECTION" | sed -n 's/.*handoff_quality:[[:space:]]*\(\S\+\).*/\1/p' | head -1)
fi
HANDOFF_QUALITY="${HANDOFF_QUALITY:-poor}"

if [[ -z "$HANDOFF_RELEVANCE" ]]; then
  HANDOFF_RELEVANCE=$(echo "$EVAL_SECTION" | sed -n 's/.*handoff_relevance:[[:space:]]*\(\S\+\).*/\1/p' | head -1)
fi
HANDOFF_RELEVANCE="${HANDOFF_RELEVANCE:-none}"

if [[ -z "$REASON" ]]; then
  REASON=$(echo "$EVAL_SECTION" | sed -n 's/.*reason:[[:space:]]*\(.*\)/\1/p' | head -1)
fi
REASON="${REASON:-no reason provided}"

if [[ -z "$KNOWLEDGE_FALLBACK" ]]; then
  KNOWLEDGE_FALLBACK=$(echo "$EVAL_SECTION" | sed -n 's/.*knowledge_fallback_items:[[:space:]]*\(\S\+\).*/\1/p' | head -1)
fi
KNOWLEDGE_FALLBACK="${KNOWLEDGE_FALLBACK:-0}"

# Backward compat: derive self_assessed_useful from new fields
SELF_ASSESSED="false"
if [[ "$HANDOFF_QUALITY" != "poor" || "$HANDOFF_RELEVANCE" != "none" ]]; then
  SELF_ASSESSED="true"
fi

# --- Strip EVAL_DATA from output (pass clean report to main agent) ---
strip_eval() {
  echo "$INPUT" | awk '
    /^=== EVAL_DATA ===$/ { skip=1; next }
    skip && /^=== .+ ===$/ { skip=0 }
    skip { next }
    { print }
  '
}

# --- Eval logging ---
mkdir -p "$(dirname "$EVAL_FILE")"
if [[ ! -f "$EVAL_FILE" ]]; then
  echo '{"schema_version": 1, "events": []}' > "$EVAL_FILE"
fi

if bash "$EVAL_APPEND" --type handoff_check \
    --handoff_existed "$HANDOFF_EXISTED" \
    --items_referenced "$ITEMS_COUNT" \
    --self_assessed_useful "$SELF_ASSESSED" \
    --handoff_quality "$HANDOFF_QUALITY" \
    --handoff_relevance "$HANDOFF_RELEVANCE" \
    --knowledge_fallback_items "$KNOWLEDGE_FALLBACK" \
    --reason "$REASON" \
    --mode "$MODE" &>/dev/null; then
  : # logged
else
  # Fallback: append via jq if eval-append fails
  TS=$(date -Iseconds)
  EVT=$(jq -n \
    --arg ts "$TS" \
    --argjson he "$([ "$HANDOFF_EXISTED" = "true" ] && echo true || echo false)" \
    --arg ic "$ITEMS_COUNT" \
    --argjson sau "$([ "$SELF_ASSESSED" = "true" ] && echo true || echo false)" \
    --arg hq "$HANDOFF_QUALITY" \
    --arg hr "$HANDOFF_RELEVANCE" \
    --arg kf "$KNOWLEDGE_FALLBACK" \
    --arg reason "$REASON" \
    --arg m "$MODE" \
    '{id: ("evt_" + $ts), ts: $ts, type: "handoff_check", data: {handoff_existed: $he, items_referenced: ($ic | tonumber), self_assessed_useful: $sau, handoff_quality: $hq, handoff_relevance: $hr, knowledge_fallback_items: ($kf | tonumber), reason: $reason, mode: $m}}')
  jq --argjson evt "$EVT" '.events += [$evt]' "$EVAL_FILE" > "${EVAL_FILE}.tmp" && mv "${EVAL_FILE}.tmp" "$EVAL_FILE"
fi

# --- Debug ---
DEBUG=$(jq -r '.debug // false' "$BASE/config.json" 2>/dev/null || echo "false")
if [[ "$DEBUG" == "true" ]]; then
  echo "post.sh: mode=$MODE handoff_existed=$HANDOFF_EXISTED items=$ITEMS_COUNT quality=$HANDOFF_QUALITY relevance=$HANDOFF_RELEVANCE knowledge_fallback=$KNOWLEDGE_FALLBACK reason=\"$REASON\" self_assessed=$SELF_ASSESSED" >&2
fi

# --- Output clean report ---
strip_eval
