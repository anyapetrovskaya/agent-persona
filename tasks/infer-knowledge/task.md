# Infer Knowledge — Sub-Agent Task

You are the infer-knowledge sub-agent.

## File paths

- **Episodic input:** `agent-persona/data/episodic/*.json` — **read only** during extraction. Archival step moves old files after write.
- **Knowledge output:** `agent-persona/data/knowledge/knowledge.json` — single JSON file with `last_infer_date` and `items` array. Create if missing.
- **Base persona:** `agent-persona/data/base_persona.json`
- **Learned triggers:** `agent-persona/data/learned_triggers.json`

## Knowledge item schema

| Field | Required | Description |
|---|---|---|
| `type` | yes | `preference`, `convention`, `fact`, `rule`, or `trait` |
| `content` | yes | Short, self-contained sentence(s); not tied to a specific chat |
| `scope` | no | `user`, `project`, or `global`; default `project` |
| `strength` | no | Integer ≥ 1; reinforcement count (default 1) |
| `source` | no | Episode session id(s) or "explicit user" |
| `polarity` | no | For preferences: `like` or `dislike`; omit if unclear |
| `source_type` | no | `self_reported`, `observed`, or `inferred`; default `inferred` |
| `contested` | no | `true` if counter-evidence exists; omit if not contested |
| `counter_evidence` | no | Episode reference + brief summary of contradicting evidence |
| `last_accessed` | no | ISO 8601 timestamp of last retrieval; `null` on new items |
| `access_count` | no | Integer; number of times retrieved via query-knowledge; `0` on new items |
| `pinned` | no | Boolean; user-pinned items are exempt from future pruning; `false` on new items |
| `created` | **yes** | Date string (YYYY-MM-DD); **REQUIRED** on all new items — set to today's date when creating |
| `emotional_value` | no | Float (-2 to +2); emotional significance propagated from episodic records; `null` on new items |
| `retention_score` | no | Float; computed by `compute-decay.sh` during consolidation — do not set manually |

**Types:**
- **preference:** Likes/dislikes. Use `polarity`.
- **convention:** How things are done.
- **fact:** Resolved fact about the project or domain.
- **rule:** Decision pattern or general rule.
- **trait:** User personality/style/values (scope always `user`); infer from patterns across multiple episodes, not single events.

**Do not promote** episode-specific events ("In chat X we fixed Y"). Promote the general rule or fact.

## Extraction rules

- **Decisions** → candidate **rule** or **fact** (generalize wording).
- **Corrections** → **preference** with **polarity: "dislike"** for what was overridden.
- **User likes** (positive reactions, repeated requests, emotional_value > 0) → **preference** with **polarity: "like"**.
- **User dislikes** (frustration, rejections, emotional_value < 0) → **preference** with **polarity: "dislike"**.
- **Repeated entities** (same file/module across episodes with stable role) → **convention** or **fact**.
- **Traits:** Patterns across multiple episodes; not one-off behavior.

**Source type assignment** (set `source_type` on every new item):
- User explicitly states something about themselves ("I prefer", "I like", "I work in", "I usually") → `self_reported`
- Derived from observed user behavior across episodes (repeated actions, measured patterns) → `observed`
- Agent inferred from indirect evidence or single-episode patterns → `inferred`
- Default for existing items missing the field: `inferred`

## Dedup & conflict resolution

- Match by meaning (exact or paraphrase). If found: increment `strength`, append to `source`; do not duplicate.
- Contradictions: prefer **explicit user** > **more recent** > older. Update/replace; do not keep both.
- When resolving contradictions, also consider `source_type` weight: `observed` > `self_reported` > `inferred`.
- **Access tracking fields** (`last_accessed`, `access_count`, `pinned`): preserve on existing items — never overwrite during merge. New items get `last_accessed: null`, `access_count: 0`, `pinned: false`.
- **`created`:** REQUIRED on all new items. Always set `created` to today's date (YYYY-MM-DD) when creating new knowledge items.

## Pruning (always run after merge)

- Merge near-duplicates: keep one, merge `source`, sum `strength`. Preserve the higher `access_count` and most recent `last_accessed` from the merged items.
- Drop strength-1 items superseded by newer/stronger items. Never drop items with `pinned: true`.

## Workflow

0pre. **Prepare episodes for scanning.** Run `bash agent-persona/scripts/scan-graph-edges.sh --prepare` via Shell. This moves episodes older than the cutoff from `episodic/` to `episodic/to_scan/` based on filename timestamp (default cutoff: now). Pass `--cutoff <epoch>` to override. Steps 0 and 0a then process `to_scan/` before episodes are archived.

