#!/usr/bin/env bash
# infer-knowledge/pre.sh — deterministic pre-processing (zero LLM tokens)
set -euo pipefail

AP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DATA_DIR="$AP_DIR/data"
KNOWLEDGE="$DATA_DIR/knowledge/knowledge.json"
GRAPH="$DATA_DIR/knowledge/memory_graph.json"
SCRIPTS="$AP_DIR/scripts"

TODAY=$(date +%Y-%m-%d)
SUMMARY=""
log() { SUMMARY="${SUMMARY}$1"$'\n'; }

validate_json() {
  local file="$1" label="$2"
  if ! jq empty "$file" 2>/dev/null; then
    echo "ERROR: $label corrupted $file" >&2
    exit 1
  fi
}

FIELD_BLOCKLIST=(
  "type" "content" "turn" "timestamp" "emotional_value" "session"
  "entity_name" "source" "category" "emotional_valence" "context" "summary"
)

# ── Gather episode file lists (needed by field-frequency + final output) ─────
shopt -s nullglob
TO_SCAN_FILES=("$DATA_DIR/episodic/to_scan"/episode_*.json)
ACTIVE_FILES=("$DATA_DIR/episodic"/episode_*.json)
ALL_EP_FILES=("${TO_SCAN_FILES[@]}" "${ACTIVE_FILES[@]}")
shopt -u nullglob

