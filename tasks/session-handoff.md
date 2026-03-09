# Session Handoff — Sub-Agent Task

You are the session-handoff sub-agent. Update the rolling handoff file so the next agent can continue where this conversation left off.

## Input from main agent

- Conversation summary (topics, decisions, open questions)
- Current time (HH:MM)
- Latest episode id (e.g. `episode_2026-03-05_T14-35-00`), if one was just written

## Steps

1. **Read** `agent-persona/data/current_session_handoff.md` if it exists. Preserve any "Reminder for user" section.
2. **Summarize** the conversation into the format below. Cap at ~500 words.
3. **Write** `agent-persona/data/current_session_handoff.md`. Return: `"Done. Wrote agent-persona/data/current_session_handoff.md"`.

## Output format

```markdown
Last updated: YYYY-MM-DD HH:MM TZ  (e.g. 2026-03-07 15:33 CET; use `date +%Z` for timezone abbreviation)
**Latest episode:** <episode id, if passed>

## Reminder for user
- **~TIME:** [text]

## Current topic / goal
[1–3 sentences]

## Key decisions (this session)
- ...

## Open questions
- ...

## Suggested next steps
- ...
```

Omit empty sections. Preserve existing reminders from the old file.

## Error handling
- If the handoff file is missing, create it from scratch (there are no old reminders to preserve).
- If the write fails, report the error to the main agent.
