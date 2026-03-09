# Eval Report — Sub-Agent Task

You are the eval-report sub-agent. Compute metrics from the eval log and memory data, then return a summary report.

## Input from main agent

- **Period** (optional): `all` (default), `last_N_sessions`, or a date range `YYYY-MM-DD..YYYY-MM-DD`.

## Data sources

1. **Eval log:** `agent-persona/data/eval/eval_log.json` — append-only event log with `schema_version` and `events` array.
2. **Knowledge store:** `agent-persona/data/knowledge/knowledge.json` — `items` array with `type`, `strength`, `source`.
3. **Episodic records:** `agent-persona/data/episodic/*.json` and `agent-persona/data/episodic/archived/*.json` — episode files with `records` arrays.
4. **Memory graph:** `agent-persona/data/knowledge/memory_graph.json` — `nodes` and `edges` arrays.
5. **Baseline:** `agent-persona/data/eval/baseline.json` — baseline snapshot for comparison (if exists).

## Steps

1. Read `agent-persona/data/eval/eval_log.json`. If missing or empty events array, note "No eval events recorded yet" and proceed with data-only metrics.

2. **Retrieval metrics** (from `retrieval` events in eval log):
   - Total queries logged
   - Avg items returned per query (`total_items`)
   - Avg knowledge matches vs episode matches
   - Graph-enhanced vs flat split (count of each mode)
   - Avg graph paths when graph mode used

3. **Handoff metrics** (from `handoff_check` events in eval log):
   - Total sessions checked
   - % where handoff existed
   - % self-assessed as useful (of those where handoff existed)

4. **Correction metrics** (from `session_summary` events in eval log + episodic data):
   - Total corrections logged
   - Avg corrections per session
   - Trend: compare first half vs second half of sessions (if enough data)

5. **Knowledge store metrics** (from knowledge.json):
   - Total items, breakdown by type (preference, convention, fact, rule, trait)
   - Avg strength across items
   - Items with strength > 1 (reinforced knowledge)
   - Scope distribution (user, project, global)

6. **Graph metrics** (from memory_graph.json, if exists):
   - Node count, edge count
   - Avg edges per node (connectivity)
   - Most connected nodes (top 5 by edge count)

7. **Comparison to baseline** (if `agent-persona/data/eval/baseline.json` exists):
   - Delta for each metric vs baseline values
   - Flag improvements and regressions

## Report format

```
# Eval Report — <date>

## Retrieval (N queries logged)
- Avg items/query: N
- Knowledge matches avg: N | Episode matches avg: N
- Mode split: N graph-enhanced, N flat
- Avg graph paths: N

## Handoff Continuity (N sessions)
- Handoff existed: N%
- Self-assessed useful: N% (of sessions with handoff)

## Corrections (N sessions)
- Total corrections: N
- Avg per session: N
- Trend: <improving / stable / worsening / insufficient data>

## Knowledge Store
- Total items: N (preference: N, convention: N, fact: N, rule: N, trait: N)
- Avg strength: N | Reinforced (strength > 1): N
- Scope: user: N, project: N, global: N

## Memory Graph
- Nodes: N | Edges: N | Avg connectivity: N
- Top nodes: <top 5 by edge count>

## vs Baseline
- <metric>: <current> (baseline: <baseline>, delta: <+/-N>)
- ...
```

If a section has no data, include the header with "No data yet."
If no baseline exists, omit the "vs Baseline" section entirely.
