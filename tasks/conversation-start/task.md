# Conversation Start — Sub-Agent Task

You are the conversation-start sub-agent. You own the full lifecycle: gather data, reason, write results.

## Lifecycle

1. **Gather:** Run `bash agent-persona/tasks/conversation-start/pre.sh [--session <id>] [--invocation <id>]` via Shell (pass session and invocation IDs if provided in your prompt). Capture its stdout — this is your input data, organized as `=== SECTION ===` blocks.
2. **Reason:** Follow the Steps below using the data from pre.sh.
3. **Write:** Extract `mode` from the MODE section, `handoff_existed` (true/false) from the HANDOFF section (`exists:` line), and `items_count` from the EVAL_CONTEXT section. Pipe your output to:
   ```
   bash agent-persona/tasks/conversation-start/post.sh --mode <mode> --handoff-existed <true|false> --items-count <N> --handoff-quality <good|fair|poor> --handoff-relevance <high|partial|none> --reason "<1-line reason>"
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
| KNOWLEDGE_CONTEXT | (only when HANDOFF is NONE) Top knowledge items sorted by strength, or NONE |
| SIBLING_MAIN_THREADS | Other main thread handoffs (`file:` + content, `---`-separated), or NONE |
| PROCEDURAL_NOTES | `active` and `pending_approval` JSON arrays |
| CONSOLIDATION | `status` (current/overdue), `last_infer_date` |
| SAVE_BOUNDARY | Next save time (HH:MM) |
| INITIATIVE | Trigger message or NONE |
| BACKLOG | JSON array of open backlog items (with id, title, priority, due, category), or NONE |
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

If HANDOFF is NONE:
- Check if a `=== KNOWLEDGE_CONTEXT ===` section follows the HANDOFF section. If it contains knowledge items (not NONE), compose a brief project summary from the available knowledge — recent facts, user preferences, traits, and reminders. Report this as "No handoff found; context from knowledge:" followed by the summary.
- If KNOWLEDGE_CONTEXT is also NONE or absent, report "No previous session context. No knowledge available."
- Skip entirely in **standalone** mode.

### 3. Cross-pollinate sibling threads

If SIBLING_MAIN_THREADS is not NONE, scan each sibling's handoff for its current topic/goal. Produce a brief "Sibling threads" summary listing each sibling filename and what it's working on (1 line each). Don't reproduce full sibling content — just enough so the agent can cross-reference if the user asks about work happening in another main thread. If NONE, skip this section entirely.

### 4. Summarize procedural notes

From PROCEDURAL_NOTES `active` array, produce one-line summaries. List `pending_approval` notes separately for user review. Skip in **standalone** mode.

### 5. Assess handoff quality and relevance

Evaluate the handoff on two dimensions. Ask: "Does this handoff provide valuable background context for the current project or ongoing work?"

**`handoff_quality`** (good / fair / poor):
- **good** — structured, current, and actionable
- **fair** — present but partially outdated, incomplete, or loosely structured
- **poor** — empty, severely outdated, or for a completely unrelated project

**`handoff_relevance`** (high / partial / none):
- **high** — directly relates to the user's immediate message
- **partial** — relates to the same project or ongoing work, but not the immediate request
- **none** — no connection to the user's message or current project

**`reason`**: 1-line explanation of the assessment.

In standalone mode -> `handoff_quality: poor`, `handoff_relevance: none`, `reason: "standalone mode — no handoff"`.
If HANDOFF is NONE -> `handoff_quality: poor`, `handoff_relevance: none`, `reason: "no handoff present"`.

### 6. Check initiative

If INITIATIVE contains a trigger message (not NONE), note it for the report. In anon mode, omit initiative from the report.

### 7. Backlog highlights

From BACKLOG, produce a brief highlights section:
- Compute today's date. Show any items with `due` within the next 7 days.
- Show any items with `priority` == `"high"` (regardless of due date).
- If there are urgent/high-priority items, list them briefly: `- [id] title (due: date | priority)`.
- If nothing is urgent or high-priority, just note the total count, e.g. "9 open items, none urgent".
- If BACKLOG is NONE or empty (`[]`), output "No backlog items."
- Skip in **standalone** mode.

### 8. Compose output

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

**Sibling threads:** <summary from step 3, or omit if none>

**Backlog:** <highlights from step 7>
**Reminders:** <extracted reminders or "none">
**Next proactive save:** <SAVE_BOUNDARY value>
**Consolidation:** <CONSOLIDATION status>
**Debug:** <true/false>
**Tool calls:** 0 (no tools used)

=== EVAL_DATA ===
handoff_quality: <good/fair/poor from step 5>
handoff_relevance: <high/partial/none from step 5>
knowledge_fallback_items: <number of KNOWLEDGE_CONTEXT items surfaced, 0 if handoff existed or no knowledge available>
reason: <1-line string from step 5>
```

**Mode adjustments:**
- **anon:** Omit Handoff context, Reminders, and Initiative sections.
- **standalone:** Omit Handoff context, Reminders, Backlog, and Procedural notes sections.
- **Debug / Tool calls lines:** Include only when debug is true.

If INITIATIVE had a trigger, include it prominently at the top of the report.