0. **Knowledge reinforcement scan.** Run `bash agent-persona/scripts/scan-archived-reinforcements.sh` via Shell. This boosts existing knowledge items' strength based on keyword co-occurrence in `to_scan/` episodes (≥2 of 5 key terms must match per episode — majority matching, not any-term) — pure bash/jq, zero token cost. Boost: +1 per 3 distinct matching episodes, cap +5 per scan, cap 10 total strength. Runs after the prepare step moves episodes to `to_scan/`, so each episode is processed exactly once. Capture the output summary for inclusion in the final report under "Knowledge reinforcement". If the script fails, log the error and continue.
0a. **Scan graph edges.** Run `bash agent-persona/scripts/scan-graph-edges.sh` via Shell. This scans `to_scan/` for node co-occurrences and writes a delta file (`data/knowledge/graph_delta.json`). Each episode is scanned exactly once. If the script fails, log the error and continue.
1. **Scope:** Read episodic files from `agent-persona/data/episodic/` AND `agent-persona/data/episodic/to_scan/` (episodes moved by the prepare step). Filter if task prompt specifies a subset.
2. **Record archive cutoff:** Record today's date as `archive_cutoff`.
3. **Extract:** For each episode's `records`, create candidate knowledge items using the extraction rules above.
4. **Load existing:** Read `agent-persona/data/knowledge/knowledge.json` or start with `{ "items": [] }`.
5. **Schema-aware reinforcement:** Beyond content text, scan the structural fields used across episodic records to detect foundational concepts invisible to content-only extraction. If a concept appears as a field name on many records (e.g., `emotional_value` on 300+ records), that concept is foundationally important — this is the "water doesn't know it's wet" problem, where the most pervasive concepts are so taken for granted they never appear in `content` text.

   **5a. Field-frequency scan:** Count how many episodic records use each field. The base schema fields (always present) are: `type`, `content`, `turn`, `timestamp`, `emotional_value`. Scan for these specific fields plus any non-standard fields beyond the base schema: `emotional_value` (base but represents a key design concept), `source_type`, `contested`, `counter_evidence`, and any others found.

   For each field appearing on many records:
   - **If a knowledge item already exists for the concept:** boost its `strength` by 1 for every 50 records using it as a field (cap total strength at 5). Append the current consolidation run date to `source`.
   - **If no knowledge item exists:** create one (type `convention` or `rule`) describing what the field represents, how it's used across the system, and why it matters. Set `source` to the current consolidation run date. Set `created` to today's date (YYYY-MM-DD). Set initial `strength` proportional to usage count (1 per 50 records, minimum 1, cap 5).

   **5b. Knowledge graph cross-reference:** If `agent-persona/data/knowledge/memory_graph.json` exists from a previous consolidation run, load it and check for nodes with `category` equal to `"system"` or `"principle"`. When a knowledge item maps to (or describes the same concept as) a graph node in one of these categories, treat that as a reinforcement signal: boost `strength` by 1 (cap at 5) and note `"graph-reinforced: <node_label>"` in the item's `source`. System and principle concepts are by definition important to preserve — their presence in the graph confirms structural importance beyond what content mentions alone would show.

   Record schema-reinforced and graph-reinforced counts for the report.
6. **Merge:** Dedupe, resolve conflicts, add or update.
7. **Contradiction scan (MANDATORY — do not skip):** Iterate over every `trait` and `preference` item in the merged knowledge (especially `source_type: "self_reported"` items, but check all). For each one, explicitly compare its `content` against concrete behavioral evidence in recent episodic records. Ask: "Does the user's actual behavior match this stated belief?"

   **How to check:** Look at session durations, timestamps, repeated actions, stated intentions vs. outcomes, and any quantitative observations in episodes. A single counter-example is enough to mark contested.

   **When counter-evidence is found:**
   - Set `contested: true` on the knowledge item.
   - Set `counter_evidence` to `"<episode_id>: <brief summary of contradicting evidence>"`.
   - If already `contested` with existing counter-evidence from a different episode, append the new evidence (semicolon-separated).
   - Do NOT silently skip — if you find a contradiction, you MUST mark it.

   **When to clear:** Remove `contested` and `counter_evidence` only if the user's behavior has genuinely changed to match the belief (not just because one recent episode is consistent).

   **Concrete example:** Belief: "User works in short, focused 1-2 hour sessions" (`source_type: "self_reported"`). Episodic evidence: user logged 5-8 hour sessions across multiple days. Result → `contested: true`, `counter_evidence: "episode_2026-03-05: 6h session; episode_2026-03-06: 5h session"`.

   **Another example:** Preference: "prefers tabs over spaces" (`self_reported`). Episode shows user switched the project config to spaces and kept it. Result → `contested: true`, `counter_evidence: "episode_2026-03-07: switched .editorconfig to spaces, no revert"`.

   **Track the count:** Record the total number of contested items found (new + previously contested). This count MUST appear in the report output.
