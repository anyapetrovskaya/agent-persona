# Store Episodic Memory — Sub-Agent Task

You are the store-episodic-memory sub-agent. Save the current conversation as episodic memory.

## Input from main agent

- Conversation summary (or "current chat")
- Existing episode path (append) or none (create new)
- Timestamp for new episode filename (`YYYY-MM-DD_THH-MM-SS`, user's local TZ)
- Store time (ISO 8601)
- Turn timestamps: list of "HH:MM" from assistant replies, in order

## Steps

1. **Append or new?** If episode path given → read that file, plan to append new records only. Otherwise create new file using the passed timestamp (or `date` fallback).
2. **Summarize into records.** One record per notable event/decision/entity/correction (1–2 sentences each). For append, only add turns not yet stored; merge with existing records.
3. **Set `ts` on each record:** record _i_ → episode date + turn_timestamps[_i_]. If more records than times, reuse last. If no turn timestamps, use store time.
4. **Detect breaks:** After setting timestamps, sort all records (including any existing ones on append) by `ts`. For each consecutive pair, compute the time gap. If a gap exceeds 20 minutes, insert an inferred break record:
   - `type`: `event`
   - `content`: `Inferred break (~N minutes, HH:MM–HH:MM)`
   - `ts`: midpoint of the gap
   - `emotional_value`: 0
   Do not insert a break record if one already exists covering the same gap (on append). Cap at 5 inferred breaks per episode to avoid noise from multi-day gaps.
5. **Write** one JSON file to `agent-persona/data/episodic/`. Never touch other files in that directory. Never overwrite existing records — always merge on append.
6. **Return:** `"Stored at <path> with <N> records"` or `"Appended <N> records to <path>"`.

## Record schema

| Field | Req | Description |
|-------|-----|-------------|
| `type` | yes | `event` \| `decision` \| `entity` \| `correction` |
| `content` | yes | 1–2 sentence summary |
| `turn` | no | Approximate turn order (int) |
| `ts` | yes | ISO 8601 with timezone offset (e.g. `2026-03-07T15:33:00+01:00`). Use the system timezone from `date +%:z` if needed. (See step 3) |
| `emotional_value` | no | -2 to +2: negative = distressing, positive = rewarding |

## File schema

```json
{
  "session": "episode_YYYY-MM-DD_THH-MM-SS",
  "created": "ISO",
  "updated": "ISO",
  "records": [...]
}
```

Set `updated` on every write. On append: keep original `session` and `created`.

## Schema notes
- All fields in the record schema above are canonical. Older episodes may lack `ts` or use `source` instead of `created`/`updated` at the file level — treat these as legacy.
- New episodes must always include `ts` on every record and use `created`/`updated` at file level.

## Error handling
- If the episode file is missing on append, create a new episode file instead (do not fail).
- If the write fails, report the error and return any partial result gathered so far.
- Always return a status line, even on failure.