# ── 1. Field-frequency boosting (single-pass) ───────────────────────────────
FIELD_BOOSTED=0
if (( ${#ALL_EP_FILES[@]} > 0 )) && [[ -f "$KNOWLEDGE" ]]; then
  BLOCKLIST_JQ=$(printf '%s\n' "${FIELD_BLOCKLIST[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')

  FIELD_FREQ=$(jq -s --argjson bl "$BLOCKLIST_JQ" '
    [.[].records[] | keys[]] |
    group_by(.) |
    map({field: .[0], count: length}) |
    [.[] | select(
      .count >= 50 and
      (.field as $f | $bl | map(ascii_downcase) | index($f | ascii_downcase) | not)
    )] |
    sort_by(-.count)
  ' "${ALL_EP_FILES[@]}" 2>/dev/null || echo '[]')

  FREQ_COUNT=$(echo "$FIELD_FREQ" | jq 'length')

  if (( FREQ_COUNT > 0 )); then
    BOOST_MAP=$(echo "$FIELD_FREQ" | jq '
      [.[] | {
        key: .field,
        value: ((.count / 50 | floor) | if . > 5 then 5 elif . < 1 then 1 else . end)
      }] | from_entries
    ')

    FIELD_BOOSTED=$(jq --argjson boosts "$BOOST_MAP" '
      [.items[] | . as $item | select(
        any($boosts | to_entries[];
          . as $e | $item.content | ascii_downcase | contains($e.key | ascii_downcase)
        )
      )] | length
    ' "$KNOWLEDGE")

    jq --argjson boosts "$BOOST_MAP" --arg today "$TODAY" '
      .items |= [.[] |
        reduce ($boosts | to_entries[]) as $e (.;
          if (.content | ascii_downcase | contains($e.key | ascii_downcase)) then
            .strength = ([(.strength // 1) + $e.value, 5] | min) |
            if ((.source // "") | contains("field-freq:" + $today)) then .
            else .source = ((.source // "") + " field-freq:" + $today) end
          else . end
        )
      ]
    ' "$KNOWLEDGE" > "${KNOWLEDGE}.tmp" && mv "${KNOWLEDGE}.tmp" "$KNOWLEDGE"
  fi
  log "Field-frequency: boosted $FIELD_BOOSTED items"
fi

# ── 2. Compute decay (now sees boosted strengths) ────────────────────────────
DECAY_RC=0
DECAY_OUT=$(bash "$SCRIPTS/compute-decay.sh" 2>&1) || DECAY_RC=$?
log "Decay: $DECAY_OUT"
if [[ -f "$KNOWLEDGE" ]]; then validate_json "$KNOWLEDGE" "compute-decay"; fi

# ── 3. Auto-remove forgotten items (retention_score < 0.5, not pinned) ──────
FORGOTTEN=0
FORGOTTEN_ITEMS="[]"
if [[ -f "$KNOWLEDGE" ]]; then
  FORGOTTEN=$(jq '[.items[] | select(.retention_score != null and .retention_score < 0.5 and (.pinned != true))] | length' "$KNOWLEDGE")
  if (( FORGOTTEN > 0 )); then
    ARCHIVE="$DATA_DIR/knowledge/archive.json"
    ITEMS_TO_ARCHIVE=$(jq -c --arg today "$TODAY" '
      [.items[] |
        select(.retention_score != null and .retention_score < 0.5 and (.pinned != true)) |
        . + {archived_date: $today, reason: "auto-decay"}
      ]
    ' "$KNOWLEDGE")

    if [[ -f "$ARCHIVE" ]] && jq empty "$ARCHIVE" 2>/dev/null; then
      jq --argjson new "$ITEMS_TO_ARCHIVE" '.archived_items += $new' \
        "$ARCHIVE" > "${ARCHIVE}.tmp" && mv "${ARCHIVE}.tmp" "$ARCHIVE"
    else
      echo "$ITEMS_TO_ARCHIVE" | jq '{archived_items: .}' > "$ARCHIVE"
    fi

    FORGOTTEN_ITEMS=$(jq -c '[.items[] | select(.retention_score != null and .retention_score < 0.5 and (.pinned != true)) | {type, content: (.content[:80]), retention_score}]' "$KNOWLEDGE")
    jq '.items |= [.[] | select(.retention_score == null or .retention_score >= 0.5 or .pinned == true)]' \
      "$KNOWLEDGE" > "${KNOWLEDGE}.tmp" && mv "${KNOWLEDGE}.tmp" "$KNOWLEDGE"
    log "Forgotten: removed $FORGOTTEN items (archived)"
  else
    log "Forgotten: 0"
  fi
fi

# ── 4. Exact-match dedup ────────────────────────────────────────────────────
DEDUPED=0
if [[ -f "$KNOWLEDGE" ]]; then
  BEFORE_COUNT=$(jq '.items | length' "$KNOWLEDGE")
  jq '
    .items |= (
      group_by(.content) | map(
        if length == 1 then .[0]
        else
          sort_by(-(.strength // 0)) |
          .[0] as $best |
          reduce .[1:][] as $dup ($best;
            .source = (
              [(.source // ""), ($dup.source // "")] |
              map(select(. != null and . != "")) |
              join(" ")
            ) |
            .created = (
              [.created, $dup.created] |
              map(select(. != null and . != "")) |
              sort | .[0] // .created
            )
          )
        end
      )
    )
  ' "$KNOWLEDGE" > "${KNOWLEDGE}.tmp" && mv "${KNOWLEDGE}.tmp" "$KNOWLEDGE"
  AFTER_COUNT=$(jq '.items | length' "$KNOWLEDGE")
  DEDUPED=$(( BEFORE_COUNT - AFTER_COUNT ))
  if (( DEDUPED > 0 )); then
    log "Dedup: merged $DEDUPED duplicate items"
  fi
fi

# ── 5. Snapshot script-managed fields ───────────────────────────────────────
if [[ -f "$KNOWLEDGE" ]]; then
  mkdir -p "$DATA_DIR/.staging"
  jq '{items: [.items | to_entries[] | {
    index: .key,
    content: .value.content,
    pinned: (.value.pinned // false),
    last_accessed: (.value.last_accessed // null),
    access_count: (.value.access_count // 0),
    retention_score: (.value.retention_score // null)
  }]}' "$KNOWLEDGE" > "$DATA_DIR/.staging/field-snapshot.json"
fi

# ── 6. Collect stats ─────────────────────────────────────────────────────────
if [[ -f "$KNOWLEDGE" ]]; then
  ITEM_COUNT=$(jq '.items | length' "$KNOWLEDGE")
  FADING_COUNT=$(jq '[.items[] | select(.retention_score != null and .retention_score >= 0.5 and .retention_score < 1.5 and (.pinned != true))] | length' "$KNOWLEDGE")
  HEALTHY_COUNT=$(jq '[.items[] | select(.retention_score == null or .retention_score >= 1.5 or .pinned == true)] | length' "$KNOWLEDGE")
  SURFACING=$(jq -c '[.items[] | select((.emotional_value != null and ((.emotional_value > 1.5) or (.emotional_value < -1.5))) and (.retention_score != null and .retention_score < 1.5)) | {type, content: (.content[:80]), emotional_value, retention_score}]' "$KNOWLEDGE")
  SURFACING_COUNT=$(echo "$SURFACING" | jq 'length')
else
  ITEM_COUNT=0; FADING_COUNT=0; HEALTHY_COUNT=0; SURFACING="[]"; SURFACING_COUNT=0
fi

# ── 7. List episode files ───────────────────────────────────────────────────
EP_LIST=""
for f in "${ALL_EP_FILES[@]}"; do
  EP_LIST="${EP_LIST}  $(basename "$f")"$'\n'
done

# ── 8. Graph context for LLM ────────────────────────────────────────────────
GRAPH_NODES=""
GRAPH_EDGES=""
if [[ -f "$GRAPH" ]]; then
  GRAPH_NODES=$(jq -c '[.nodes[] | {id, name, type, aliases: (.aliases // [])}]' "$GRAPH" 2>/dev/null || echo '[]')
  GRAPH_EDGES=$(jq -c '[.edges[] | {id, source, target, type, fact}]' "$GRAPH" 2>/dev/null || echo '[]')
fi

# ── Output summary ───────────────────────────────────────────────────────────
echo "=== PRE-PROCESSING COMPLETE ==="
echo ""
printf "%s" "$SUMMARY"
echo ""
echo "Knowledge: $ITEM_COUNT items ($HEALTHY_COUNT healthy, $FADING_COUNT fading, $FORGOTTEN forgotten/removed)"
echo "Schema: $FIELD_BOOSTED field-boosted"
if (( DEDUPED > 0 )); then echo "Dedup: $DEDUPED duplicates merged"; fi
echo "Surfacing: $SURFACING_COUNT candidates"
[[ "$SURFACING_COUNT" -gt 0 ]] && echo "Surfacing items: $SURFACING"
if [[ "$FORGOTTEN" -gt 0 ]]; then
  echo "Forgotten items: $FORGOTTEN_ITEMS"
fi
echo ""
echo "=== EXISTING GRAPH ==="
echo "Nodes: $GRAPH_NODES"
echo "Edges: $GRAPH_EDGES"
echo ""
echo "Episodes to process:"
printf "%s" "$EP_LIST"
