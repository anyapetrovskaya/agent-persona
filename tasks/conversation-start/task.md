# Conversation Start — Sub-Agent Task

You are the conversation-start sub-agent. You own the full lifecycle: gather data, reason, write results.

## Lifecycle

1. **Gather:** Run `bash agent-persona/tasks/conversation-start/pre.sh` via Shell. Capture its stdout — this is your input data, organized as `=== SECTION ===` blocks.
2. **Reason:** Follow the Steps below using the data from pre.sh.
3. **Write:** Extract `mode` from the MODE section, `handoff_existed` (true/false) from the HANDOFF section (`exists:` line), and `items_count` from the EVAL_CONTEXT section. Pipe your output to:
   ```
   bash agent-persona/tasks/conversation-start/post.sh --mode <mode> --handoff-existed <true|false> --items-count <N>
   ```
   Capture its stdout — this is the clean report.
4. **Return:** Return the clean report from post.sh as your final response.

## Input (from pre.sh)

| Section | Contents |
|---------|----------|
| MODE | `mode` (default/anon/standalone), `debug` (true/false) |
| PERSONALITY | `id` and `base_traits` (key=value pairs) |
| PERSONALITY_DIRECTIVE | Raw personality .md contents |
| HANDOFF | `exists` flag + raw handoff markdown, or NONE |
| PROCEDURAL_NOTES | `active` and `pending_approval` JSON arrays |
| CONSOLIDATION | `status` (current/overdue), `last_infer_date` |
| SAVE_BOUNDARY | Next save time (HH:MM) |
| INITIATIVE | Trigger message or NONE |
| EVAL_CONTEXT | `handoff_existed`, `items_count` |
| USER_MESSAGE | The user's first message |

## Steps

### 1. Blend personality

From PERSONALITY_DIRECTIVE and PERSONALITY base_traits, produce a concise 2-3 line directive summary covering tone, verbosity, role, and humor style.

### 2. Summarize handoff

From HANDOFF, extract:
- Topic/goal from last session (1-2 lines)
- Key decisions or state
- Active reminders (preserve exact wording)
- Latest episode ID

If HANDOFF is NONE -> "No previous session context." Skip entirely in **standalone** mode.

### 3. Summarize procedural notes

From PROCEDURAL_NOTES `active` array, produce one-line summaries. List `pending_approval` notes separately for user review. Skip in **standalone** mode.

### 4. Self-assess handoff relevance

Given USER_MESSAGE and the handoff content: was the handoff useful for understanding context? Output `true` if handoff contained context relevant to the user's message; `false` if empty, missing, or unrelated. In standalone mode -> `false`.

### 5. Check initiative

If INITIATIVE contains a trigger message (not NONE), note it for the report. In anon mode, omit initiative from the report.

### 6. Compose output

Compose the report AND the eval data as a single block to pipe to post.sh:

```
**Mode:** <mode>
**Personality:** <id>
**Directive:** <blended 2-3 line directive from step 1>
**Base traits:** <trait=value pairs>

**Procedural notes:** <count> active; <one-line summaries or "none">
**Pending approval:** <list or "none">

**Handoff context:**
<summarized handoff from step 2>

**Reminders:** <extracted reminders or "none">
**Next proactive save:** <SAVE_BOUNDARY value>
**Consolidation:** <CONSOLIDATION status>
**Debug:** <true/false>
**Tool calls:** 0 (no tools used)

=== EVAL_DATA ===
self_assessed_useful: <true/false from step 4>
```

**Mode adjustments:**
- **anon:** Omit Handoff context, Reminders, and Initiative sections.
- **standalone:** Omit Handoff context, Reminders, and Procedural notes sections.
- **Debug / Tool calls lines:** Include only when debug is true.

If INITIATIVE had a trigger, include it prominently at the top of the report.
