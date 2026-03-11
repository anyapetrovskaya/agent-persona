#!/usr/bin/env bash
# reflect/post.sh — parse reflection output, write data files, output clean report
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
DATA="$BASE/data"
EVAL_FILE="$DATA/eval/eval_log.json"
REFLECTIONS_FILE="$DATA/eval/reflections.json"
NOTES_FILE="$DATA/procedural_notes.json"
EVAL_APPEND="$BASE/scripts/eval-append.sh"

# --- Read stdin ---
INPUT=$(cat)

# --- Extract sections ---
extract_section() {
  local name="$1"
  local marker="=== ${name} ==="
  echo "$INPUT" | awk -v m="$marker" '
    $0 == m { found=1; next }
    found && /^=== .+ ===$/ { exit }
    found { print }
  '
}

REFLECTION_ENTRY=$(extract_section "REFLECTION_ENTRY" | grep -v '^[[:space:]]*$' | head -1)
UPDATED_NOTES=$(extract_section "UPDATED_NOTES" | grep -v '^[[:space:]]*$' | head -1)
EVAL_EVENT=$(extract_section "EVAL_EVENT" | grep -v '^[[:space:]]*$' | head -1)

# --- 1. Append reflection entry ---
if [[ -n "$REFLECTION_ENTRY" ]] && echo "$REFLECTION_ENTRY" | jq empty 2>/dev/null; then
  mkdir -p "$(dirname "$REFLECTIONS_FILE")"
  if [[ -f "$REFLECTIONS_FILE" ]]; then
    EXISTING=$(jq -c '.' "$REFLECTIONS_FILE")
    if echo "$EXISTING" | jq -e 'type == "array"' &>/dev/null; then
      echo "$EXISTING" | jq --argjson entry "$REFLECTION_ENTRY" '. += [$entry]' > "${REFLECTIONS_FILE}.tmp"
    elif echo "$EXISTING" | jq -e '.reflections' &>/dev/null; then
      echo "$EXISTING" | jq --argjson entry "$REFLECTION_ENTRY" '.reflections += [$entry]' > "${REFLECTIONS_FILE}.tmp"
    else
      jq -n --argjson entry "$REFLECTION_ENTRY" '[$entry]' > "${REFLECTIONS_FILE}.tmp"
    fi
  else
    jq -n --argjson entry "$REFLECTION_ENTRY" '[$entry]' > "${REFLECTIONS_FILE}.tmp"
  fi
  mv "${REFLECTIONS_FILE}.tmp" "$REFLECTIONS_FILE"
fi

# --- 2. Write updated procedural notes ---
if [[ -n "$UPDATED_NOTES" ]] && echo "$UPDATED_NOTES" | jq empty 2>/dev/null; then
  echo "$UPDATED_NOTES" | jq '.' > "${NOTES_FILE}.tmp"
  mv "${NOTES_FILE}.tmp" "$NOTES_FILE"
fi

# --- 3. Append eval event ---
if [[ -n "$EVAL_EVENT" ]] && echo "$EVAL_EVENT" | jq empty 2>/dev/null; then
  TS=$(date -Iseconds)
  FULL_EVENT=$(echo "$EVAL_EVENT" | jq --arg ts "$TS" '. + {id: ("evt_" + $ts), ts: $ts}')
  
  mkdir -p "$(dirname "$EVAL_FILE")"
  if [[ ! -f "$EVAL_FILE" ]]; then
    echo '{"schema_version": 1, "events": []}' > "$EVAL_FILE"
  fi
  
  if bash "$EVAL_APPEND" --type reflection \
      --observations_count "$(echo "$EVAL_EVENT" | jq -r '.data.observations_count // 0')" \
      --adjustments_count "$(echo "$EVAL_EVENT" | jq -r '.data.adjustments_count // 0')" \
      --verifications_count "$(echo "$EVAL_EVENT" | jq -r '.data.verifications_count // 0')" \
      --notes_active "$(echo "$EVAL_EVENT" | jq -r '.data.notes_active // 0')" \
      --notes_pending "$(echo "$EVAL_EVENT" | jq -r '.data.notes_pending // 0')" &>/dev/null; then
    : # logged via eval-append
  else
    # Fallback: append directly
    if jq --argjson evt "$FULL_EVENT" '.events += [$evt]' "$EVAL_FILE" > "${EVAL_FILE}.tmp" 2>/dev/null; then
      mv "${EVAL_FILE}.tmp" "$EVAL_FILE"
    fi
  fi
fi

# --- 4. Debug ---
DEBUG=$(jq -r '.debug // false' "$BASE/config.json" 2>/dev/null || echo "false")
if [[ "$DEBUG" == "true" ]]; then
  REF_ID=$(echo "$REFLECTION_ENTRY" | jq -r '.id // "unknown"' 2>/dev/null || echo "unknown")
  OBS=$(echo "$EVAL_EVENT" | jq -r '.data.observations_count // 0' 2>/dev/null || echo "0")
  ADJ=$(echo "$EVAL_EVENT" | jq -r '.data.adjustments_count // 0' 2>/dev/null || echo "0")
  VER=$(echo "$EVAL_EVENT" | jq -r '.data.verifications_count // 0' 2>/dev/null || echo "0")
  echo "post.sh: ref=$REF_ID observations=$OBS adjustments=$ADJ verifications=$VER" >&2
fi

# --- 5. Output clean report (REPORT section only) ---
extract_section "REPORT"
