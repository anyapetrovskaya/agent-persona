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

## Pruning (always run after merge)

- Merge near-duplicates: keep one, merge `source`, sum `strength`.
- Drop strength-1 items superseded by newer/stronger items.

## Workflow

1. **Scope:** Read episodic files from `agent-persona/data/episodic/`. Filter if task prompt specifies a subset.
2. **Record archive cutoff:** Record today's date as `archive_cutoff`.
3. **Extract:** For each episode's `records`, create candidate knowledge items using the extraction rules above.
4. **Load existing:** Read `agent-persona/data/knowledge/knowledge.json` or start with `{ "items": [] }`.
5. **Merge:** Dedupe, resolve conflicts, add or update.
6. **Contradiction scan:** For each `trait` or `preference` item (especially those with `source_type: "self_reported"`), search recent episodic records for counter-evidence — behavioral patterns that contradict the stated belief. If counter-evidence is found:
   - Set `contested: true` on the knowledge item.
   - Set `counter_evidence` to `"<episode_id>: <brief summary of contradicting evidence>"`.
   - If the item was already `contested` and counter-evidence is from a new episode, append to the existing `counter_evidence` string.
   - Clear `contested` and `counter_evidence` if the item is no longer contradicted (e.g., user behavior has changed to match the belief).
   Examples: trait "works in short 1-2h sessions" + episodic "logged 5-8h session" → contested. Preference "prefers tabs" + episodic "switched project to spaces" → contested.
7. **Prune:** Merge near-duplicates, drop superseded. Do not skip.
8. **Write:** Save `agent-persona/data/knowledge/knowledge.json` (UTF-8). Set `last_infer_date` to today. Preserve existing items that were not updated.
9. **Build memory graph.** Read `agent-persona/tasks/build-memory-graph/task.md` and execute. Pass: knowledge path (`agent-persona/data/knowledge/knowledge.json`), episodic path (`agent-persona/data/episodic/`), graph path (`agent-persona/data/knowledge/memory_graph.json`). This extracts entities and relationships into a graph and generates an HTML visualization.
10. **Rebuild timeline.** Run `python agent-persona/scripts/visualize-timeline.py` to regenerate `agent-persona/data/knowledge/memory_timeline.html` from all current data sources. If the script fails, note the error but continue.
11. **Archive old episodes:** Use `archive_cutoff`. For each `agent-persona/data/episodic/episode_*.json`, parse the date portion (`YYYY-MM-DD`) from the filename. If the episode date is **strictly before** `archive_cutoff`, move it to `agent-persona/data/episodic/archived/`. Episodes from the same day or newer stay. Do not move `.gitkeep`.
12. **Infer base persona:** Read `agent-persona/tasks/infer-base-persona/task.md` and execute on the knowledge just written.
13. **Suggest behavior:** Read `agent-persona/tasks/suggest-learned-behavior/task.md` and execute. If a candidate trigger is returned, include it in your report.
14. **Proactive initiative:** Read `agent-persona/tasks/proactive-initiative/task.md` and execute with trigger=`after_infer_knowledge`, context=summary from above. If a line is returned, include it.
15. **Reflect:** Read `agent-persona/tasks/reflect/task.md` and execute. Pass: episodes processed in step 1, knowledge counts from this run (+added, ~updated, -pruned), eval log path (`agent-persona/data/eval/eval_log.json`). Include reflection summary in report.

## Report format

```
Counts: +N added, ~N updated, -N pruned
Contradictions: N found (examples: ...)
Examples: [1–2 example knowledge items]
Base persona: <default_mode> (changed/unchanged)
Suggested trigger: <candidate JSON or "none">
Initiative: <line or "none">
Reflection: <summary or "none">
```
