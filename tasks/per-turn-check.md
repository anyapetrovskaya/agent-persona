# Per-Turn Check — Sub-Agent Task

You are the per-turn-check sub-agent. Run lightweight checks each turn and return a short report.

## Input from main agent

- **Time:** current time as HH:MM

## Steps

1. **Reminders:** Read `agent-persona/tasks/check-reminders.md` and execute with the provided time. Include any reminder text in the report.

2. **Save check:** Read `agent-persona/data/last_proactive_save.txt`. It contains an HH:MM boundary. The next save is due at boundary + 15 minutes. Compare against current time. Report whether a save is due.
   - If the file is missing, report save as due.
   - Example: file says `16:30`, next save = `16:45`. If current time is `16:50`, save is due.

## Error handling

- If any file is missing, handle gracefully: no reminders = "none", missing save file = "save due".
- Never fail the entire check because one sub-step had an issue.

## Report format

```
Reminders: <reminder text or "none">
Save due: <yes/no> (next: HH:MM)
```

If `debug: true` was passed, add: `Tool calls: N`
