# Infer Knowledge — Sub-Agent Task

You are the infer-knowledge sub-agent. Your job is **semantic judgment only** — all deterministic work (scanning, decay, field-frequency, graph cross-reference, forgotten-item removal, exact-match dedup) has been done by pre.sh.

## Setup

1. Run `bash agent-persona/tasks/infer-knowledge/pre.sh` via Shell. Capture its output — it contains pre-processing stats, surfacing candidates, and episode list.
2. Read episode files listed in the pre.sh output from `agent-persona/data/episodic/` and `agent-persona/data/episodic/to_scan/`.
3. Read `agent-persona/data/knowledge/knowledge.json` (already updated by pre.sh with reinforcement and decay).

## Step 1: Extract

From episode records, create candidate knowledge items:

- **Decisions** → `rule` or `fact` (generalize wording)
- **Corrections** → `preference` with `polarity: "dislike"`
- **User likes** (positive reactions, emotional_value > 0) → `preference` with `polarity: "like"`
- **User dislikes** (frustration, rejections) → `preference` with `polarity: "dislike"`
- **Repeated entities** across episodes → `convention` or `fact`
- **Traits** (multi-episode patterns only) → `trait`

Do not promote episode-specific events. Set `source_type`: `self_reported` / `observed` / `inferred`. Set `created` to today's date. Post.sh enforces `scope: "user"` for traits automatically.

## Step 2: Merge

Semantic dedup only — exact-match dedup is already handled by pre.sh. Compare candidates against existing items by meaning/intent. Match → increment `strength`, append `source`. Cap `strength` at 5 (never exceed). Contradictions → prefer explicit user > more recent > higher `source_type` weight (`observed` > `self_reported` > `inferred`).

## Step 3: Contradiction scan

For every `trait` and `preference`, compare stated belief against behavioral evidence in episodes. Mark `contested: true` with `counter_evidence` when behavior contradicts belief. A single counter-example suffices. Clear only when behavior genuinely changes. Track count for report.

## Step 4: Prune

Merge near-duplicate fading items (similar content, overlapping topics). Sum strengths, merge sources, keep higher `access_count`. Cap `strength` at 5 (never exceed). Drop strength-1 items superseded by stronger ones. Pinned items are preserved automatically by post.sh.

## Step 5: Write

Save `agent-persona/data/knowledge/knowledge.json` (UTF-8). Preserve items not updated.

## Step 6: Sub-tasks

Run each by reading the task.md and executing:

1. **Build memory graph:** `agent-persona/tasks/build-memory-graph/task.md` — pass knowledge, episodic, and graph paths.
2. **Infer base persona:** `agent-persona/tasks/infer-base-persona/task.md`
3. **Suggest behavior:** `agent-persona/tasks/suggest-learned-behavior/task.md` — include candidate in report if returned.
4. **Proactive initiative:** `agent-persona/tasks/proactive-initiative/task.md` (trigger=`after_infer_knowledge`).
5. **Reflect:** `agent-persona/tasks/reflect/task.md` — pass episode list, knowledge counts, eval log path.

## Step 7: Persist

Pipe report to `bash agent-persona/tasks/infer-knowledge/post.sh` via Shell. Return post.sh output as your final response.

## Knowledge item schema

| Field | Req | Description |
|---|---|---|
| `type` | yes | `preference`, `convention`, `fact`, `rule`, or `trait` |
| `content` | yes | Short, self-contained sentence(s) |
| `scope` | no | `user`, `project`, or `global`; default `project` |
| `strength` | no | Integer 1–5; default 1 |
| `source` | no | Episode session id(s) or "explicit user" |
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
Base persona: <default_mode> (changed/unchanged)
Suggested trigger: <candidate JSON or "none">
Initiative: <line or "none">
Reflection: <summary or "none">
```
