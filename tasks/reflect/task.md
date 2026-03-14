# Reflect — Sub-Agent Task

You are the reflection sub-agent. You own the full lifecycle: gather data, reason, write results.

## Lifecycle

1. **Gather:** Run `bash agent-persona/tasks/reflect/pre.sh [--session <id>] [--invocation <id>]` via Shell (pass session and invocation IDs if provided in your prompt). Capture its stdout — this is your input data, organized as `=== SECTION ===` blocks.
2. **Reason:** Follow the Steps below using the data from pre.sh.
3. **Write:** Pipe your structured output (all `=== SECTION ===` blocks from step 5) to `bash agent-persona/tasks/reflect/post.sh` via Shell. Capture its stdout — this is the clean report.
4. **Return:** Return the clean report from post.sh as your final response.

## Input (from pre.sh)

| Section | Contents |
|---------|----------|
| LAST_REFLECTION | `date` of most recent reflection (or "never") |
| EPISODES | Episode JSON blobs separated by `--- episode_id ---` headers, or "none" |
| EVAL_LOG | Full eval_log.json contents, or "not found" |
| EVAL_BASELINE | Full baseline.json contents, or "not found" |
| REFLECTIONS | Full reflections.json contents, or "not found" |
| PROCEDURAL_NOTES | Full procedural_notes.json contents, or "not found" |

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

From EPISODES, categorize records into:

- **Corrections** (type="correction"): mistakes to learn from. Note what went wrong and what the fix was.
- **Positive reactions** (emotional_value > 0): what to keep doing.
- **Negative reactions** (emotional_value < 0): frustrations or pain points.
- **Repeated patterns**: themes appearing across multiple episodes.

Summarize into a list of observations, each with `type` (correction/positive/negative/pattern), `content`, and `source` episode id.

If EPISODES is "none", report zero observations.

### 2. Compare

From EVAL_LOG, compute recent metrics:
- Correction rate: count of corrections / count of sessions (from session_summary events)
- Retrieval avg items: mean of total_items from retrieval events
- Handoff usefulness: % of handoff_check events where self_assessed_useful is true

From EVAL_BASELINE (if present), note deltas from baseline.

From REFLECTIONS, get the most recent reflection's `eval_snapshot` for trend comparison.

Use null for any metric without sufficient data.

### 3. Verify previous adjustments

From PROCEDURAL_NOTES, for each note with status `active` or `verified_helpful`:

- Count sessions since the note was created (or last verified).
- If 3+ sessions have passed:
  - Search episode records for recurrence of the issue the note addresses.
  - If issue has NOT recurred: mark as `verified_helpful`, set `verified` to today's date.
  - If issue HAS recurred: mark as `verified_unhelpful`.
- Notes with status `verified_unhelpful`: auto-retire (set status to `retired`).
- Notes older than 30 days without any verification: flag as stale.

### 4. Adjust

From observations in step 1, derive candidate procedural notes:

**Confidence assignment:**
- **High confidence** (auto-apply): pattern supported by 3+ episodes, explicit user correction with clear generalizable fix, or reinforcement of existing note.
- **Low confidence** (queue for approval): single episode, ambiguous correction, or communication style change.

**Rules:**
- Check existing notes for overlap — reinforce rather than duplicate.
- Cap at 2 new notes per reflection.
- Cap total active notes at 15. If at cap, only add if retiring another.
- Notes should be actionable and general — not tied to a specific file or conversation.

### 5. Compose structured output

Compose ALL of the following sections as a single text block. This entire block will be piped to post.sh.

**Report section** (displayed to user):

```
=== REPORT ===
Reflection: ref_<YYYY-MM-DD>
Observations: N (corrections: N, positive: N, negative: N, patterns: N)
Eval snapshot: correction_rate=N, retrieval_avg=N, handoff_useful=N%
Verifications: N checked (helpful: N, unhelpful: N, retired: N)
New notes: N (auto-applied: N, pending approval: N)
Active notes: N / 15 cap
Pending approval: <list of note contents, or "none">
Stale notes: <list of note ids older than 30 days without verification, or "none">
```

**Reflection entry** (for reflections.json):

```
=== REFLECTION_ENTRY ===
<single-line JSON object>
```

Format:
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
      "auto_applied": true
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

**Updated procedural notes** (full replacement for procedural_notes.json):

```
=== UPDATED_NOTES ===
<single-line JSON object: {"notes": [<all notes with status changes applied and new notes added>]}>
```

**Eval event** (for eval_log.json):

```
=== EVAL_EVENT ===
<single-line JSON object>
```

Format:
```json
{
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

- If any data section from pre.sh is "not found" or "none", skip the corresponding step gracefully.
- A reflection with zero observations and zero verifications is valid.
- Always emit all output sections, even if mostly empty/zeroed.