8. **Prune:** Merge near-duplicates, drop superseded. Do not skip.
9. **Graceful forgetting (decay cycle).** Run `bash agent-persona/scripts/compute-decay.sh` via Shell. This annotates each non-pinned knowledge item with a `retention_score` computed from strength, access recency, emotional significance, reinforcement recency, and graph connectivity (well-connected graph nodes resist decay). Pinned items are immune — skipped entirely.

   Then apply decay actions to the knowledge items:

   a. **Forgotten (`retention_score < 0.5`):** Remove these items from the store. Log each removed item in the report (type, content snippet, score).

   b. **Fading (`0.5 ≤ retention_score < 1.5`):** Check for merge opportunities — fading items with similar content, same source, or overlapping topics. If two or more fading items can be combined into one more compact item, do so: merge content concisely, sum strengths, merge sources, keep the higher `access_count` and most recent `last_accessed`. Log merges in the report.

   c. **Healthy (`retention_score ≥ 1.5`):** Keep as-is.

   d. **Surfacing:** If any items have `|emotional_value| ≥ 1.5` AND `retention_score < 1.5` (high emotional significance but fading), list them in a "Surfacing" section of the report for the main agent to optionally mention to the user.

   Record forgotten/merged/surfacing counts for the report.
10. **Write:** Save `agent-persona/data/knowledge/knowledge.json` (UTF-8). Set `last_infer_date` to today. Preserve existing items that were not updated.
11. **Build memory graph.** Read `agent-persona/tasks/build-memory-graph/task.md` and execute. Pass: knowledge path (`agent-persona/data/knowledge/knowledge.json`), episodic path (`agent-persona/data/episodic/`), graph path (`agent-persona/data/knowledge/memory_graph.json`). This extracts entities and relationships into a graph and generates an HTML visualization.
12. **Rebuild timeline.** Run `python agent-persona/scripts/visualize-timeline.py` to regenerate `agent-persona/data/knowledge/memory_timeline.html` from all current data sources. If the script fails, note the error but continue.
13. **Apply graph delta and archive.** Run `bash agent-persona/scripts/scan-graph-edges.sh --apply` via Shell. This merges the graph delta (new + reinforced edges) into `memory_graph.json`, moves scanned episodes from `to_scan/` to `archived/`, and deletes the delta file. If the script fails, log the error and continue.
14. **Infer base persona:** Read `agent-persona/tasks/infer-base-persona/task.md` and execute on the knowledge just written.
15. **Suggest behavior:** Read `agent-persona/tasks/suggest-learned-behavior/task.md` and execute. If a candidate trigger is returned, include it in your report.
16. **Proactive initiative:** Read `agent-persona/tasks/proactive-initiative/task.md` and execute with trigger=`after_infer_knowledge`, context=summary from above. If a line is returned, include it.
17. **Reflect:** Read `agent-persona/tasks/reflect/task.md` and execute. Pass: episodes processed in step 1, knowledge counts from this run (+added, ~updated, -pruned), eval log path (`agent-persona/data/eval/eval_log.json`). Include reflection summary in report.
18. **Persist via post.sh:** Pipe your report to `bash agent-persona/tasks/infer-knowledge/post.sh` via Shell. Return the output of post.sh as your final response. Post.sh runs short-term memory cleanup (expired files in `data/short-term/`) as part of the consolidation cycle — you do not need to run it yourself.

## Report format

```
Archived reinforcement: N boosted (+N total strength) or "no new reinforcements"
Counts: +N added, ~N updated, -N pruned
Schema: N field-boosted, N graph-reinforced
Decay: N forgotten, N fading (N merged), N healthy, N surfacing
Contradictions: N found (examples: ...)
Examples: [1–2 example knowledge items]
Surfacing: [high-emotional fading items for user mention, or "none"]
Base persona: <default_mode> (changed/unchanged)
Suggested trigger: <candidate JSON or "none">
Initiative: <line or "none">
Reflection: <summary or "none">
```
