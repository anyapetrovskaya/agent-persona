# Prepare Handoff — Sub-Agent Task

You are the handoff sub-agent. You own the full lifecycle: gather data, reason, write results.

## Lifecycle

1. **Gather:** Run `bash agent-persona/tasks/prepare-handoff/pre.sh` via Shell. Capture its stdout — this is your input data, organized as `=== SECTION ===` blocks.
2. **Reason:** Follow the Steps below using the data from pre.sh. The main agent provides a conversation summary in your prompt.
3. **Write:** Construct your structured output and pipe it to post.sh (see step 6 below).
4. **Return:** Return the output of post.sh as your final response.

## Input (from pre.sh)

| Section | Contents |
|---------|----------|
| CONFIG | git_sync, timezone, save_interval |
| EPISODE_META | path, session_id, is_new, existing_record_count |
| EXISTING_EPISODE | Full episode JSON or NONE |
| SAVE_BOUNDARY | HH:MM boundary value |
| EXISTING_REMINDERS | Reminder section from handoff or NONE |
| HANDOFF_TRIGGERS | JSON array of approved before_handoff triggers |
| TIMESTAMPS | iso, tz, tz_offset |
| CORRECTION_COUNT | Count of corrections in existing episode |
| EVAL_LOG | path, exists, event_count |
| FLAGS | end_of_day, debug, git_sync |

## Steps

### 1. Generate episodic records

From the conversation summary (provided by main agent in your prompt), create records for notable events, decisions, entities, and corrections since the last save.

**Record schema:**
| Field | Type | Description |
|-------|------|-------------|
| `type` | string | `event` \| `decision` \| `entity` \| `correction` |
| `content` | string | 1-2 sentence summary |
| `turn` | int | Approximate turn number |
| `emotional_value` | int | -2 to +2 |
| `ts` | string | ISO 8601 with timezone offset (use `tz_offset` from TIMESTAMPS) |

**Rules:**
- If EXISTING_EPISODE has records, only generate records for NEW turns not already covered
- Detect >20 min gaps between timestamps -> insert break records
- Cap inferred breaks at 5

### 2. Generate handoff markdown

Write a session summary:

```
## Reminder for user
<preserve from EXISTING_REMINDERS verbatim if not NONE>

## Current topic / goal
[1-3 sentences]

## Key decisions (this session)
- ...

## Open questions
- ...

## Suggested next steps
- ...

## Session notes
<minor observations, cleanup items, edge cases>
```

Keep under 500 words. Do NOT include "Last updated" or "Latest episode" headers — post.sh adds those.

### 3. Semantic trigger matching

If HANDOFF_TRIGGERS is non-empty, check each trigger's `condition` against the conversation context. Output matching `suggested_line` or `NOTHING`.

### 4. Eval data

Compute:
- `corrections` = CORRECTION_COUNT + count of new correction-type records
- `total_records` = EPISODE_META existing_record_count + count of new records

### 5. End-of-day (conditional)

If FLAGS shows `end_of_day=true`, spawn a sub-agent:

> Read agent-persona/tasks/infer-knowledge.md and execute.

Proceed without waiting.

### 6. Persist via post.sh

Construct your output and pipe to post.sh. Read `path` from EPISODE_META and boundary from SAVE_BOUNDARY:

```bash
cat <<'AGENT_OUTPUT' | bash agent-persona/tasks/prepare-handoff/post.sh \
  --episode <EPISODE_META path value> \
  --boundary <SAVE_BOUNDARY value> \
  [--git-sync]
=== EPISODE_RECORDS ===
<JSON array from step 1>
=== HANDOFF_CONTENT ===
<markdown from step 2>
=== INITIATIVE ===
<line from step 3>
=== EVAL_DATA ===
corrections=N total_records=N
AGENT_OUTPUT
```

Add `--git-sync` only if FLAGS shows `git_sync=true`.

## Report

Return the output of post.sh as your report. Include any initiative line prominently at the top. Always include the episode path.
