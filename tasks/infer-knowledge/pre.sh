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

# ── 1. Compute decay ────────────────────────────────────────────────────────
DECAY_RC=0
DECAY_OUT=$(bash "$SCRIPTS/compute-decay.sh" 2>&1) || DECAY_RC=$?
log "Decay: $DECAY_OUT"
if [[ -f "$KNOWLEDGE" ]]; then validate_json "$KNOWLEDGE" "compute-decay"; fi

# ── 2. Auto-remove forgotten items (retention_score < 0.5, not pinned) ──────
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

# ── 3. Exact-match dedup ────────────────────────────────────────────────────
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

# ── 4. Snapshot script-managed fields ───────────────────────────────────────
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

# ── 5. Collect stats ─────────────────────────────────────────────────────────
if [[ -f "$KNOWLEDGE" ]]; then
  ITEM_COUNT=$(jq '.items | length' "$KNOWLEDGE")
  FADING_COUNT=$(jq '[.items[] | select(.retention_score != null and .retention_score >= 0.5 and .retention_score < 1.5 and (.pinned != true))] | length' "$KNOWLEDGE")
  HEALTHY_COUNT=$(jq '[.items[] | select(.retention_score == null or .retention_score >= 1.5 or .pinned == true)] | length' "$KNOWLEDGE")
  SURFACING=$(jq -c '[.items[] | select((.emotional_value != null and ((.emotional_value > 1.5) or (.emotional_value < -1.5))) and (.retention_score != null and .retention_score < 1.5)) | {type, content: (.content[:80]), emotional_value, retention_score}]' "$KNOWLEDGE")
  SURFACING_COUNT=$(echo "$SURFACING" | jq 'length')
else
  ITEM_COUNT=0; FADING_COUNT=0; HEALTHY_COUNT=0; SURFACING="[]"; SURFACING_COUNT=0
fi

# ── 6. Graph context for LLM ────────────────────────────────────────────────
GRAPH_NODES=""
GRAPH_EDGES=""
if [[ -f "$GRAPH" ]]; then
  GRAPH_NODES=$(jq -c '[.nodes[] | {id, name, type, aliases: (.aliases // [])}]' "$GRAPH" 2>/dev/null || echo '[]')
  GRAPH_EDGES=$(jq -c '[.edges[] | {id, source, target, type, fact}]' "$GRAPH" 2>/dev/null || echo '[]')
fi

# ── 7. Short-term transcripts (atomic snapshot) ────────────────────────────
ST_DIR="$DATA_DIR/short-term"
mkdir -p "$ST_DIR/to_process"
for f in "$ST_DIR"/*.jsonl; do
  [[ -f "$f" ]] && mv "$f" "$ST_DIR/to_process/"
done
ST_CONTENT=""
if [[ -d "$ST_DIR/to_process" ]]; then
  for f in "$ST_DIR/to_process"/*.jsonl; do
    [[ -f "$f" ]] || continue
    ST_CONTENT="${ST_CONTENT}$(cat "$f")
"
  done
fi

# ── 8. Living doc changes since last inference ───────────────────────────
LIVING_DOC_DIFF=""
LIVING_DOCS_DIR="$DATA_DIR/living-docs"
LAST_COMMIT_FILE="$DATA_DIR/.staging/last_infer_commit.txt"
if [[ -d "$LIVING_DOCS_DIR" ]] && git -C "$AP_DIR" rev-parse --git-dir &>/dev/null; then
  if [[ -f "$LAST_COMMIT_FILE" ]]; then
    LAST_COMMIT=$(cat "$LAST_COMMIT_FILE")
    if git -C "$AP_DIR" cat-file -t "$LAST_COMMIT" &>/dev/null; then
      LIVING_DOC_DIFF=$(git -C "$AP_DIR" diff --stat --patch "$LAST_COMMIT" -- "$LIVING_DOCS_DIR" 2>/dev/null || true)
    fi
  fi
  if [[ -z "$LIVING_DOC_DIFF" ]]; then
    shopt -s nullglob
    LD_FILES=("$LIVING_DOCS_DIR"/*.md "$LIVING_DOCS_DIR"/*.json "$LIVING_DOCS_DIR"/*.txt)
    shopt -u nullglob
    for ldf in "${LD_FILES[@]}"; do
      LIVING_DOC_DIFF+="--- $(basename "$ldf") (full content, first run) ---"$'\n'
      LIVING_DOC_DIFF+="$(cat "$ldf")"$'\n\n'
    done
  fi
fi

# ── Output summary ───────────────────────────────────────────────────────────
echo "=== PRE-PROCESSING COMPLETE ==="
echo ""
printf "%s" "$SUMMARY"
echo ""
echo "Knowledge: $ITEM_COUNT items ($HEALTHY_COUNT healthy, $FADING_COUNT fading, $FORGOTTEN forgotten/removed)"
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
echo "=== SHORT-TERM MEMORY ==="
echo "$ST_CONTENT"
echo ""
echo "=== LIVING DOC CHANGES ==="
echo "$LIVING_DOC_DIFF"
