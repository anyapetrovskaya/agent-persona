# Conversation Start — Sub-Agent Task

You are the startup sub-agent. Execute all steps and return a single compact report.

## Input from main agent

The main agent passes: **user's first message** (for mode detection) and **current time** (HH:MM).

**Parallel reads:** Read ALL files listed in each batch using multiple Read tool calls in a SINGLE response. Do not read them one at a time.

## Steps

### 1. Batch 1 — config, personality source, base persona

Read in parallel:
- `agent-persona/config.json`
- `agent-persona/data/active_personality.txt`
- `agent-persona/data/base_persona.json`

**Detect mode** from the user message: "anon mode" → **anon**, "standalone mode" → **standalone**, "debug on" → note debug flag, else **default**.
- **anon:** Reads OK, no writes. Skip consolidation, proactive-initiative, suggest-learned-behavior.
- **standalone:** Skip handoff. Episodic: own file only.

**Resolve personality:**
- If `active_personality.txt` has content → personality = that id.
- Else → personality = `default_mode` from `base_persona.json`.
- If `base_persona.json` missing → personality = `expert-laconic`.

**Git sync:** If `config.json` has `git_sync: true`, run `git pull` before continuing to batch 2. Otherwise skip silently.

### 2. Batch 2 — session data, personality file, knowledge

Read in parallel (skip items as noted):
- `agent-persona/data/current_session_handoff.md` — skip if **standalone**
- `agent-persona/personalities/<personality>.md` — using personality id from step 1
- `agent-persona/data/procedural_notes.json`
- `agent-persona/data/knowledge/knowledge.json` — skip if **anon**
- `agent-persona/data/last_proactive_save.txt`
- `agent-persona/data/learned_triggers.json` — skip if **anon**
- `agent-persona/data/eval/eval_log.json`

### 3. Process loaded data

**Personality directive:** Extract directive (tone, verbosity, role lines) from `<personality>.md`. Note base traits from `base_persona.json`.

**Handoff:** If loaded, extract: current topic/goal (1–2 lines), key decisions (bullet list), latest episode id, reminders (with times). If missing or empty → "No previous session."

**Procedural notes:** Collect notes with status `active` as behavioral guidance. Collect `pending_approval` notes separately for user approval.

**Consolidation:** Compare `last_infer_date` from `knowledge.json` to today. Consolidation is due only if `last_infer_date` is more than 1 day old (end-of-day consolidation was missed). Skip if **anon** or if current/missing.

**Proactive save boundary:** From `last_proactive_save.txt` (single line like `18:15`), compute the current 15-min boundary:
- Minutes 0–14 → `:00`, 15–29 → `:15`, 30–44 → `:30`, 45–59 → `:45`
- If file missing or stored boundary < current boundary → next save = current boundary + 15 min.
- Otherwise → next save = stored boundary + 15 min.

**Proactive initiative:** If not **anon** and `learned_triggers.json` has a `conversation_start` trigger with a message, include it.

### 4. Eval logging

Append to `agent-persona/data/eval/eval_log.json` (create with `{"schema_version": 1, "events": []}` if missing):
```json
{
  "id": "evt_<ISO-timestamp>",
  "ts": "<ISO-timestamp-with-timezone>",
  "type": "handoff_check",
  "data": {
    "handoff_existed": true or false,
    "items_referenced": "<count of items noted from handoff>",
    "self_assessed_useful": true or false,
    "mode": "<anon|standalone|default>"
  }
}
```
Self-assess usefulness: `true` if handoff contained context relevant to the user's first message; `false` if empty, missing, or unrelated. If **standalone**, set both `handoff_existed` and `self_assessed_useful` to `false`. If eval logging fails, skip silently.

### 5. Return report

Return EXACTLY this structure (omit sections only if truly empty):

```
**Mode:** <anon|standalone|default>
**Personality:** <mode id>
**Directive:** <2–3 line personality directive, blended with base traits>
**Base traits:** <key=value pairs, e.g. warmth=0.4 humor=0.65>

**Procedural notes:** <count active; one-line summary of each, or "none">
**Pending approval:** <list of pending note contents for user to approve/reject, or "none">

**Handoff context:**
<2–3 line summary of last session's topic, key decisions>

**Reminders:** <"none" or list with times>
**Next proactive save:** HH:MM
**Consolidation:** up to date | ran (summary: +N/-N items, base persona: <mode>)
**Tool calls:** <N> (count of Read/Write/Shell tool calls you made)
```

If mode is anon, add: `**Anon:** reads OK, no writes.`

Keep the entire report under 30 lines.
If `debug: true` was passed, include the Tool calls line. Otherwise omit it.
