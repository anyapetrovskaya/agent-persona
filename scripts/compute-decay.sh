#!/usr/bin/env bash
# compute-decay.sh — compute retention scores for graceful forgetting (Phase 2).
# Annotates each non-pinned knowledge item with a retention_score.
#
# retention_score = strength × access_recency × emotional_shield × reinforcement_recency × graph_connectivity_shield
#
# Thresholds:  ≥1.5 healthy | 0.5–1.5 fading | <0.5 forgotten | pinned: immune
# Grace period: GRACE_DAYS (default 7) — items within this window get no decay penalty.
#
# Usage:
#   bash agent-persona/scripts/compute-decay.sh              # compute + write
#   bash agent-persona/scripts/compute-decay.sh --dry-run     # report only
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
KNOWLEDGE="$BASE/data/knowledge/knowledge.json"

DRY_RUN=false
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

GRACE_DAYS=7

[[ -f "$KNOWLEDGE" ]] || { echo "ERROR: knowledge.json not found" >&2; exit 1; }

NOW_EPOCH=$(date +%s)

# --- Build graph degree map (node_id → total edge count) ---
GRAPH="$BASE/data/knowledge/memory_graph.json"
DEGREE_MAP='{}'
if [[ -f "$GRAPH" ]]; then
  DEGREE_MAP=$(jq '
    .edges | reduce .[] as $e ({};
      .[$e.source] = ((.[$e.source] // 0) + 1) |
      .[$e.target] = ((.[$e.target] // 0) + 1)
    )
  ' "$GRAPH")
fi

# --- Core computation in jq ---
RESULT=$(jq --argjson now "$NOW_EPOCH" --argjson degree_map "$DEGREE_MAP" --argjson grace_days "$GRACE_DAYS" '
  def date_to_epoch:
    try (. + "T00:00:00Z" | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime)
    catch null;

  def iso_to_epoch:
    if . == null then null
    else (.[0:10] | date_to_epoch)
    end;

  # Extract YYYY-MM-DD dates from source string, return max epoch
  def latest_source_epoch:
    if . == null then null
    else
      [scan("[0-9]{4}-[0-9]{2}-[0-9]{2}") | date_to_epoch | select(. != null)]
      | if length > 0 then max else null end
    end;

  def days_since(epoch):
    if epoch == null then null
    else (($now - epoch) / 86400 | if . < 0 then 0 else . end | floor)
    end;

  def round3: . * 1000 | round / 1000;

  # graph_connectivity_shield: min(1 + degree/10, 2.0), default 1.0 if no match
  def compute_graph_shield:
    (.content | ascii_downcase | gsub("[_ .]+"; "-")) as $clower |
    [$degree_map | to_entries[] | (.key | gsub("[_ .]+"; "-")) as $k | select($clower | contains($k))] |
    if length == 0 then 1.0
    else [.[] | .value] | max | (1.0 + . / 10.0) | if . > 2.0 then 2.0 else . end
    end | round3;

  def compute_retention:
    (.strength // 1) as $str |

    # access_recency_factor: null → use created/source date (within grace = 1.0), else linear decay over 120 days with grace period (floor 0.3)
    (if .last_accessed == null then
       # For never-accessed items, use created date or source date as proxy
       (if .created != null then (.created | date_to_epoch)
        else (.source | latest_source_epoch)
        end) as $proxy |
       if $proxy == null then 1.0  # unknown date → assume new (safer than ancient)
       else days_since($proxy) as $d | [($d - $grace_days), 0] | max as $effective | [0.3, (1.0 - ($effective / 120))] | max
       end
     else
       (.last_accessed | iso_to_epoch) as $e |
       if $e == null then 1.0  # unknown date → assume new (safer than ancient)
       else days_since($e) as $d | [($d - $grace_days), 0] | max as $effective | [0.3, (1.0 - ($effective / 120))] | max
       end
     end) as $arf |

    # emotional_shield: null → 1.0, else 1.0 + |emotional_value| × 0.5
    (if .emotional_value == null then 1.0
     else 1.0 + ((.emotional_value | fabs) * 0.5)
     end) as $es |

    # reinforcement_recency_factor: from last_seen or latest source date
    # linear decay over 180 days with grace period (floor 0.3), null → 1.0 (assume new, safer than ancient)
    (if .last_seen != null then (.last_seen | iso_to_epoch)
     else if .source != null then (.source | latest_source_epoch)
     else if .created != null then (.created | date_to_epoch)
     else null
     end end end) as $lse |
    (if $lse == null then 1.0
     else days_since($lse) as $d | [($d - $grace_days), 0] | max as $effective | [0.3, (1.0 - ($effective / 180))] | max
     end) as $rrf |

    (.graph_shield // 1.0) as $gcs |

    ($str * $arf * $es * $rrf * $gcs | round3);

  .items |= [.[] |
    if .pinned == true then .
    else .graph_shield = compute_graph_shield | .retention_score = compute_retention
    end
  ]
' "$KNOWLEDGE")

# --- Summary ---
SUMMARY=$(echo "$RESULT" | jq '
  def unpinned: select(.pinned != true);
  .items | {
    total: length,
    pinned: [.[] | select(.pinned == true)] | length,
    healthy: [.[] | unpinned | select(.retention_score >= 1.5)] | length,
    fading:  [.[] | unpinned | select(.retention_score >= 0.5 and .retention_score < 1.5)] | length,
    forgotten: [.[] | unpinned | select(.retention_score < 0.5)] | length,
    surfacing: [.[] | unpinned | select(
      .emotional_value != null and
      ((.emotional_value | fabs) >= 1.5) and
      .retention_score < 1.5
    )] | length
  }
')

echo "=== Retention Score Report ==="
echo "$SUMMARY" | jq -r '"Total: \(.total) | Pinned: \(.pinned) | Healthy (≥1.5): \(.healthy) | Fading (0.5–1.5): \(.fading) | Forgotten (<0.5): \(.forgotten) | Surfacing: \(.surfacing)"'

echo ""
echo "--- Healthy (score ≥ 1.5) ---"
echo "$RESULT" | jq -r '
  [.items[] | select(.pinned != true and .retention_score >= 1.5)]
  | sort_by(-.retention_score)
  | .[] | "  [\(.retention_score)] (gs:\(.graph_shield // 1.0)) \(.type): \(.content[0:80])"
'

echo ""
echo "--- Fading (0.5 ≤ score < 1.5) ---"
echo "$RESULT" | jq -r '
  [.items[] | select(.pinned != true and .retention_score >= 0.5 and .retention_score < 1.5)]
  | sort_by(.retention_score)
  | .[] | "  [\(.retention_score)] (gs:\(.graph_shield // 1.0)) \(.type): \(.content[0:80])"
'

echo ""
echo "--- Forgotten (score < 0.5) ---"
echo "$RESULT" | jq -r '
  [.items[] | select(.pinned != true and .retention_score < 0.5)]
  | sort_by(.retention_score)
  | .[] | "  [\(.retention_score)] (gs:\(.graph_shield // 1.0)) \(.type): \(.content[0:80])"
'

# Surfacing section (only if non-empty)
SURF_COUNT=$(echo "$SUMMARY" | jq '.surfacing')
if [[ "$SURF_COUNT" -gt 0 ]]; then
  echo ""
  echo "--- Surfacing (high emotional + fading) ---"
  echo "$RESULT" | jq -r '
    [.items[] | select(
      .pinned != true and
      .emotional_value != null and
      ((.emotional_value | fabs) >= 1.5) and
      .retention_score < 1.5
    )] | .[] | "  [\(.retention_score)] (gs:\(.graph_shield // 1.0)) \(.type): \(.content[0:80])"
  '
fi

# --- Surface queue (top fading candidates for user review) ---
SURFACE_QUEUE="$BASE/data/knowledge/surface_queue.json"
TODAY=$(date +%Y-%m-%d)
echo "$RESULT" | jq --arg generated "$TODAY" --argjson now "$NOW_EPOCH" --argjson grace_days "$GRACE_DAYS" '
  {
    generated: $generated,
    candidates: (
      .items
      | to_entries
      | map(select(.value.pinned != true and (.value.retention_score != null) and (.value.retention_score < 1.0) and (
          # Exclude items within grace period
          (if .value.created != null then
            ((.value.created + "T00:00:00Z" | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) // 0)
          else if .value.source != null then
            ([.value.source | scan("[0-9]{4}-[0-9]{2}-[0-9]{2}") | (. + "T00:00:00Z" | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) // null | select(. != null)] | if length > 0 then max else 0 end)
          else 0
          end end) as $item_epoch |
          (($now - $item_epoch) / 86400) > $grace_days
        )))
      | map({
          index: .key,
          retention_score: .value.retention_score,
          type: .value.type,
          content_preview: ((.value.content // "")[0:80]),
          emotional_value: .value.emotional_value,
          access_count: .value.access_count,
          last_accessed: .value.last_accessed
        })
      | sort_by(.retention_score)
      | .[0:10]
    )
  }
' > "${SURFACE_QUEUE}.tmp" && mv "${SURFACE_QUEUE}.tmp" "$SURFACE_QUEUE"

# --- Write or dry-run ---
if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "(dry run — no changes written)"
else
  echo "$RESULT" | jq '.items |= [.[] | del(.graph_shield)]' > "${KNOWLEDGE}.tmp" && mv "${KNOWLEDGE}.tmp" "$KNOWLEDGE"
  echo ""
  echo "Scores written to knowledge.json."
fi
