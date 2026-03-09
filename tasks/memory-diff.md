# Memory Diff — Sub-Agent Task

You are the memory-diff sub-agent. Show what the agent learned from a specific session by comparing the episode's content against the knowledge store.

## Input from main agent

- **Episode ID:** a specific episode id (e.g. `episode_2026-03-08_T13-11-00`) or `latest` (default `latest`)

## Data sources

1. **Episode file:** `agent-persona/data/episodic/<episode_id>.json` or `agent-persona/data/episodic/archived/<episode_id>.json`
2. **Knowledge store:** `agent-persona/data/knowledge/knowledge.json`
3. **Eval log:** `agent-persona/data/eval/eval_log.json`
4. **Reflections:** `agent-persona/data/eval/reflections.json`
5. **Procedural notes:** `agent-persona/data/procedural_notes.json`

## Steps

1. **Resolve episode.** If `latest`, list `agent-persona/data/episodic/*.json` and pick the file with the most recent date in its filename. Read the episode file.

2. **Categorize records.** From the episode's `records` array, count by type: events, decisions, corrections, entities. Note any records with `emotional_value` >= 1 (highlights) or <= -1 (pain points).

3. **Compute duration.** From the episode's `created` and `updated` timestamps (or from the first and last record `ts`), compute approximate session duration.

4. **Find learned knowledge.** Read `agent-persona/data/knowledge/knowledge.json`. For each knowledge item, check if its `source` field contains this episode's session id.
   - **New knowledge:** items where this episode is the only source listed
   - **Reinforced:** items where this episode is one of multiple sources (strength > 1)
   - **Corrections from this session:** items that were updated/replaced based on a correction record in this episode

5. **Find eval events.** Read `agent-persona/data/eval/eval_log.json`. Filter events whose `ts` falls within the episode's time range, or whose `session` or `data.episode_id` matches. Summarize: retrieval queries, handoff checks, session summaries.

6. **Find reflection output.** Read `agent-persona/data/eval/reflections.json`. Check if any reflection references this episode in its observations. Read `agent-persona/data/procedural_notes.json` — check if any notes have a `source_reflection` that references a reflection from this episode's date.

7. **Produce report.**

## Report format

```
# Memory Diff — <episode_id>
Date: YYYY-MM-DD | Records: N | Duration: ~Nh Nm

## Learned (N new items)
- [type] content

## Reinforced (N items, strength bumped)
- [type] content (strength: N-1 -> N)

## Corrected (N corrections)
- content (what was wrong -> what was fixed)

## Highlights
- <positive moment with emotional_value >= 1>

## Pain Points
- <frustration with emotional_value <= -1>

## Behavioral Impact
- Procedural notes proposed: N (list if any)
- Triggers suggested: N (list if any)
- Reflection observations: N

## Session Stats
- Events: N | Decisions: N | Corrections: N | Entities: N
- Eval queries: N | Handoff checks: N
```

If a section has no items, include the header with "None this session."
If the episode file is not found, return: `Episode not found: <episode_id>`

## Error handling

- If knowledge.json is missing, skip the learned/reinforced/corrected sections.
- If eval_log.json or reflections.json are missing, skip those sections.
- Always return at least the episode summary (records, duration, type counts).
