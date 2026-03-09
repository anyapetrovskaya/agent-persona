# Personality System

This document describes how agent-persona adapts the AI agent's communication style to match your preferences. It covers the base persona, presets, adaptation flow, procedural notes, and learned triggers.

---

## 1. Why Personality Matters

Different users prefer different interaction styles. Some want terse, expert responses. Others want warmth and encouragement. Without a personality system, the agent uses a generic default that may not match your preferences.

Personality adaptation lets the agent:

- **Match your style** — Brief when you're in a hurry, detailed when you're exploring
- **Reduce friction** — Fewer "that's not what I meant" moments
- **Feel consistent** — The agent remembers how you like to work across sessions

---

## 2. Base Persona (`data/base_persona.json`)

The base persona is a set of numeric trait values (0–1 scale) that define the agent's default style.

**Traits include:**

- **warmth** — Friendly vs. neutral tone
- **verbosity** — Concise vs. detailed responses
- **humor** — Dry wit vs. serious
- **criticality** — Direct, challenging feedback vs. softer suggestions
- **encouragement** — Supportive vs. matter-of-fact
- **unbiased** — Neutral framing vs. opinionated

These values are **inferred from interaction patterns** by the `infer-base-persona` task. They evolve over time as the system learns what resonates with you — e.g., if you often ask for shorter answers, verbosity trends down.

---

## 3. Personality Presets (`personalities/`)

Presets are named style profiles that override or emphasize certain traits. Each preset is a markdown file describing the style and a directive the agent follows.

**Examples:**

| Preset | Style |
|--------|-------|
| **expert-laconic** | Brief, direct, dry humor |
| **concise-unbiased** | Brief, neutral; pros/cons, caveats |
| **bubbly-chatty** | Warm, verbose, encouraging |
| **critic** | High criticality, direct feedback |
| **supportive** | High warmth, high encouragement |

You can switch presets by telling the agent. For example:

- "Be more concise" → may trigger `expert-laconic` or a verbosity reduction
- "I need encouragement today" → may trigger `supportive`
- "Be direct, don't sugarcoat" → may trigger `critic`

The `apply-personality` task handles these requests and adjusts the active preset.

---

## 4. How Adaptation Works

**When you signal a different style:**

1. You say something like "be briefer" or "I prefer warmer responses"
2. The `apply-personality` task interprets your request and adjusts the active preset
3. The personality directive is loaded at `conversation-start` and shapes all responses for the session

**Over time:**

- `infer-base-persona` updates the base trait values based on what actually resonates
- The system distinguishes between:
  - **Explicit requests** — "be briefer" (immediate preset change)
  - **Inferred preferences** — patterns in your reactions (gradual base persona updates)

So a one-off "be concise today" affects the session; repeated preferences shape the long-term base.

---

## 5. Procedural Notes (`data/procedural_notes.json`)

Procedural notes are user-approved behavioral rules — a layer above personality. They encode preferences like:

- "Prefer library defaults over custom implementations"
- "Always explain trade-offs when suggesting changes"
- "Use TypeScript strict mode"

**Flow:**

1. The `suggest-learned-behavior` task proposes rules based on your patterns
2. You approve or reject them
3. Approved rules are stored in `procedural_notes.json`
4. They are applied every session alongside personality

These are explicit, user-verified rules, not inferred style tweaks.

---

## 6. Learned Triggers (`data/learned_triggers.json`)

Learned triggers are automated behaviors tied to specific events or patterns. They are more specific than procedural notes.

**Example:** After completing a task, the agent checks if there's a relevant follow-up action (e.g., "run tests" or "update docs") and offers it.

**How they work:**

- Stored in `data/learned_triggers.json`
- Keyed by trigger type (e.g., `task_complete`)
- The agent applies them when the matching event occurs

---

## Day-to-Day Usage

**To change style:** Tell the agent in natural language — "be more concise," "I need support," "be direct." The `apply-personality` task handles it.

**To add a rule:** When the agent suggests a learned behavior, approve it. It becomes a procedural note or trigger.

**To see what's active:** The personality directive and procedural notes are loaded at session start. Base persona and presets influence the default; your explicit requests override for the session.

**To reflect on your relationship:** After a week or so of sessions, you can ask the agent how your working relationship has evolved. It draws on accumulated episodic memories and knowledge to produce a narrative of how things have changed.

The system is designed to adapt to you over time while respecting your explicit choices.
