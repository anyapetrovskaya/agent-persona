#!/usr/bin/env bash
# infer-knowledge/post.sh — post-processing: enforce invariants, validate graph, archive, timeline, cleanup
set -euo pipefail

AP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DATA_DIR="$AP_DIR/data"
KNOWLEDGE="$DATA_DIR/knowledge/knowledge.json"
GRAPH="$DATA_DIR/knowledge/memory_graph.json"
SNAPSHOT="$DATA_DIR/.staging/field-snapshot.json"
TODAY=$(date +%Y-%m-%d)
REPORT=$(cat)

# ── 0. Success check ─────────────────────────────────────────────────────────
if [[ -z "$REPORT" ]] || ! echo "$REPORT" | grep -qiE 'Processed|items|added|updated|pruned|Counts'; then
  echo "ERROR: LLM report is empty or malformed — aborting without archiving episodes" >&2
  exit 1
fi

# ── 1. Strength cap enforcement ──────────────────────────────────────────────
if [[ -f "$KNOWLEDGE" ]]; then
  CAPPED=$(jq '[.items[] | select(.strength > 5)] | length' "$KNOWLEDGE")
  jq '.items |= [.[] | .strength = ([.strength, 5] | min)]' \
    "$KNOWLEDGE" > "${KNOWLEDGE}.tmp" && mv "${KNOWLEDGE}.tmp" "$KNOWLEDGE"
  (( CAPPED > 0 )) && echo "post.sh: clamped strength on $CAPPED items (max 5)" >&2
fi

# ── 2. Pinned-item safety ────────────────────────────────────────────────────
if [[ -f "$SNAPSHOT" ]] && [[ -f "$KNOWLEDGE" ]]; then
  PINNED_SNAPSHOT=$(jq -c '[.items[] | select(.pinned == true) | .content]' "$SNAPSHOT" 2>/dev/null || echo '[]')
  PINNED_CURRENT=$(jq -c '[.items[] | select(.pinned == true) | .content]' "$KNOWLEDGE" 2>/dev/null || echo '[]')

  MISSING=$(jq -n --argjson snap "$PINNED_SNAPSHOT" --argjson curr "$PINNED_CURRENT" \
    '$snap - $curr')
  MISSING_COUNT=$(echo "$MISSING" | jq 'length')

  if (( MISSING_COUNT > 0 )); then
    echo "post.sh: WARNING — $MISSING_COUNT pinned items were dropped by LLM, restoring" >&2
    RESTORED_ITEMS=$(jq -c --argjson missing "$MISSING" \
      '[.items[] | select(.pinned == true and (.content as $c | $missing | index($c) != null))]' \
      "$SNAPSHOT")
    jq --argjson restored "$RESTORED_ITEMS" \
      '.items += $restored' \
      "$KNOWLEDGE" > "${KNOWLEDGE}.tmp" && mv "${KNOWLEDGE}.tmp" "$KNOWLEDGE"
  fi
fi

