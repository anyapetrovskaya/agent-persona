# agent-persona

Entry point documentation for the agent-persona system.

---

## What is agent-persona?

**agent-persona** is a drop-in system that gives Cursor's AI coding agent persistent memory and adaptable personality across chat sessions. Without it, every new chat starts from zero — the agent forgets prior conversations, preferences, and context. With agent-persona, the agent remembers what happened before, learns your preferences over time, and can adjust its communication style to match how you like to work.

---

## The core idea

The system works through a Cursor rule that orchestrates the main agent's behavior. The main agent **never touches files directly** — it delegates all file I/O to sub-agents that read task files and execute them. This architecture means the system is modular: each capability (loading context, saving memory, checking reminders, applying personality) is a standalone task file. Add, remove, or modify tasks without changing the orchestration logic.

---

## What happens during a session

### Session start

When a non-trivial conversation begins, the agent runs **conversation-start**. This loads context from prior sessions: the last handoff summary, personality settings (base persona + active preset), and procedural notes. The knowledge base is not pre-loaded; it is retrieved on-demand via **query-knowledge** when the agent needs to recall something. The returned report becomes session context.

### Every turn

A background **per-turn-check** runs with the current time. It evaluates reminders (e.g., "ask about X later") and save timing. If reminders are due, the agent mentions them. If a save is due, or the user signals save/remember/prepare handoff/switching, or after substantial work, the agent triggers **prepare-handoff**.

### Periodically

The agent saves what's happened so far as **episodic memory** — a snapshot of the session (what was discussed, what was decided, what's in progress).

### Session end / end of day

When the user signals they're done ("good night", "logging off", "done for today", "wrapping up"), the agent runs **prepare-handoff** with `end_of_day: true`. This performs the normal save, then triggers **infer-knowledge** — consolidating durable facts and preferences from episodes into the long-term knowledge base. The user can close the chat; consolidation runs in the background.

---

## Key concepts

| Concept | Definition |
|--------|------------|
| **Episodic memory** | Per-session snapshots: what happened, what was discussed, what was decided. Stored as JSON episodes, archived when superseded. |
| **Knowledge** | Consolidated facts and preferences extracted from many sessions. Durable, queryable. Grows via infer-knowledge at end-of-day. |
| **Base persona** | Numeric trait values (warmth, verbosity, humor, etc.) that define the agent's default communication style. |
| **Personality presets** | Named styles like "expert-laconic" or "bubbly-chatty". User can request a different tone; **apply-personality** switches the preset. |
| **Procedural notes** | User-approved behavioral rules. Things the agent should always or never do, learned from feedback. |
| **Tasks** | Modular task files in `tasks/`. Sub-agents read them and execute. The main agent spawns tasks; it does not read or edit files directly. |

---

## Directory layout

```
agent-persona/
├── data/                    # Runtime data (episodic, knowledge, config)
│   ├── episodic/            # Per-session episode JSON files
│   │   └── archived/        # Superseded episodes
│   ├── knowledge/           # Consolidated facts, preferences, memory graph
│   ├── personalities/       # Base persona + presets
│   ├── eval/                # Evaluation outputs
│   └── *.json               # Config: learned_triggers, last handoff, etc.
├── docs/                    # Documentation (you are here)
├── rules/                   # The Cursor rule (agent-persona.mdc)
├── scripts/                 # Utilities
│   ├── install.sh           # Install into a project
│   ├── update.sh            # Update from source
│   ├── export-to-project.sh # Export agent template
│   └── visualize-*.py       # Memory graph / timeline visualization
└── tasks/                   # Task files (sub-agents execute these)
    ├── conversation-start.md
    ├── per-turn-check.md
    ├── prepare-handoff.md
    ├── store-episodic-memory.md
    ├── infer-knowledge.md
    ├── query-knowledge.md
    ├── apply-personality.md
    └── ...                  # Other capabilities
```

---

## Things to try

After a week or so of sessions, ask the agent how your working relationship has evolved. It draws on accumulated episodic memories and knowledge to generate a narrative of how things have changed over time.

---

## Further reading

| Doc | Description |
|-----|-------------|
| [architecture.md](architecture.md) | How orchestration and sub-agents work |
| [memory.md](memory.md) | Deep dive on the memory system |
| [personality.md](personality.md) | How personality adaptation works |
| [setup.md](setup.md) | Installation and configuration |
