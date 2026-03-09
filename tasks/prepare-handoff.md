# Prepare Handoff — Sub-Agent Task

You are the prepare-handoff sub-agent. The user is switching chat and needs episodic + handoff saved.

## Input from main agent

- Conversation summary (topics, decisions, open questions)
- Current time (HH:MM) and timestamp
- Latest episode path (if one was already created this session), or none
- Turn timestamps (list of "— HH:MM" from replies)
- **End of day:** `true` or `false` (default `false`). When `true`, run infer-knowledge after the normal handoff steps.

## Steps

1. **Store episodic memory:** Read `agent-persona/tasks/store-episodic-memory.md` and execute. Use the conversation summary. Append to existing episode if path provided; otherwise create new. Note the resulting episode path and id.

2. **Write session handoff:** Read `agent-persona/tasks/session-handoff.md` and execute. Pass: conversation summary, `agent-persona/data/current_session_handoff.md`, current time, episode id from step 1.

3. **Update save boundary:** Compute the current 15-min boundary from current time (minutes 0–14→`:00`, 15–29→`:15`, 30–44→`:30`, 45–59→`:45`). Write it to `agent-persona/data/last_proactive_save.txt`.

4. **Eval logging:** Append an eval event to `agent-persona/data/eval/eval_log.json`. Read the file (create with `{"schema_version": 1, "events": []}` if missing), then append to the `events` array:
   ```json
   {
     "id": "evt_<ISO-timestamp>",
     "ts": "<ISO-timestamp-with-timezone>",
     "type": "session_summary",
     "session": "<episode id from step 1>",
     "data": {
       "corrections": "<count of records with type 'correction' in the episode>",
       "total_records": "<total records stored in step 1>",
       "episode_id": "<episode id from step 1>"
     }
   }
   ```
   If eval logging fails, skip silently — never fail the handoff because of eval.

5. **Proactive initiative** (optional): If context suggests user is switching chats, read `agent-persona/tasks/proactive-initiative.md` and execute with trigger=`before_handoff`, context=conversation summary. If a line is returned, include it.

6. **End-of-day consolidation** (only if end_of_day = `true`): Read `agent-persona/tasks/infer-knowledge.md` and execute. This runs the full consolidation pipeline (extract → merge → prune → write knowledge → build graph → archive → infer persona → suggest triggers). The user does not need to wait for this to complete.

7. **Git sync (push)** (only if configured): Read `agent-persona/config.json`. If `git_sync` is `true`, run:
   ```bash
   git add agent-persona/data/
   git commit -m "agent-persona session update"
   git push
   ```
   If `git_sync` is `false`, missing, or not present in config, skip. If the push fails, note in the report but don't fail the handoff.

## Error handling
- If any sub-task (episodic store, handoff write, save boundary, initiative, git sync) fails, continue with the remaining steps and note failures in the report.
- Never let a single failure abort the entire handoff process.
- Always return the report format below, marking failed steps with `FAILED: <reason>`.

## Report format

```
Episode: <path> (<N> records)
Handoff: agent-persona/data/current_session_handoff.md updated
Boundary: <HH:MM>
Initiative: <line or "none">
Consolidation: <ran / skipped>
Git sync: <pushed / skipped / FAILED: reason>
Reflection: <ran (summary) / skipped>
```