# ── 3. Schema validation ─────────────────────────────────────────────────────
if [[ -f "$KNOWLEDGE" ]]; then
  VALID_TYPES='["preference","convention","fact","rule","trait"]'
  INVALID_ITEMS=$(jq --argjson types "$VALID_TYPES" '
    [.items | to_entries[] |
      select(
        (.value.type as $t | $types | index($t) == null) or
        (.value.content == null or .value.content == "") or
        (.value.created == null or .value.created == "")
      ) | {index: .key, type: .value.type, content: (.value.content // "<empty>")[:60], created: (.value.created // "<missing>")}
    ]' "$KNOWLEDGE")
  INVALID_COUNT=$(echo "$INVALID_ITEMS" | jq 'length')
  if (( INVALID_COUNT > 0 )); then
    echo "post.sh: WARNING — $INVALID_COUNT items have schema issues (not removed):" >&2
    echo "$INVALID_ITEMS" | jq -r '.[] | "  idx \(.index): type=\(.type) content=\(.content) created=\(.created)"' >&2
  fi
fi

# ── 4. Trait scope enforcement ────────────────────────────────────────────────
if [[ -f "$KNOWLEDGE" ]]; then
  TRAIT_FIXED=$(jq '[.items[] | select(.type == "trait" and .scope != "user")] | length' "$KNOWLEDGE")
  jq '.items |= [.[] | if .type == "trait" then .scope = "user" else . end]' \
    "$KNOWLEDGE" > "${KNOWLEDGE}.tmp" && mv "${KNOWLEDGE}.tmp" "$KNOWLEDGE"
  (( TRAIT_FIXED > 0 )) && echo "post.sh: forced scope=user on $TRAIT_FIXED trait items" >&2
fi

# ── 5. Script-managed field restoration ───────────────────────────────────────
if [[ -f "$SNAPSHOT" ]] && [[ -f "$KNOWLEDGE" ]]; then
  RESTORED_FIELDS=$(jq --slurpfile snap "$SNAPSHOT" '
    ($snap[0].items | map({key: .content, value: {last_accessed, access_count, pinned, retention_score}}) | from_entries) as $lookup |
    .items |= [to_entries | .[] |
      .value as $item |
      if ($lookup[$item.content] != null) then
        ($lookup[$item.content]) as $orig |
        .value.last_accessed = $orig.last_accessed |
        .value.access_count = $orig.access_count |
        .value.pinned = $orig.pinned |
        .value.retention_score = $orig.retention_score
      else . end |
      .value
    ]' "$KNOWLEDGE")
  RESTORE_COUNT=$(jq -n --argjson snap "$(jq '.items | length' "$SNAPSHOT")" '$snap')
  echo "$RESTORED_FIELDS" > "${KNOWLEDGE}.tmp" && mv "${KNOWLEDGE}.tmp" "$KNOWLEDGE"
  echo "post.sh: restored script-managed fields from snapshot ($RESTORE_COUNT items checked)" >&2
fi

# ── 6. Set last_infer_date ────────────────────────────────────────────────────
if [[ -f "$KNOWLEDGE" ]]; then
  jq --arg today "$TODAY" '.last_infer_date = $today' \
    "$KNOWLEDGE" > "${KNOWLEDGE}.tmp" && mv "${KNOWLEDGE}.tmp" "$KNOWLEDGE"
fi

# ── 7. Graph validation ──────────────────────────────────────────────────────
GRAPH_WARN=""
if [[ -f "$GRAPH" ]]; then
  ALLOWED_TYPES='["part_of","uses","reads_from","writes_to","replaced","created","motivated_by","supports","contradicts","parent_of","child_of","sibling_of","married_to","belongs_to","embodies","explores","works_at","relates_to"]'

  # 7a. Valid node references — every edge source/target must exist as a node ID
  DANGLING=$(jq --raw-output '
    (.nodes | map(.id)) as $ids |
    [.edges[] |
      (if (.source as $s | $ids | index($s) == null) then {edge: .id, field: "source", ref: .source} else empty end),
      (if (.target as $t | $ids | index($t) == null) then {edge: .id, field: "target", ref: .target} else empty end)
    ]' "$GRAPH")
  DANGLING_COUNT=$(echo "$DANGLING" | jq 'length')
  if (( DANGLING_COUNT > 0 )); then
    DANGLING_MSG="post.sh: WARNING — $DANGLING_COUNT dangling node references in graph edges:"
    DANGLING_DETAIL=$(echo "$DANGLING" | jq -r '.[] | "  edge \(.edge): \(.field)=\(.ref) not found"')
    echo "$DANGLING_MSG" >&2
    echo "$DANGLING_DETAIL" >&2
    GRAPH_WARN+="$DANGLING_COUNT dangling refs; "
  fi

  # 7b. Edge type taxonomy — warn on unrecognized types
  BAD_TYPES=$(jq --argjson allowed "$ALLOWED_TYPES" -r '
    [.edges[] | select(.type as $t | $allowed | index($t) == null) | {edge: .id, type: .type}] | unique_by(.type)' "$GRAPH")
  BAD_TYPE_COUNT=$(echo "$BAD_TYPES" | jq 'length')
  if (( BAD_TYPE_COUNT > 0 )); then
    echo "post.sh: WARNING — $BAD_TYPE_COUNT unrecognized edge types (kept):" >&2
    echo "$BAD_TYPES" | jq -r '.[] | "  edge \(.edge): type=\(.type)"' >&2
    GRAPH_WARN+="$BAD_TYPE_COUNT unknown types; "
  fi

  # 7c. Duplicate edge detection — same source+target+type, keep longer fact
  DEDUPED=$(jq '
    .edges | group_by([.source, .target, .type]) |
    map(select(length > 1) | sort_by(-(.fact // "" | length)) | .[1:][]) |
    map(.id)' "$GRAPH")
  DEDUP_COUNT=$(echo "$DEDUPED" | jq 'length')
  if (( DEDUP_COUNT > 0 )); then
    DEDUP_IDS=$(echo "$DEDUPED" | jq -r '.[]')
    echo "post.sh: deduped $DEDUP_COUNT duplicate edges (removed): $DEDUP_IDS" >&2
    jq --argjson remove "$DEDUPED" '
      .edges |= [.[] | select(.id as $eid | $remove | index($eid) == null)]' \
      "$GRAPH" > "${GRAPH}.tmp" && mv "${GRAPH}.tmp" "$GRAPH"
    GRAPH_WARN+="$DEDUP_COUNT dupes removed; "
  fi

  # 7d. Orphan node detection — nodes with zero edges (warn only)
  ORPHANS=$(jq -r '
    (.edges | map(.source, .target) | unique) as $connected |
    [.nodes[] | select(.id as $nid | $connected | index($nid) == null) | .id]' "$GRAPH")
  ORPHAN_COUNT=$(echo "$ORPHANS" | jq 'length')
  if (( ORPHAN_COUNT > 0 )); then
    ORPHAN_IDS=$(echo "$ORPHANS" | jq -r 'join(", ")')
    echo "post.sh: WARNING — $ORPHAN_COUNT orphan nodes (no edges): $ORPHAN_IDS" >&2
    GRAPH_WARN+="$ORPHAN_COUNT orphans; "
  fi

  [[ -z "$GRAPH_WARN" ]] && GRAPH_WARN="clean"
fi

# ── 8. Archive scanned episodes ──────────────────────────────────────────────
if [[ -d "$DATA_DIR/episodic/to_scan" ]]; then
  mkdir -p "$DATA_DIR/episodic/archived"
  for f in "$DATA_DIR/episodic/to_scan"/*.json; do
    [[ -f "$f" ]] && mv "$f" "$DATA_DIR/episodic/archived/"
  done
fi

# ── 9. Rebuild timeline ──────────────────────────────────────────────────────
set +e
TIMELINE_OUT=$(python3 "$AP_DIR/scripts/visualize-timeline.py" 2>&1)
TIMELINE_EXIT=$?
set -e
[[ $TIMELINE_EXIT -ne 0 ]] && TIMELINE_OUT="timeline rebuild failed"

# ── 10. Short-term cleanup ────────────────────────────────────────────────────
set +e
CLEANUP_OUT=$(bash "$AP_DIR/scripts/cleanup-short-term.sh" 2>&1)
CLEANUP_EXIT=$?
set -e
[[ $CLEANUP_EXIT -ne 0 ]] && CLEANUP_OUT="${CLEANUP_OUT:-cleanup failed}"

# ── 11. Clean staging files ──────────────────────────────────────────────────
rm -f "$DATA_DIR"/.staging/infer-knowledge-*.json
rm -f "$SNAPSHOT"
echo "post.sh: staging files cleaned" >&2

# ── Output report + post-processing ──────────────────────────────────────────
echo "$REPORT"
echo ""
echo "## Post-processing"
echo "Graph validation: ${GRAPH_WARN:-skipped (no graph file)}"
echo "Timeline: ${TIMELINE_OUT:-rebuilt}"
echo "Short-term cleanup: $CLEANUP_OUT"
