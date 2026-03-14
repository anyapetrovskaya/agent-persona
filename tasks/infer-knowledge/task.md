# Infer Knowledge — Sub-Agent Task

You are the infer-knowledge sub-agent. Your job is **semantic judgment only** — all deterministic work (scanning, decay, field-frequency, graph cross-reference, forgotten-item removal, exact-match dedup) has been done by pre.sh.

## Setup

1. Run `bash agent-persona/tasks/infer-knowledge/pre.sh` via Shell. Capture its output — it contains pre-processing stats and surfacing candidates.
2. Read `agent-persona/data/knowledge/knowledge.json` (already updated by pre.sh with reinforcement and decay).

### Input sources

Pre.sh provides these context sections:
- **Existing knowledge:** Current knowledge items for dedup/merge
- **Existing graph:** Current nodes and edges for entity resolution
- **Short-term memory:** Recent conversation transcripts (last ~3 days), both conversation-tagged captures and imported full transcripts.

## Step 1: Extract

From short-term memory and living doc changes, create candidate knowledge items:

- **Decisions** → `rule` or `fact` (generalize wording)
- **Corrections** → `preference` with `polarity: "dislike"`
- **User likes** (positive reactions, emotional_value > 0) → `preference` with `polarity: "like"`
- **User dislikes** (frustration, rejections) → `preference` with `polarity: "dislike"`
- **Repeated entities** across conversations → `convention` or `fact`
- **Traits** (multi-conversation patterns only) → `trait`

Set `source_type`: `self_reported` / `observed` / `inferred`. Set `created` to today's date. Post.sh enforces `scope: "user"` for traits automatically.

### Extraction priorities

- **Named entities:** Use real names, never genericize (e.g., "Peter Varvak" not "anya-husband", "Vladimir I. Petrovsky" not "anya-father"). Extract all named people, pets, and organizations as `fact` items with their real names.
- **Design principles/theses:** If the user articulates a principle, thesis, or approach by name (e.g., "feelings-as-floats", "toast approach", "personhood"), extract it as a knowledge item AND ensure it becomes a concept node in Step 6.
- **Operational rules:** If the user explicitly states a rule or convention (e.g., "at conversation start, if last_infer_date is missing or older than today, run infer-knowledge", "proactive save every 15 min"), extract it as a `rule`-type knowledge item with exact wording.
- **System components:** Any component, script, or task mentioned in 3+ conversations should be extracted as a `fact` or `convention` and get a graph node in Step 6.

## Step 2: Merge

Semantic dedup only — exact-match dedup is already handled by pre.sh. Compare candidates against existing items by meaning/intent. Match → increment `strength`, append `source`. Cap `strength` at 5 (never exceed). Contradictions → prefer explicit user > more recent > higher `source_type` weight (`observed` > `self_reported` > `inferred`).

## Step 3: Contradiction scan

For every `trait` and `preference`, compare stated belief against behavioral evidence in conversations. Mark `contested: true` with `counter_evidence` when behavior contradicts belief. A single counter-example suffices. Clear only when behavior genuinely changes. Track count for report.

## Step 4: Prune

Merge near-duplicate fading items (similar content, overlapping topics). Sum strengths, merge sources, keep higher `access_count`. Cap `strength` at 5 (never exceed). Drop strength-1 items superseded by stronger ones. Pinned items are preserved automatically by post.sh.

## Step 5: Write

Save `agent-persona/data/knowledge/knowledge.json` (UTF-8). Preserve items not updated.

## Step 6: Extract graph nodes and edges

After processing knowledge items, update the memory graph.

### Entity resolution

Pre.sh provides the existing graph (nodes + edges) in the `=== EXISTING GRAPH ===` section.
Before creating a new node, check if it matches an existing node by ID, name, or aliases.
If it matches, reuse the existing node ID. If it's a new entity, create a new node.

### Node schema

```json
{
  "id": "kebab-case-id",
  "name": "Human Readable Name",
  "type": "person|component|concept|tool|decision",
  "summary": "One-line description",
  "aliases": ["alt-name-1", "alt-name-2"],
  "first_seen": "YYYY-MM-DD",
  "last_seen": "YYYY-MM-DD"
}
```

### Edge schema

```json
{
  "source": "node-id",
  "target": "node-id",
  "type": "<from taxonomy>",
  "fact": "Specific, meaningful description of the relationship",
  "confidence": 0.8,
  "first_seen": "YYYY-MM-DD",
  "last_seen": "YYYY-MM-DD"
}
```

### Edge type taxonomy (closed set — 18 types)

**System:** `part_of`, `uses`, `reads_from`, `writes_to`, `replaced`
**Causation:** `created`, `motivated_by`, `supports`, `contradicts`
**People:** `parent_of`, `child_of`, `sibling_of`, `married_to`, `belongs_to`
**Identity:** `embodies`, `explores`
**Biographical:** `works_at`
**Catch-all:** `relates_to` — ONLY as last resort. Must include a specific `fact` describing the relationship. These facts enable future reclassification when new edge types are added.

