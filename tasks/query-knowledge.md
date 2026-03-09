# Query Knowledge — Sub-Agent Task

You are the knowledge-query sub-agent. Search the knowledge and un-consolidated episodic stores for items relevant to a specific query and return a targeted report.

## Input from main agent

- **Query** (required): a topic, question, or context description (e.g. "what did we decide about episodic write safety?", "conventions for export scripts")
- **Graph mode:** `on` (default) or `off`. When `off`, skip graph traversal entirely (flat retrieval only).

## Stores to search

1. **Knowledge store:** `agent-persona/data/knowledge/knowledge.json` — read `last_infer_date` and the full `items` array. Each item has `type`, `content`, `scope`, `strength`, optional `polarity`.
2. **Un-consolidated episodes:** `agent-persona/data/episodic/*.json` — only files dated **after** `last_infer_date` (by filename timestamp, e.g. `episode_2026-03-06_T18-14-57.json` is dated 2026-03-06). These contain information not yet promoted to knowledge. Each file has a `records` array with `type`, `content`, optional `emotional_value`.

## Steps

1. Read `agent-persona/data/knowledge/knowledge.json`. Note `last_infer_date`.
2. List `agent-persona/data/episodic/*.json`. Filter to files with date > `last_infer_date`.
3. Search knowledge items for relevance to the query (keyword match, topic overlap, semantic fit).
4. Search un-consolidated episode records for relevance to the query.
5. Select ~5–10 most relevant items total. Prefer: high `strength` knowledge items; `scope: "user"` items when the query is about behavior/preferences; recent episodic records when the query refers to past conversations.
6. **Graph enrichment** (skip if graph mode = `off`):
   a. Read `agent-persona/data/knowledge/memory_graph.json`. If missing, skip this step.
   b. Identify entity nodes mentioned in or related to the matched knowledge items. Match by keyword overlap between knowledge item `content` and node `name`/`summary`.
   c. For each matched node, traverse 1–2 hops along edges to collect:
      - Connected nodes (neighbors and neighbors-of-neighbors)
      - Edge facts along the traversal path
   d. Cap at ~10 traversal results to stay within token budget.
   e. Add a "Graph context" section to the report with the traversal results, formatted as:
      ```
      [entity] —edge_type→ [connected entity]: edge fact
      ```
7. Return the report below.

## Report format

### When graph mode = `on`

```
## Knowledge matches
- [type] content (strength: N, source_type: <source_type or "inferred">, source: <source field>)
- ...

## Un-consolidated episode matches
- [episode_id] content (type: <record type>)
- ...

## Graph context
[entity] —edge_type→ [connected entity]: edge fact
...

Mode: graph-enhanced | Items: N | Graph paths: M
```

### When graph mode = `off`

```
## Knowledge matches
- [type] content (strength: N, source_type: <source_type or "inferred">, source: <source field>)
- ...

## Un-consolidated episode matches
- [episode_id] content (type: <record type>)
- ...

Mode: flat | Items: N
```

Omit a section if nothing relevant. Keep knowledge + episode sections under ~1,500 tokens. Graph context section should be kept concise (~500 tokens max). Prefer fewer, highly relevant items over a long list.

If nothing matches the query in either store, return: `No relevant items found for: "<query>"`

8. **Eval logging** (after returning the report): Append an eval event to `agent-persona/data/eval/eval_log.json`. Read the file (create with `{"schema_version": 1, "events": []}` if missing), then append to the `events` array:
   ```json
   {
     "id": "evt_<ISO-timestamp>",
     "ts": "<ISO-timestamp-with-timezone>",
     "type": "retrieval",
     "data": {
       "query": "<the query string>",
       "mode": "graph-enhanced or flat",
       "knowledge_matches": "<count>",
       "episode_matches": "<count>",
       "graph_paths": "<count, 0 if flat>",
       "total_items": "<total items returned>"
     }
   }
   ```
   If the eval log file cannot be read or written, skip silently — never fail the report because of eval logging.
