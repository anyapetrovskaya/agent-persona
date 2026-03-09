# Check Reminders — Sub-Agent Task

1. **Input:** Current time (HH:MM). Read `agent-persona/data/current_session_handoff.md`.
2. If no "Reminder for user" section with times, return empty.
3. Parse times to 24h format. If current time is within 5 min of any listed time, return that reminder's text (one line).
4. Otherwise return empty.
