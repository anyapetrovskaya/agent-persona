#!/usr/bin/env bash
# query-knowledge/post.sh — eval log, access tracking, output clean report
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
EVAL_FILE="$BASE/data/eval/eval_log.json"
EVAL_APPEND="$BASE/scripts/eval-append.sh"
MARK_ACCESSED="$BASE/scripts/mark-accessed.sh"

# --- Parse args ---
QUERY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --query) QUERY="$2"; shift 2 ;;
    *)       echo "Unknown arg: $1" >&2; shift ;;
  esac
done
[[ -z "$QUERY" ]] && { echo "ERROR: --query required" >&2; exit 1; }

# --- Read stdin ---
INPUT=$(cat)

# --- Extract EVAL_DATA section (same awk pattern as other post.sh scripts) ---
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
MODE=$(echo "$EVAL_SECTION" | sed -n 's/.*mode:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)
K_MATCHES=$(echo "$EVAL_SECTION" | sed -n 's/.*knowledge_matches:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)
E_MATCHES=$(echo "$EVAL_SECTION" | sed -n 's/.*episode_matches:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)
G_PATHS=$(echo "$EVAL_SECTION" | sed -n 's/.*graph_paths:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)
ST_MATCHES=$(echo "$EVAL_SECTION" | sed -n 's/.*short_term_matches:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)

MODE="${MODE:-graph-enhanced}"
K_MATCHES="${K_MATCHES:-0}"
E_MATCHES="${E_MATCHES:-0}"
G_PATHS="${G_PATHS:-0}"
ST_MATCHES="${ST_MATCHES:-0}"

# --- Eval logging (skip silently on failure) ---
mkdir -p "$(dirname "$EVAL_FILE")"
if [[ ! -f "$EVAL_FILE" ]]; then
  echo '{"schema_version": 1, "events": []}' > "$EVAL_FILE"
fi

if bash "$EVAL_APPEND" --type retrieval \
    --query "$QUERY" \
    --mode "$MODE" \
    --knowledge_matches "$K_MATCHES" \
    --episode_matches "$E_MATCHES" \
    --short_term_matches "$ST_MATCHES" \
    --graph_paths "$G_PATHS" &>/dev/null; then
  : # logged
else
  # Fallback: append via jq if eval-append fails
  TS=$(date -Iseconds)
  EVT=$(jq -n \
    --arg ts "$TS" \
    --arg q "$QUERY" \
    --arg m "$MODE" \
    --arg km "$K_MATCHES" \
    --arg em "$E_MATCHES" \
    --arg stm "$ST_MATCHES" \
    --arg gp "$G_PATHS" \
    '{id: ("evt_" + $ts), ts: $ts, type: "retrieval", data: {query: $q, mode: $m, knowledge_matches: $km, episode_matches: $em, short_term_matches: $stm, graph_paths: $gp}}')
  if jq --argjson evt "$EVT" '.events += [$evt]' "$EVAL_FILE" > "${EVAL_FILE}.tmp" 2>/dev/null && mv "${EVAL_FILE}.tmp" "$EVAL_FILE"; then
    : # fallback logged
  fi
  # If both fail, skip silently
fi

# --- Debug ---
DEBUG=$(jq -r '.debug // false' "$BASE/config.json" 2>/dev/null || echo "false")
if [[ "$DEBUG" == "true" ]]; then
  echo "post.sh: query=$QUERY mode=$MODE knowledge_matches=$K_MATCHES episode_matches=$E_MATCHES short_term_matches=$ST_MATCHES graph_paths=$G_PATHS" >&2
fi

# --- Track access on matched knowledge items (fire-and-forget) ---
if [[ -x "$MARK_ACCESSED" ]] && [[ "${K_MATCHES:-0}" != "0" ]]; then
  # Extract content strings from "## Knowledge matches" section
  # Lines look like: - **[type]** content text (strength: N, source: S)
  # or:              - **[type] ⚠ CONTESTED** content text (...)
  MATCHED_CONTENT=$(echo "$INPUT" | awk '
    /^## Knowledge matches/ { in_section=1; next }
    /^## / && in_section { exit }
    in_section && /^- \*\*\[/ {
      # Strip everything up to and including the closing **
      sub(/^- \*\*[^*]*\*\* */, "")
      # Strip trailing (strength: ...) parenthetical
      sub(/ *\(strength:.*$/, "")
      gsub(/^ +| +$/, "")
      if (length > 0) print
    }
  ')
  if [[ -n "$MATCHED_CONTENT" ]]; then
    echo "$MATCHED_CONTENT" | bash "$MARK_ACCESSED" &>/dev/null &
  fi
fi

# --- Strip EVAL_DATA section, output clean report ---
echo "$INPUT" | awk '
  /^=== EVAL_DATA ===$/ { skip=1; next }
  skip && /^=== .+ ===$/ { skip=0 }
  skip { next }
  { print }
'
