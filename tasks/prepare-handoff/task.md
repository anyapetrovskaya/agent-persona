# Prepare Handoff — Sub-Agent Task

You are the handoff sub-agent. You own the full lifecycle: gather data, reason, write results.

## Lifecycle

1. **Gather:** Run `bash agent-persona/tasks/prepare-handoff/pre.sh [--session <id>] [--invocation <id>]` via Shell (pass session and invocation IDs if provided in your prompt). Capture its stdout — this is your input data, organized as `=== SECTION ===` blocks.
2. **Reason:** Follow the Steps below using the data from pre.sh. The main agent provides a conversation summary in your prompt.
3. **Write:** Construct your structured output and pipe it to post.sh (see step 6 below).
4. **Return:** Return the output of post.sh as your final response.

## Sections handled by format.sh (DO NOT generate)

SKIP these sections — they are rendered by format.sh at startup from live data:
- **Backlog highlights** — format.sh reads backlog.json directly
- **Sibling threads** — format.sh reads sibling conversation files directly
- **Cross-thread coordination** — covered by sibling threads rendering

Do NOT include these in your handoff markdown output. Any content you write for them will be duplicated.

## Input (from pre.sh)

| Section | Contents |
|---------|----------|
| CONFIG | git_sync, timezone, save_interval |
| EPISODE_META | path, session_id, is_new, existing_record_count |
| EXISTING_EPISODE | Full episode JSON or NONE |
| SAVE_BOUNDARY | HH:MM boundary value |
| HANDOFF_TRIGGERS | JSON array of approved before_handoff triggers |
| TIMESTAMPS | iso, tz, tz_offset |
| CORRECTION_COUNT | Count of corrections in existing episode |
| EVAL_LOG | path, exists, event_count |
| FLAGS | end_of_day, debug, git_sync |
| SIBLING_MAIN_THREADS | Content of other main_*.md handoffs (for cross-thread awareness only — do NOT write a dedicated section for this) |
| RECENT_CONVERSATION | (provided in prompt by main agent) Last 2 user/assistant exchanges, truncated to ~500 chars each |

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

Write a handoff with two distinct sections — **Persistent context** (carried forward across sessions) and **Recent work context** (refreshed each save).

```
## Persistent context

### Active conversation threads
<ongoing topics that span multiple sessions — carry forward until resolved>

### Unfixed issues / blockers
<known bugs, blockers, or unresolved problems — carry forward until fixed>

### Ongoing project goals
<high-level goals or milestones the user is working toward>

## Recent work context
Last active: <TIMESTAMPS iso value>

### Last 3 user intents
<extract the user's last 3 distinct requests/intents from the conversation summary or episode data, most recent first; if fewer than 3, list what's available>
1. ...
2. ...
3. ...

### Current topic / goal
[1-3 sentences]

### Key decisions (this session)
- ...

### Open questions
- ...

### Suggested next steps
- ...

### Session notes
<minor observations, cleanup items, edge cases>

### Recent conversation
<last 2 user/assistant exchanges, verbatim from RECENT_CONVERSATION. Format each as:
> **User:** <content>
> **Assistant:** <content>
Truncate each to ~500 chars. If not provided, omit this section entirely.>
```

**Preservation rules:**
- **Persistent context** must be carried forward from the previous handoff. Only remove items when they are explicitly resolved, completed, or dismissed by the user. Add new items as they arise.
- **Recent work context** is refreshed each save to reflect the current session.

Reminders are managed in backlog.json, not in the handoff. Do NOT add a reminders section.

Do NOT include `### Backlog highlights` or `### Sibling threads` sections — these are rendered by format.sh at startup from live data.

Keep total handoff under 600 words. Do NOT include "Last updated" or "Latest episode" headers — post.sh adds those.
The `### Recent conversation` section does NOT count toward the 600-word limit — it is verbatim content, not summarized.

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
  [--conversation <conversation from FLAGS, if non-empty>] \
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

Include `--conversation <value>` when the FLAGS section shows a non-empty `conversation=` value.
Add `--git-sync` only if FLAGS shows `git_sync=true`.

## Report

Return the output of post.sh as your report. Include any initiative line prominently at the top. Always include the episode path.
