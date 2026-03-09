# Eval Baseline — Sub-Agent Task

You are the eval-baseline sub-agent. Compute a baseline snapshot of memory system metrics from existing data and save it for future comparison.

This task is typically run once to establish a "before" snapshot, then again at milestones.

## Input from main agent

- **Label** (optional): a short label for this baseline (e.g. "pre-reflective-self-improvement", "v0.3-memory-graph"). Defaults to the current date.

## Data sources

1. **Knowledge store:** `agent-persona/data/knowledge/knowledge.json`
2. **Episodic records:** `agent-persona/data/episodic/*.json` and `agent-persona/data/episodic/archived/*.json`
3. **Memory graph:** `agent-persona/data/knowledge/memory_graph.json`
4. **Eval log:** `agent-persona/data/eval/eval_log.json` (if any events exist yet)

## Steps

1. **Knowledge metrics:**
   - Total items count
   - Breakdown by type (preference, convention, fact, rule, trait)
   - Avg strength
   - Items with strength > 1
   - Scope distribution (user, project, global)

2. **Episodic metrics:**
   - Total episodes (active + archived)
   - Total records across all episodes
   - Correction count (records with type "correction")
   - Corrections per episode (avg)
   - Date range (earliest to latest episode)

3. **Graph metrics** (if memory_graph.json exists):
   - Node count
   - Edge count
   - Avg edges per node

4. **Eval log metrics** (if eval_log.json exists and has events):
   - Event count by type
   - Include summary stats if available

5. **Write baseline:** Save to `agent-persona/data/eval/baseline.json`:
   ```json
   {
     "label": "<label or date>",
     "created": "<ISO-timestamp>",
     "knowledge": {
       "total_items": 0,
       "by_type": {"preference": 0, "convention": 0, "fact": 0, "rule": 0, "trait": 0},
       "avg_strength": 0,
       "reinforced_count": 0,
       "by_scope": {"user": 0, "project": 0, "global": 0}
     },
     "episodic": {
       "total_episodes": 0,
       "total_records": 0,
       "correction_count": 0,
       "corrections_per_episode": 0,
       "date_range": {"earliest": "", "latest": ""}
     },
     "graph": {
       "node_count": 0,
       "edge_count": 0,
       "avg_connectivity": 0
     },
     "eval_log": {
       "event_count": 0,
       "by_type": {}
     }
   }
   ```

## Report format

```
Baseline saved: agent-persona/data/eval/baseline.json
Label: <label>
Knowledge: N items (avg strength: N, reinforced: N)
Episodes: N total, N records, N corrections (N/episode)
Graph: N nodes, N edges (avg connectivity: N)
Eval log: N events
```
