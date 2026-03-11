# Build Memory Graph — Sub-Agent Task

You are the build-memory-graph sub-agent. Extract entities and relationships from knowledge and episodic memory into a graph.

## Input from main agent

- **Knowledge path:** `agent-persona/data/knowledge/knowledge.json` (just written by infer-knowledge)
- **Episodic path:** `agent-persona/data/episodic/*.json` (un-archived episodes only)
- **Graph path:** `agent-persona/data/knowledge/memory_graph.json` (existing graph to update, or absent for first build)

## Steps

1. **Read inputs.** Load knowledge.json, all un-archived episodic files, and existing memory_graph.json (if present).

2. **Extract entities.** From each knowledge item and episodic record, identify distinct entities — people, components, tools, concepts, preferences, decisions. Assign a stable `id` (kebab-case, e.g. `user-anya`, `system-handoff`). Reuse existing node ids from the graph when the entity matches.

3. **Extract relationships.** For each pair of related entities, create an edge:
   - Causal language ("because", "motivated by", "due to") → `motivated_by`
   - Creation/authorship → `created`
   - Supersession ("replaced", "renamed", "refactored into") → `replaced`
   - Reinforcement ("enables", "supports", "helps") → `supports`
   - Conflict ("contradicts", "conflicts with") → `contradicts`
   - Composition ("part of", "contains", "includes") → `part_of`
   - General association → `relates_to`
   - Use free-form edge types when canonical types don't fit.

4. **Merge with existing graph.** For each extracted node/edge:
   - If node exists (by id): update `last_seen`, merge `summary` if richer, update `properties`.
   - If edge exists (same source + target + type): update `last_seen`, increment `confidence` (cap at 1.0), append new source episodes.
   - New nodes/edges: add with `confidence: 0.5` for edges.
   - Never remove existing nodes or edges — only add or update.

5. **Motivation correction.** When processing episodic records of type `correction`, check if the correction content references a motivation or cause. Look for keywords: "actually because", "real reason", "not because", "motivated by", "the reason was", "wasn't because".
   - If a matching `motivated_by` edge exists in the current graph (same source or target entity as the correction references): update the edge's `fact` field to reflect the corrected motivation, and add `"corrected": true` to the edge.
   - If no matching `motivated_by` edge is found, process the correction as a normal record — it may still generate new nodes/edges via steps 2–4.

6. **Write** `agent-persona/data/knowledge/memory_graph.json`. Set `last_built` to current ISO timestamp.

7. **Generate visualization.** Run the script: `python3 agent-persona/scripts/visualize-graph.py`. This reads the graph JSON and outputs `agent-persona/data/knowledge/memory_graph.html`.

## Node schema

| Field | Req | Description |
|-------|-----|-------------|
| `id` | yes | Stable kebab-case identifier |
| `name` | yes | Human-readable name |
| `type` | yes | Hint: `person`, `component`, `tool`, `concept`, `preference`, `decision` |
| `summary` | yes | 1-2 sentence description |
| `first_seen` | yes | ISO date (YYYY-MM-DD) when first observed |
| `last_seen` | yes | ISO date (YYYY-MM-DD) of most recent observation |
| `properties` | no | Freeform key-value pairs for extra metadata |

## Edge schema

| Field | Req | Description |
|-------|-----|-------------|
| `id` | yes | Unique edge id (e.g. `e-001`) |
| `source` | yes | Source node id |
| `target` | yes | Target node id |
| `type` | yes | Relationship type (see step 3) |
| `fact` | yes | 1-sentence natural language description of the relationship |
| `confidence` | yes | 0.0–1.0, starts at 0.5, incremented when corroborated |
| `first_seen` | yes | ISO date |
| `last_seen` | yes | ISO date |
| `source_episodes` | no | List of episode ids that evidence this edge |

## File schema

```json
{
  "version": 1,
  "last_built": "ISO timestamp",
  "nodes": [...],
  "edges": [...]
}
```

## Error handling

- If knowledge.json is missing, abort and report error.
- If no episodic files exist, build from knowledge only.
- If existing graph is missing, create from scratch.
- If visualization script fails, still write the graph JSON and note the failure.
