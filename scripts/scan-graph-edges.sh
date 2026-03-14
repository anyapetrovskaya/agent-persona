#!/usr/bin/env bash
# scan-graph-edges.sh — three-phase graph edge pipeline.
# --prepare: move eligible episodes from episodic/ to to_scan/
# (default): scan to_scan/, produce graph_delta.json
# --apply:   merge delta into graph, move to_scan/ → archived/, delete delta
# --dry-run: report only (no writes)
#
# Usage:
#   bash agent-persona/scripts/scan-graph-edges.sh --prepare                    # move episodes to to_scan/
#   bash agent-persona/scripts/scan-graph-edges.sh --prepare --cutoff 1773460000  # move episodes to to_scan/ (epoch cutoff)
#   bash agent-persona/scripts/scan-graph-edges.sh --apply      # merge + cleanup
#   bash agent-persona/scripts/scan-graph-edges.sh --dry-run    # report only
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
GRAPH="$BASE/data/knowledge/memory_graph.json"
EPISODIC_DIR="$BASE/data/episodic"
TO_SCAN_DIR="$BASE/data/episodic/to_scan"
ARCHIVED_DIR="$BASE/data/episodic/archived"
DELTA="$BASE/data/knowledge/graph_delta.json"

PREPARE=false
APPLY=false
DRY_RUN=false
CUTOFF=$(date +%s)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepare) PREPARE=true ;;
    --apply)   APPLY=true ;;
    --dry-run) DRY_RUN=true ;;
    --cutoff)  shift; CUTOFF="$1" ;;
  esac
  shift
done

normalize() {
  echo "$1" \
    | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' \
    | sed -E 's/([A-Z]+)([A-Z][a-z])/\1-\2/g' \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[_ .]/-/g'
}

# ── Phase 1: Prepare ─────────────────────────────────────────────────────────
if [[ "$PREPARE" == "true" ]]; then
  mkdir -p "$TO_SCAN_DIR"
  moved=0
  shopt -s nullglob
  for f in "$EPISODIC_DIR"/episode_*.json; do
    # Parse full datetime from filename: episode_YYYY-MM-DD_THH-MM-SS.json
    fname=$(basename "$f" .json)
    ep_datetime=$(echo "$fname" | sed -E 's/episode_([0-9-]+)_T([0-9]+)-([0-9]+)-([0-9]+)/\1 \2:\3:\4/')
    ep_epoch=$(date -d "$ep_datetime" +%s 2>/dev/null || echo 0)
    if (( ep_epoch > 0 && ep_epoch < CUTOFF )); then
      mv "$f" "$TO_SCAN_DIR/"
      ((moved++)) || true
    fi
  done
  shopt -u nullglob
  echo "Prepared: moved $moved episodes to to_scan/ (cutoff: $CUTOFF)"
fi

