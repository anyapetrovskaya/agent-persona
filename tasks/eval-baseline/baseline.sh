#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$SCRIPT_DIR/../../data"

# --- Parse arguments ---
DEBUG=false
LABEL=""

for arg in "$@"; do
  case "$arg" in
    --debug) DEBUG=true ;;
    --label=*) LABEL="${arg#--label=}" ;;
  esac
done

[[ -z "$LABEL" ]] && LABEL="$(date +%Y-%m-%d)"

KNOWLEDGE="$BASE/knowledge/knowledge.json"
GRAPH="$BASE/knowledge/memory_graph.json"
EVAL_LOG="$BASE/eval/eval_log.json"
EPISODIC_DIR="$BASE/episodic"
BASELINE_OUT="$BASE/eval/baseline.json"
CREATED=$(date -u +%Y-%m-%dT%H:%M:%S+0000)

# --- Knowledge metrics ---
knowledge_json='{"total_items":0,"by_type":{"preference":0,"convention":0,"fact":0,"rule":0,"trait":0},"avg_strength":0,"reinforced_count":0,"by_scope":{"user":0,"project":0,"global":0}}'

if [[ -f "$KNOWLEDGE" ]]; then
  knowledge_json=$(jq '{
    total_items: (.items | length),
    by_type: (
      {"preference":0,"convention":0,"fact":0,"rule":0,"trait":0} as $init |
      reduce .items[] as $i ($init; .[$i.type] += 1)
    ),
    avg_strength: (
      if (.items | length) > 0
      then ([.items[].strength] | add / length * 100 | round / 100)
      else 0 end
    ),
    reinforced_count: ([.items[] | select(.strength > 1)] | length),
    by_scope: (
      {"user":0,"project":0,"global":0} as $init |
      reduce .items[] as $i ($init; .[$i.scope] += 1)
    )
  }' "$KNOWLEDGE")
fi

# --- Episodic metrics ---
shopt -s nullglob
episode_files=("$EPISODIC_DIR"/*.json "$EPISODIC_DIR"/archived/*.json)
shopt -u nullglob

episodic_json='{"total_episodes":0,"total_records":0,"correction_count":0,"corrections_per_episode":0,"date_range":{"earliest":"","latest":""}}'
e_total=${#episode_files[@]}

if (( e_total > 0 )); then
  episodic_json=$(jq -s --argjson total "$e_total" '{
    total_episodes: $total,
    total_records: ([.[].records | length] | add // 0),
    correction_count: ([.[].records[]? | select(.type == "correction")] | length),
    corrections_per_episode: (
      ([.[].records[]? | select(.type == "correction")] | length) as $c |
      if $total > 0 then ($c / $total * 100 | round / 100) else 0 end
    ),
    date_range: {
      earliest: ([.[].created] | sort | first // ""),
      latest: ([.[].created] | sort | last // "")
    }
  }' "${episode_files[@]}")
fi

# --- Graph metrics ---
graph_json='{"node_count":0,"edge_count":0,"avg_connectivity":0}'

if [[ -f "$GRAPH" ]]; then
  graph_json=$(jq '{
    node_count: (.nodes | length),
    edge_count: (.edges | length),
    avg_connectivity: (
      if (.nodes | length) > 0
      then ((.edges | length) / (.nodes | length) * 100 | round / 100)
      else 0 end
    )
  }' "$GRAPH")
fi

# --- Eval log metrics ---
eval_json='{"event_count":0,"by_type":{}}'

if [[ -f "$EVAL_LOG" ]]; then
  eval_json=$(jq '{
    event_count: (.events | length),
    by_type: (reduce .events[] as $e ({}; .[$e.type] += 1))
  }' "$EVAL_LOG")
fi

# --- Write baseline.json ---
mkdir -p "$(dirname "$BASELINE_OUT")"

jq -n \
  --arg label "$LABEL" \
  --arg created "$CREATED" \
  --argjson knowledge "$knowledge_json" \
  --argjson episodic "$episodic_json" \
  --argjson graph "$graph_json" \
  --argjson eval_log "$eval_json" \
  '{
    label: $label,
    created: $created,
    knowledge: $knowledge,
    episodic: $episodic,
    graph: $graph,
    eval_log: $eval_log
  }' > "$BASELINE_OUT"

# --- Summary output ---
echo "Baseline saved: agent-persona/data/eval/baseline.json"
jq -r '
  "Label: \(.label)",
  "Knowledge: \(.knowledge.total_items) items (avg strength: \(.knowledge.avg_strength), reinforced: \(.knowledge.reinforced_count))",
  "Episodes: \(.episodic.total_episodes) total, \(.episodic.total_records) records, \(.episodic.correction_count) corrections (\(.episodic.corrections_per_episode)/episode)",
  "Graph: \(.graph.node_count) nodes, \(.graph.edge_count) edges (avg connectivity: \(.graph.avg_connectivity))",
  "Eval log: \(.eval_log.event_count) events"
' "$BASELINE_OUT"

if $DEBUG; then
  echo "tool_calls: 0"
fi
