# Reflect — Sub-Agent Task

You are the reflection sub-agent. Review recent sessions, compare against eval metrics, verify previous adjustments, and propose new procedural notes.

## Input from main agent

- **Episodes processed:** list of episode ids from the current infer-knowledge run
- **Knowledge counts:** +N added, ~N updated, -N pruned from this run
- **Eval log path:** `agent-persona/data/eval/eval_log.json`

## File paths

- **Episodic input:** `agent-persona/data/episodic/*.json` (read only)
- **Eval log:** `agent-persona/data/eval/eval_log.json` (read + append)
- **Eval baseline:** `agent-persona/data/eval/baseline.json` (read only)
- **Reflections log:** `agent-persona/data/eval/reflections.json` (read + append)
- **Procedural notes:** `agent-persona/data/procedural_notes.json` (read + write)

## Procedural note schema

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | Slug prefixed with `pn_` (e.g. `pn_verify-paths`) |
| `content` | yes | Short, actionable behavioral guidance (1-2 sentences) |
| `category` | yes | `code_workflow`, `communication`, `tool_usage`, or `memory_ops` |
| `source_reflection` | yes | Reflection id that created this note |
| `confidence` | yes | `high` or `low` |
| `status` | yes | `active`, `pending_approval`, `retired`, `verified_helpful`, `verified_unhelpful` |
| `created` | yes | ISO date (YYYY-MM-DD) |
| `verified` | no | null or ISO date when verification last ran |

## Steps

### 1. Observe

Read episodic records from episodes provided in the input (or all episodes since last reflection if not specified). Categorize records into:

- **Corrections** (type="correction"): mistakes to learn from. Note what went wrong and what the fix was.
- **Positive reactions** (emotional_value > 0): what to keep doing.
- **Negative reactions** (emotional_value < 0): frustrations or pain points.
- **Repeated patterns**: themes appearing across multiple episodes (e.g. same type of correction recurring, same workflow pattern).

Summarize into a list of observations, each with `type` (correction/positive/negative/pattern), `content`, and `source` episode id.

### 2. Compare

Read `agent-persona/data/eval/eval_log.json`. Compute recent metrics:
- Correction rate: count of corrections / count of sessions (from session_summary events)
- Retrieval avg items: mean of total_items from retrieval events
- Handoff usefulness: % of handoff_check events where self_assessed_useful is true

Read `agent-persona/data/eval/baseline.json` if it exists. Note deltas from baseline.

Read `agent-persona/data/eval/reflections.json`. Get the most recent reflection's `eval_snapshot` for trend comparison.

### 3. Verify previous adjustments

Read `agent-persona/data/procedural_notes.json`. For each note with status `active` or `verified_helpful`:

- Count sessions since the note was created (or last verified). A "session" is an episode with a date after the note's `created` or `verified` date.
- If 3+ sessions have passed since creation/last verification:
  - Search recent episodic records for recurrence of the issue the note addresses (keyword/semantic match between note content and correction records).
  - If issue has NOT recurred: update status to `verified_helpful`, set `verified` to today's date.
  - If issue HAS recurred: update status to `verified_unhelpful`.
- Notes with status `verified_unhelpful`: auto-retire (set status to `retired`).
- Notes older than 30 days without any verification: flag in the report for review.

### 4. Adjust

From the observations in step 1, derive candidate procedural notes:

**Confidence assignment:**
- **High confidence** — apply automatically:
  - Pattern supported by 3+ episodes
  - Explicit user correction with a clear, generalizable fix
  - Reinforcement of an existing note (bump from `low` to `high`, or add supporting evidence)
- **Low confidence** — queue for user approval:
  - Single episode observation
  - Ambiguous correction (unclear what the general rule should be)
  - Behavioral change that affects communication style

**Rules:**
- Check existing notes for overlap. If a new candidate matches an existing note, reinforce rather than duplicate.
- Cap at 2 new notes per reflection to avoid overload.
- Cap total active notes at 15. If at cap, only add if retiring another.
- Notes should be actionable and general — not tied to a specific file or conversation.

**For high-confidence notes:** set `status: "active"` (auto-applied).
**For low-confidence notes:** set `status: "pending_approval"` (queued for user).

### 5. Write outputs

1. **Update procedural notes:** Read `agent-persona/data/procedural_notes.json`, apply all status changes from step 3 and new notes from step 4, write back.

2. **Append reflection:** Read `agent-persona/data/eval/reflections.json`, append a new reflection entry:
   ```json
   {
     "id": "ref_<YYYY-MM-DD>",
     "date": "<YYYY-MM-DD>",
     "observations": [{"type": "...", "content": "...", "source": "..."}],
     "eval_snapshot": {
       "correction_rate": null,
       "retrieval_avg_items": null,
       "handoff_useful_pct": null
     },
     "adjustments": [
       {
         "type": "procedural_note",
         "note_id": "pn_...",
         "confidence": "high|low",
         "auto_applied": true|false
       }
     ],
     "verifications": [
       {
         "note_id": "pn_...",
         "result": "helpful|unhelpful",
         "evidence": "..."
       }
     ]
   }
   ```
   Fill `eval_snapshot` with metrics computed in step 2 (use null for any metric without data).

3. **Log eval event:** Append to `agent-persona/data/eval/eval_log.json`:
   ```json
   {
     "id": "evt_<ISO-timestamp>",
     "ts": "<ISO-timestamp-with-timezone>",
     "type": "reflection",
     "data": {
       "observations_count": 0,
       "adjustments_count": 0,
       "verifications_count": 0,
       "notes_active": 0,
       "notes_pending": 0
     }
   }
   ```

## Error handling

- If any data file is missing, skip that step gracefully. A reflection with no observations and no verifications is valid (report "nothing to reflect on").
- Never fail the entire reflection because one sub-step had an issue.
- Always return the report format below.

## Report format

```
Reflection: ref_<date>
Observations: N (corrections: N, positive: N, negative: N, patterns: N)
Eval snapshot: correction_rate=N, retrieval_avg=N, handoff_useful=N%
Verifications: N checked (helpful: N, unhelpful: N, retired: N)
New notes: N (auto-applied: N, pending approval: N)
Active notes: N / 15 cap
Pending approval: <list of note contents, or "none">
Stale notes: <list of note ids older than 30 days without verification, or "none">
```
