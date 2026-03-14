#!/usr/bin/env bash
# scan-archived-reinforcements.sh — boost knowledge strength from to-scan episodes.
# Pure bash/jq — no LLM tokens needed.
#
# For each knowledge item, extracts up to 5 key terms and counts how many
# archived episodes have ≥2 terms co-occurring (majority match). Episodes
# already in the item's source field are skipped. Boosts strength by +1 per
# 3 distinct new matches (cap boost at +5, cap total strength at 10).
#
# Usage:
#   bash agent-persona/scripts/scan-archived-reinforcements.sh              # scan + write
#   bash agent-persona/scripts/scan-archived-reinforcements.sh --dry-run    # report only
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
KNOWLEDGE="$BASE/data/knowledge/knowledge.json"
TO_SCAN_DIR="$BASE/data/episodic/to_scan"

DRY_RUN=false
for arg in "$@"; do [[ "$arg" == "--dry-run" ]] && DRY_RUN=true; done

[[ -f "$KNOWLEDGE" ]] || { echo "ERROR: knowledge.json not found" >&2; exit 1; }
[[ -d "$TO_SCAN_DIR" ]] || { echo "No to_scan episodes directory"; exit 0; }

shopt -s nullglob
EPISODE_FILES=("$TO_SCAN_DIR"/episode_*.json)
shopt -u nullglob
(( ${#EPISODE_FILES[@]} )) || { echo "No episodes in to_scan/"; exit 0; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ── Step 1: Build per-episode lowercase text blobs ──────────────────────────
for f in "${EPISODE_FILES[@]}"; do
  SESSION=$(basename "$f" .json)
  jq -r '[.records[].content // empty] | join("\n")' "$f" \
    | tr '[:upper:]' '[:lower:]' > "$WORK/$SESSION.txt"
done

EP_COUNT=${#EPISODE_FILES[@]}

# ── Step 2: Pre-extract knowledge items (single jq pass) ───────────────────
jq -c '.items[] | {content, source: (.source // ""), strength: (.strength // 1)}' \
  "$KNOWLEDGE" > "$WORK/items.jsonl"
ITEM_COUNT=$(wc -l < "$WORK/items.jsonl")

# 5+ char words that appear too broadly across episodes to be discriminating
STOPS="about|after|agent|along|always|based|being|could|every|field|first|items|model|never|other|scope|short|since|source|state|still|store|their|these|those|three|under|using|value|where|which|while|would|should|content|default|episode|episodic|existing|memory|knowledge|project|records|session|strength|updated|persona|within|without|through|across|before|between|during|another|because|either|enough|except|having|itself|rather|towards|single|format|include|report|added|notes|files|start|entry|point|system|write|reads|makes|build|check"

# ── Step 3: Find reinforcements per item ────────────────────────────────────
> "$WORK/boosts.jsonl"
BOOSTED=0
TOTAL_BOOST=0
IDX=0

while IFS= read -r item_json; do
  CONTENT=$(echo "$item_json" | jq -r '.content')
  SOURCES=$(echo "$item_json" | jq -r '.source')
  CUR_STR=$(echo "$item_json" | jq -r '.strength')

  TERMS=$(echo "$CONTENT" | tr '[:upper:]' '[:lower:]' \
    | grep -oE '\b[a-z]{5,}\b' \
    | grep -vwE "$STOPS" \
    | sort -u | awk '{print length, $0}' | sort -rn | head -5 | awk '{print $2}')

  if [[ -z "$TERMS" ]]; then
    IDX=$((IDX + 1)); continue
  fi

  TERM_ARRAY=()
  while IFS= read -r t; do
    [[ -n "$t" ]] && TERM_ARRAY+=("$t")
  done <<< "$TERMS"
  TOTAL_TERMS=${#TERM_ARRAY[@]}
  MIN_MATCH=$(( TOTAL_TERMS > 1 ? 2 : 1 ))

  # Phase 1: quick OR filter for candidate episodes
  PATTERN=$(echo "$TERMS" | paste -sd'|')
  CANDIDATES=$(grep -rlwE "$PATTERN" "$WORK"/episode_*.txt 2>/dev/null || true)

  if [[ -z "$CANDIDATES" ]]; then
    IDX=$((IDX + 1)); continue
  fi

  # Phase 2: verify ≥MIN_MATCH terms co-occur per episode
  NEW_EPS=""
  MATCH_COUNT=0
  while IFS= read -r txt; do
    [[ -z "$txt" ]] && continue
    SESSION=$(basename "$txt" .txt)
    echo "$SOURCES" | grep -qF "$SESSION" && continue
    HITS=0
    for term in "${TERM_ARRAY[@]}"; do
      grep -qw "$term" "$txt" && HITS=$((HITS + 1))
    done
    if (( HITS >= MIN_MATCH )); then
      MATCH_COUNT=$((MATCH_COUNT + 1))
      [[ -n "$NEW_EPS" ]] && NEW_EPS="$NEW_EPS, $SESSION" || NEW_EPS="$SESSION"
    fi
  done <<< "$CANDIDATES"

  BOOST=$((MATCH_COUNT / 3))
  (( BOOST > 5 )) && BOOST=5
  if (( BOOST > 0 )); then
    NEW_STR=$((CUR_STR + BOOST))
    if (( NEW_STR > 10 )); then
      NEW_STR=10
      BOOST=$((NEW_STR - CUR_STR))
    fi
  fi
  if (( BOOST > 0 )); then
    BOOSTED=$((BOOSTED + 1))
    TOTAL_BOOST=$((TOTAL_BOOST + BOOST))
    jq -nc --argjson idx "$IDX" --argjson boost "$BOOST" \
      --argjson str "$NEW_STR" --arg eps "$NEW_EPS" --argjson mc "$MATCH_COUNT" \
      '{index:$idx,boost:$boost,new_strength:$str,new_episodes:$eps,match_count:$mc}' \
      >> "$WORK/boosts.jsonl"
  fi

  IDX=$((IDX + 1))
done < "$WORK/items.jsonl"

# ── Step 4: Report ──────────────────────────────────────────────────────────
echo "=== Archived Reinforcement Scan ==="
echo "Scanned: $EP_COUNT to_scan episodes, $ITEM_COUNT knowledge items"

if [[ ! -s "$WORK/boosts.jsonl" ]]; then
  echo "Result: No new reinforcements found"
  exit 0
fi

echo "Boosted: $BOOSTED items (total +$TOTAL_BOOST strength)"
echo ""
echo "--- Details ---"
while IFS= read -r line; do
  B_IDX=$(echo "$line" | jq -r '.index')
  B_BOOST=$(echo "$line" | jq -r '.boost')
  B_STR=$(echo "$line" | jq -r '.new_strength')
  B_MC=$(echo "$line" | jq -r '.match_count')
  B_CONTENT=$(jq -r ".items[$B_IDX].content[0:80]" "$KNOWLEDGE")
  echo "  [str $B_STR <- +$B_BOOST from $B_MC eps] $B_CONTENT"
done < "$WORK/boosts.jsonl"

# ── Step 5: Apply boosts (single jq pass) ──────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "(dry run — no changes written)"
else
  BOOSTS=$(jq -s '.' "$WORK/boosts.jsonl")
  jq --argjson boosts "$BOOSTS" '
    reduce ($boosts[]) as $b (.;
      .items[$b.index].strength = $b.new_strength |
      .items[$b.index].source = ((.items[$b.index].source // "") + ", " + $b.new_episodes)
    )
  ' "$KNOWLEDGE" > "${KNOWLEDGE}.tmp" && mv "${KNOWLEDGE}.tmp" "$KNOWLEDGE"
  echo ""
  echo "Changes written to knowledge.json."
fi
