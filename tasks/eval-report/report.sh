#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR/../../data"

# --- Parse arguments ---
DEBUG=false
PERIOD="all"

for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=true ;;
    --period=*) PERIOD="${arg#--period=}" ;;
  esac
done

KNOWLEDGE="$BASE/knowledge/knowledge.json"
GRAPH="$BASE/knowledge/memory_graph.json"
EVAL_LOG="$BASE/eval/eval_log.json"
EPISODIC_DIR="$BASE/episodic"
BASELINE="$BASE/eval/baseline.json"

TODAY=$(date +%Y-%m-%d)

# --- Load and filter eval events ---
if [[ -f "$EVAL_LOG" ]]; then
  case "$PERIOD" in
    all)
      EVENTS=$(jq '.events' "$EVAL_LOG")
      ;;
    last_*)
      N="${PERIOD#last_}"
      EVENTS=$(jq --argjson n "$N" '
        .events as $all |
        [$all[] | select(.type == "session_summary")] |
        group_by(.session) |
        map({session: .[0].session, latest: ([.[].ts] | sort | last)}) |
        sort_by(.latest) | .[-$n:] |
        map(.latest[:10]) as $dates |
        ($dates | sort | first // "") as $start |
        [$all[] | select(.ts[:10] >= $start)]
      ' "$EVAL_LOG")
      ;;
    *..*)
      START="${PERIOD%..*}"
      END="${PERIOD#*..}"
      EVENTS=$(jq --arg s "$START" --arg e "$END" '
        [.events[] | select(.ts[:10] >= $s and .ts[:10] <= $e)]
      ' "$EVAL_LOG")
      ;;
    *)
      echo "error: unknown period format '$PERIOD'" >&2
      echo "usage: --period=all | --period=last_N | --period=YYYY-MM-DD..YYYY-MM-DD" >&2
      exit 1
      ;;
  esac
else
  EVENTS='[]'
fi

HAS_EVENTS=$(echo "$EVENTS" | jq 'length > 0')

# ===== REPORT OUTPUT =====
echo "# Eval Report — $TODAY"
echo ""

# --- Retrieval metrics ---
retrieval_json=$(echo "$EVENTS" | jq '
  [.[] | select(.type == "retrieval")] |
  if length == 0 then {count: 0}
  else {
    count: length,
    avg_items: ([.[].data.total_items | tonumber] | add / length * 100 | round / 100),
    avg_knowledge: ([.[].data.knowledge_matches | tonumber] | add / length * 100 | round / 100),
    avg_episodes: ([.[].data.episode_matches | tonumber] | add / length * 100 | round / 100),
    graph_enhanced: ([.[] | select(.data.mode == "graph-enhanced")] | length),
    flat: ([.[] | select(.data.mode == "flat")] | length),
    avg_graph_paths: (
      [.[] | select(.data.mode == "graph-enhanced") | .data.graph_paths | tonumber] |
      if length > 0 then (add / length * 100 | round / 100) else 0 end
    )
  } end
')

r_count=$(echo "$retrieval_json" | jq '.count')
echo "## Retrieval ($r_count queries logged)"
if (( r_count == 0 )); then
  echo "No data yet."
else
  echo "$retrieval_json" | jq -r '
    "- Avg items/query: \(.avg_items)",
    "- Knowledge matches avg: \(.avg_knowledge) | Episode matches avg: \(.avg_episodes)",
    "- Mode split: \(.graph_enhanced) graph-enhanced, \(.flat) flat",
    "- Avg graph paths: \(.avg_graph_paths)"
  '
fi
echo ""

# --- Handoff metrics ---
handoff_json=$(echo "$EVENTS" | jq '
  [.[] | select(.type == "handoff_check")] |
  if length == 0 then {count: 0}
  else
    length as $total |
    ([.[] | select(.data.handoff_existed == true)] | length) as $existed |
    ([.[] | select(.data.handoff_existed == true and .data.self_assessed_useful == true)] | length) as $useful |
    {
      count: $total,
      pct_existed: ($existed / $total * 10000 | round / 100),
      pct_useful: (if $existed > 0 then ($useful / $existed * 10000 | round / 100) else 0 end)
    }
  end
')

h_count=$(echo "$handoff_json" | jq '.count')
echo "## Handoff Continuity ($h_count sessions)"
if (( h_count == 0 )); then
  echo "No data yet."
else
  echo "$handoff_json" | jq -r '
    "- Handoff existed: \(.pct_existed)%",
    "- Self-assessed useful: \(.pct_useful)% (of sessions with handoff)"
  '
fi
echo ""

# --- Correction metrics ---
# Use latest session_summary per unique session to avoid double-counting
correction_json=$(echo "$EVENTS" | jq '
  [.[] | select(.type == "session_summary")] |
  if length == 0 then {count: 0, sessions: 0}
  else
    group_by(.session) |
    map(sort_by(.ts) | last | {session: .session, corrections: (.data.corrections | tonumber)}) |
    sort_by(.session) |
    . as $sessions |
    {
      sessions: length,
      total_corrections: ([.[].corrections] | add // 0),
      avg_per_session: ([.[].corrections] | add / length * 100 | round / 100),
      trend: (
        if length < 4 then "insufficient data"
        else
          (length / 2 | floor) as $half |
          (.[:$half] | [.[].corrections] | add / length) as $first_avg |
          (.[$half:] | [.[].corrections] | add / length) as $second_avg |
          if $first_avg == 0 and $second_avg == 0 then "stable"
          elif $first_avg == 0 then "worsening"
          elif (($second_avg - $first_avg) / $first_avg | fabs) < 0.2 then "stable"
          elif $second_avg < $first_avg then "improving"
          else "worsening"
          end
        end
      )
    }
  end
')

c_sessions=$(echo "$correction_json" | jq '.sessions // 0')
echo "## Corrections ($c_sessions sessions)"
if (( c_sessions == 0 )); then
  echo "No data yet."
else
  echo "$correction_json" | jq -r '
    "- Total corrections: \(.total_corrections)",
    "- Avg per session: \(.avg_per_session)",
    "- Trend: \(.trend)"
  '
fi
echo ""

# --- Knowledge store metrics ---
echo "## Knowledge Store"
if [[ -f "$KNOWLEDGE" ]]; then
  jq -r '
    (.items | length) as $total |
    ({"preference":0,"convention":0,"fact":0,"rule":0,"trait":0} as $init |
      reduce .items[] as $i ($init; .[$i.type] += 1)) as $by_type |
    (if $total > 0 then ([.items[].strength] | add / length * 100 | round / 100) else 0 end) as $avg |
    ([.items[] | select(.strength > 1)] | length) as $reinforced |
    ({"user":0,"project":0,"global":0} as $init |
      reduce .items[] as $i ($init; .[$i.scope] += 1)) as $by_scope |
    "- Total items: \($total) (preference: \($by_type.preference), convention: \($by_type.convention), fact: \($by_type.fact), rule: \($by_type.rule), trait: \($by_type.trait))",
    "- Avg strength: \($avg) | Reinforced (strength > 1): \($reinforced)",
    "- Scope: user: \($by_scope.user), project: \($by_scope.project), global: \($by_scope.global)"
  ' "$KNOWLEDGE"
else
  echo "No data yet."
fi
echo ""

# --- Graph metrics ---
echo "## Memory Graph"
if [[ -f "$GRAPH" ]]; then
  jq -r '
    (.nodes | length) as $n |
    (.edges | length) as $e |
    (if $n > 0 then ($e / $n * 100 | round / 100) else 0 end) as $avg |
    "- Nodes: \($n) | Edges: \($e) | Avg connectivity: \($avg)",
    (
      .nodes as $nodes |
      [.edges[] | .source, .target] |
      group_by(.) |
      map({id: .[0], edge_count: length}) |
      sort_by(-.edge_count) | .[:5] |
      map(
        .id as $id |
        ($nodes[] | select(.id == $id) | .name // $id) as $name |
        "\($name) (\(.edge_count))"
      ) | join(", ")
    ) as $top |
    "- Top nodes: \($top)"
  ' "$GRAPH"
else
  echo "No data yet."
fi
echo ""

# --- Baseline comparison ---
if [[ -f "$BASELINE" ]]; then
  echo "## vs Baseline"

  # Gather current values
  k_total=0; k_avg=0; k_reinforced=0
  if [[ -f "$KNOWLEDGE" ]]; then
    k_total=$(jq '.items | length' "$KNOWLEDGE")
    k_avg=$(jq 'if (.items | length) > 0 then ([.items[].strength] | add / length * 100 | round / 100) else 0 end' "$KNOWLEDGE")
    k_reinforced=$(jq '[.items[] | select(.strength > 1)] | length' "$KNOWLEDGE")
  fi

  e_total=0; e_records=0; e_corrections=0
  shopt -s nullglob
  ep_files=("$EPISODIC_DIR"/*.json "$EPISODIC_DIR"/archived/*.json)
  shopt -u nullglob
  e_total=${#ep_files[@]}
  if (( e_total > 0 )); then
    e_stats=$(jq -s '{
      records: ([.[].records | length] | add // 0),
      corrections: ([.[].records[]? | select(.type == "correction")] | length)
    }' "${ep_files[@]}")
    e_records=$(echo "$e_stats" | jq '.records')
    e_corrections=$(echo "$e_stats" | jq '.corrections')
  fi

  g_nodes=0; g_edges=0
  if [[ -f "$GRAPH" ]]; then
    g_nodes=$(jq '.nodes | length' "$GRAPH")
    g_edges=$(jq '.edges | length' "$GRAPH")
  fi

  el_count=0
  if [[ -f "$EVAL_LOG" ]]; then
    el_count=$(jq '.events | length' "$EVAL_LOG")
  fi

  # Format deltas
  format_delta() {
    local label="$1" current="$2" baseline="$3"
    local delta
    delta=$(jq -rn --argjson c "$current" --argjson b "$baseline" '
      ($c - $b) as $d |
      if $d > 0 then "+\($d)" elif $d < 0 then "\($d)" else "0" end
    ')
    echo "- $label: $current (baseline: $baseline, delta: $delta)"
  }

  format_delta "Knowledge items" "$k_total" "$(jq '.knowledge.total_items' "$BASELINE")"
  format_delta "Avg strength" "$k_avg" "$(jq '.knowledge.avg_strength' "$BASELINE")"
  format_delta "Reinforced" "$k_reinforced" "$(jq '.knowledge.reinforced_count' "$BASELINE")"
  format_delta "Episodes" "$e_total" "$(jq '.episodic.total_episodes' "$BASELINE")"
  format_delta "Episode records" "$e_records" "$(jq '.episodic.total_records' "$BASELINE")"
  format_delta "Corrections" "$e_corrections" "$(jq '.episodic.correction_count' "$BASELINE")"
  format_delta "Graph nodes" "$g_nodes" "$(jq '.graph.node_count' "$BASELINE")"
  format_delta "Graph edges" "$g_edges" "$(jq '.graph.edge_count' "$BASELINE")"
  format_delta "Eval events" "$el_count" "$(jq '.eval_log.event_count' "$BASELINE")"
  echo ""
fi

if $DEBUG; then
  echo "tool_calls: 0"
fi