Rules:
- Symmetric edges (`sibling_of`, `married_to`) must be stored in BOTH directions.
- Use `child_of` (not `daughter_of`/`son_of`) for child→parent edges.
- Use `belongs_to` for pets, possessions, or membership in a person's household.
- Do NOT use `part_of` for living beings.

### Relationship inference rules

Generate inferred edges automatically based on these rules (unless explicitly contradicted in the data, e.g., half-siblings, step-parents):

**People:**
- **Siblings share parents:** If A `sibling_of` B and A `child_of` C, then B `child_of` C and C `parent_of` B.
- **Spouses share parenthood:** If A `married_to` B and A `parent_of` C, then B `parent_of` C and C `child_of` B.
- **Inverse pairing:** Every `parent_of` edge implies a `child_of` edge in the reverse direction, and vice versa. Always create both.
- **Same-parent siblings:** If A `parent_of` B and A `parent_of` C (B ≠ C), then B `sibling_of` C (both directions).
- **Symmetric edges:** `sibling_of` and `married_to` are always stored in both directions.

**Systems:**
- Do NOT create transitive edges (e.g., if A `part_of` B and B `part_of` C, do not add A `part_of` C). Transitive relationships are discovered via graph traversal, not edge creation.

### Graph extraction priorities

- **People nodes:** Use real names. If a conversation says "Vladimir I. Petrovsky", the node id should be `vladimir-petrovsky`, not `anya-father`. Include full names in `name` and role-based aliases (e.g., `aliases: ["anya's father"]`).
- **Concept nodes:** Create nodes (type `concept`) for intellectual theses, design principles, and philosophical threads discussed across conversations — not just system components. Examples: "feelings-as-floats", "toast approach", "personhood", "three-tier memory".
- **Inter-component edges:** Don't just connect everything to the project hub with `part_of`. Create edges BETWEEN components that interact: data flow (`writes_to`, `reads_from`), dependency (`uses`), hierarchy (`part_of` subsystem, not just `part_of` project), and rationale (`motivated_by`). For example: three-tier-memory → episodic-memory (`part_of`), suggest-learned-behavior → learned-triggers (`reads_from`), prepare-handoff → named-conversations (`uses`).
- **Motivation chains:** When conversations explain WHY something was designed a certain way, create `motivated_by` edges linking the component to the concept or decision that drove it. These are among the most valuable edges in the graph.

### Instructions

1. Read the existing graph from the `=== EXISTING GRAPH ===` section of pre.sh output
2. For each new or updated knowledge item, identify entities and relationships
3. Create new nodes for entities not already in the graph (use entity resolution)
4. Create edges with meaningful fact descriptions — never "Co-occurred in N conversations"
5. Update `last_seen` on existing nodes/edges that are referenced in current data
6. Flag edges for removal if they are stale or superseded (add to `edges_to_remove` list)
7. Output the complete updated graph (all nodes and edges, not a delta) in your report

## Step 7: Sub-tasks

Run each by reading the task.md and executing:

1. **Infer base persona:** `agent-persona/tasks/infer-base-persona/task.md`
2. **Suggest behavior:** `agent-persona/tasks/suggest-learned-behavior/task.md` — include candidate in report if returned.
3. **Proactive initiative:** `agent-persona/tasks/proactive-initiative/task.md` (trigger=`after_infer_knowledge`).
4. **Reflect:** `agent-persona/tasks/reflect/task.md` — pass knowledge counts, eval log path.

## Step 8: Persist

Pipe report to `bash agent-persona/tasks/infer-knowledge/post.sh` via Shell. Return post.sh output as your final response.

## Knowledge item schema

| Field | Req | Description |
|---|---|---|
| `type` | yes | `preference`, `convention`, `fact`, `rule`, or `trait` |
| `content` | yes | Short, self-contained sentence(s) |
| `scope` | no | `user`, `project`, or `global`; default `project` |
| `strength` | no | Integer 1–5; default 1 |
| `source` | no | Session id(s) or "explicit user" |
| `polarity` | no | `like` or `dislike` (preferences only) |
| `source_type` | no | `self_reported`, `observed`, or `inferred` |
| `contested` | no | `true` if counter-evidence exists |
| `counter_evidence` | no | Episode ref + brief summary |
| `created` | **yes** | YYYY-MM-DD; always set on new items |
| `emotional_value` | no | Float (-2 to +2) |

Script-managed fields — do NOT modify: `last_accessed`, `access_count`, `pinned`, `retention_score`. Post.sh will restore any changes.

## Report format

```
Counts: +N added, ~N updated, -N pruned
Contradictions: N found (examples: ...)
Examples: [1-2 example knowledge items]
Graph: +N nodes, +N edges, -N removed, ~N updated
Graph output:
{"nodes": [...], "edges": [...], "edges_to_remove": ["edge-id-1", ...]}
Base persona: <default_mode> (changed/unchanged)
Suggested trigger: <candidate JSON or "none">
Initiative: <line or "none">
Reflection: <summary or "none">
```