# ── Phase 2: Scan (runs unless --apply only) ─────────────────────────────────
if [[ "$APPLY" != "true" ]] && [[ "$PREPARE" != "true" ]]; then
  [[ -f "$GRAPH" ]] || { echo "ERROR: memory_graph.json not found" >&2; exit 1; }
  mkdir -p "$TO_SCAN_DIR"

  shopt -s nullglob
  SCAN_FILES=("$TO_SCAN_DIR"/episode_*.json)
  shopt -u nullglob

  if (( ${#SCAN_FILES[@]} == 0 )); then
    echo "No episodes to scan in to_scan/"
    echo '{"created":"'"$(date -Iseconds)"'","new_edges":[],"reinforced_edges":[],"episodes_scanned":[]}' > "$DELTA"
    exit 0
  fi

  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT

  # Load node IDs
  jq -r '.nodes[].id' "$GRAPH" > "$WORK/node_ids.txt"

  # Load all existing edges for reinforcement matching
  jq -r '.edges[] | "\(.source)\t\(.target)\t\(.type)\t\(.id)\t\(.confidence)"' "$GRAPH" \
    > "$WORK/existing_edges.tsv"

  # Pre-normalize node IDs
  declare -A NODE_NORM
  declare -A NODE_LEN
  while IFS= read -r nid; do
    n=$(normalize "$nid")
    NODE_NORM["$nid"]="$n"
    NODE_LEN["$nid"]=${#n}
  done < "$WORK/node_ids.txt"
  mapfile -t NODE_IDS < "$WORK/node_ids.txt"
  NODE_COUNT=${#NODE_IDS[@]}

  echo "Scanning ${#SCAN_FILES[@]} episodes against $NODE_COUNT nodes..."

  # Scan episodes for co-occurrences
  SCANNED_EPISODES=()

  for f in "${SCAN_FILES[@]}"; do
    SESSION=$(basename "$f" .json)
    SCANNED_EPISODES+=("$SESSION")
    EP_DATE=$(jq -r '.created // "" | .[0:10]' "$f")

    while IFS= read -r -d '' CONTENT; do
      if (( ${#CONTENT} < 10 )); then continue; fi
      NORM_CONTENT=$(normalize "$CONTENT")

      FOUND_NODES=()
      for nid in "${NODE_IDS[@]}"; do
        NORM_NID="${NODE_NORM[$nid]}"
        NID_LEN="${NODE_LEN[$nid]}"
        if (( NID_LEN < 5 )); then
          if [[ "$NORM_CONTENT" =~ (^|[-[:space:]])${NORM_NID}([-[:space:]]|$) ]]; then
            FOUND_NODES+=("$nid")
          fi
        else
          if [[ "$NORM_CONTENT" == *"$NORM_NID"* ]]; then
            FOUND_NODES+=("$nid")
          fi
        fi
      done

      NFOUND=${#FOUND_NODES[@]}
      if (( NFOUND >= 2 )); then
        for (( i=0; i<NFOUND; i++ )); do
          for (( j=i+1; j<NFOUND; j++ )); do
            A="${FOUND_NODES[$i]}"
            B="${FOUND_NODES[$j]}"
            if [[ "$A" > "$B" ]]; then TMP="$A"; A="$B"; B="$TMP"; fi
            printf '%s\t%s\t%s\t%s\n' "$A" "$B" "$SESSION" "$EP_DATE"
          done
        done
      fi
    done < <(jq -j '.records[] | (.content // "") + "\u0000"' "$f")
  done > "$WORK/cooccurrences.tsv"

  if [[ ! -s "$WORK/cooccurrences.tsv" ]]; then
    echo "No co-occurrences found"
    SCANNED_JSON=$(printf '%s\n' "${SCANNED_EPISODES[@]}" | jq -R . | jq -s .)
    jq -nc --arg created "$(date -Iseconds)" --argjson scanned "$SCANNED_JSON" \
      '{created: $created, new_edges: [], reinforced_edges: [], episodes_scanned: $scanned}' > "$DELTA"
    echo "Delta written (empty)"
    exit 0
  fi

  # Deduplicate: same pair in same episode counts once
  sort -u -t$'\t' -k1,3 "$WORK/cooccurrences.tsv" > "$WORK/cooccurrences_dedup.tsv"

  # Aggregate per pair
  awk -F'\t' '{
    pair = $1 "\t" $2
    count[pair]++
    if (!(pair in earliest) || $4 < earliest[pair]) earliest[pair] = $4
    if (!(pair in latest) || $4 > latest[pair]) latest[pair] = $4
    if (pair in episodes) episodes[pair] = episodes[pair] "," $3
    else episodes[pair] = $3
  }
  END {
    for (pair in count) {
      print count[pair] "\t" pair "\t" earliest[pair] "\t" latest[pair] "\t" episodes[pair]
    }
  }' "$WORK/cooccurrences_dedup.tsv" | sort -t$'\t' -k1 -rn > "$WORK/candidates.tsv"

  # Classify: new edge vs reinforce existing
  > "$WORK/new_edges.jsonl"
  > "$WORK/reinforced_edges.jsonl"

  MAX_ID=$(jq '[.edges[].id | select(startswith("e-")) | ltrimstr("e-") | select(test("^[0-9]+$")) | tonumber] | max // 0' "$GRAPH")
  NEXT_ID=$((MAX_ID + 1))
  new_count=0
  reinf_count=0

  while IFS=$'\t' read -r cnt nodeA nodeB earliest latest episodes; do
    EP_JSON=$(echo "$episodes" | tr ',' '\n' | sort -u | jq -R . | jq -s .)
    EP_COUNT=$(echo "$EP_JSON" | jq 'length')

    # Find ALL existing edges between this pair (any direction, any type)
    FOUND_EXISTING=false
    while IFS=$'\t' read -r src tgt etype eid econf; do
      if { [[ "$src" == "$nodeA" ]] && [[ "$tgt" == "$nodeB" ]]; } || \
         { [[ "$src" == "$nodeB" ]] && [[ "$tgt" == "$nodeA" ]]; }; then
        FOUND_EXISTING=true
        NEW_CONF=$(awk "BEGIN {c = $econf + $EP_COUNT * 0.05; if (c > 1.0) c = 1.0; printf \"%.2f\", c}")
        jq -nc \
          --arg id "$eid" \
          --arg last "$latest" \
          --arg conf "$NEW_CONF" \
          --argjson eps "$EP_JSON" \
          '{id: $id, confidence: ($conf|tonumber), last_seen: $last, add_episodes: $eps}' \
          >> "$WORK/reinforced_edges.jsonl"
        ((reinf_count++)) || true
      fi
    done < "$WORK/existing_edges.tsv"

    if [[ "$FOUND_EXISTING" == "false" ]]; then
      # No edge of any type — create new relates_to
      CONF=$(awk "BEGIN {c = 0.5 + ($EP_COUNT - 1) * 0.05; if (c > 1.0) c = 1.0; printf \"%.2f\", c}")
      jq -nc \
        --arg id "e-${NEXT_ID}" \
        --arg source "$nodeA" \
        --arg target "$nodeB" \
        --arg fact "Co-occurred in ${cnt} episodes" \
        --arg first "$earliest" \
        --arg last "$latest" \
        --arg conf "$CONF" \
        --argjson eps "$EP_JSON" \
        '{id: $id, source: $source, target: $target, type: "relates_to",
          fact: $fact, confidence: ($conf|tonumber),
          first_seen: $first, last_seen: $last, source_episodes: $eps}' \
        >> "$WORK/new_edges.jsonl"
      NEXT_ID=$((NEXT_ID + 1))
      ((new_count++)) || true
    fi
  done < "$WORK/candidates.tsv"

  # Build delta JSON
  NEW_EDGES=$(cat "$WORK/new_edges.jsonl" | jq -s '.' 2>/dev/null || echo '[]')
  REINFORCED=$(cat "$WORK/reinforced_edges.jsonl" | jq -s '.' 2>/dev/null || echo '[]')
  SCANNED_JSON=$(printf '%s\n' "${SCANNED_EPISODES[@]}" | jq -R . | jq -s .)

  jq -nc \
    --arg created "$(date -Iseconds)" \
    --argjson new_edges "$NEW_EDGES" \
    --argjson reinforced "$REINFORCED" \
    --argjson scanned "$SCANNED_JSON" \
    '{created: $created, new_edges: $new_edges, reinforced_edges: $reinforced, episodes_scanned: $scanned}' \
    > "$DELTA"

  echo "Scan complete: $new_count new, $reinf_count reinforced"
  echo "Delta written to $DELTA"
fi

# ── Phase 3: Apply ───────────────────────────────────────────────────────────
if [[ "$APPLY" == "true" ]]; then
  [[ -f "$DELTA" ]] || { echo "No delta to apply"; exit 0; }
  [[ -f "$GRAPH" ]] || { echo "ERROR: graph not found" >&2; exit 1; }

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "(dry run — delta contents:)"
    jq '{new: (.new_edges | length), reinforced: (.reinforced_edges | length), scanned: (.episodes_scanned | length)}' "$DELTA"
    exit 0
  fi

  # Apply new edges
  NEW_COUNT=$(jq '.new_edges | length' "$DELTA")
  if (( NEW_COUNT > 0 )); then
    jq --slurpfile delta "$DELTA" '.edges += $delta[0].new_edges' "$GRAPH" > "${GRAPH}.tmp" \
      && mv "${GRAPH}.tmp" "$GRAPH"
  fi

  # Apply reinforcements (batched — single jq call)
  REINF_COUNT=$(jq '.reinforced_edges | length' "$DELTA")
  if (( REINF_COUNT > 0 )); then
    jq --slurpfile delta "$DELTA" '
      .edges |= [.[] | . as $e |
        ($delta[0].reinforced_edges | map(select(.id == $e.id)) | first) as $u |
        if $u then
          .confidence = $u.confidence |
          .last_seen = $u.last_seen |
          .source_episodes = ((.source_episodes // []) + $u.add_episodes | unique)
        else . end
      ]' "$GRAPH" > "${GRAPH}.tmp" && mv "${GRAPH}.tmp" "$GRAPH"
  fi

  # Move scanned episodes to archived
  mkdir -p "$ARCHIVED_DIR"
  moved=0
  shopt -s nullglob
  for f in "$TO_SCAN_DIR"/episode_*.json; do
    mv "$f" "$ARCHIVED_DIR/"
    ((moved++)) || true
  done
  shopt -u nullglob

  # Delete delta
  rm -f "$DELTA"

  echo "Applied: $NEW_COUNT new edges, $REINF_COUNT reinforced, $moved episodes archived, delta deleted"
fi
