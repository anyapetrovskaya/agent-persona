# agent-persona

Entry point documentation for the agent-persona system.

---

## What is agent-persona?

**agent-persona** is a drop-in system that gives Cursor's AI coding agent persistent memory and adaptable personality across chat sessions. Without it, every new chat starts from zero — the agent forgets prior conversations, preferences, and context. With agent-persona, the agent remembers what happened before, learns your preferences over time, and can adjust its communication style to match how you like to work.

---

## The core idea

The system works through a Cursor rule that orchestrates the main agent's behavior. The main agent **never touches files directly** — it delegates all file I/O to sub-agents. Each capability is a **task directory** under `tasks/` with a pipeline architecture:

1. **Main agent** runs `task.sh` via Shell (with any arguments)
2. `task.sh` stages arguments, gathers minimal context, and outputs a `spawn:` instruction
3. **Main agent** follows the spawn instruction — creates a sub-agent
4. **Sub-agent** reads `task.md` (instructions), runs `pre.sh` (context gathering), executes the task, then runs `post.sh` (result writing)

This means each capability is self-contained. Add, remove, or modify task directories without changing the orchestration logic.

---

## What happens during a session

### Session start

When a non-trivial conversation begins, the agent runs **conversation-start**. This loads context from prior sessions: the last handoff summary (from a named conversation or the default), personality settings (base persona + active preset), and procedural notes. If a named conversation is specified, that thread's context is loaded instead of the default. The knowledge base is not pre-loaded; it is retrieved on-demand via **query-knowledge** when the agent needs to recall something.

### Every turn

A background **per-turn-check** runs with the current time. It evaluates save timing and reminders. If reminders are due, the agent mentions them. If a save is due, or the user signals save/remember/prepare handoff/switching, or after substantial work, the agent triggers **prepare-handoff**. Each turn ends with a completion chime via `footer.sh`.

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
| **Tasks** | Task directories in `tasks/`. Each contains a pipeline: `task.sh` (entry), `task.md` (instructions), and optional `pre.sh`/`post.sh` scripts. The main agent runs `task.sh`; sub-agents handle the rest. |
| **Named conversations** | Persistent named threads in `data/conversations/`. Save, load, create, and list conversation threads. Loading a conversation forks it — future saves go to that thread. |
| **Session-scoped staging** | Each chat session gets a unique ID. Temporary files are namespaced under `.staging/<session-id>/` to prevent conflicts when multiple chats share a workspace. |

---

## Directory layout

```
agent-persona/
├── data/                        # Runtime data
│   ├── conversations/           # Named conversation threads
│   │   ├── _default.md          # Default conversation (fallback)
│   │   └── <name>.md            # Named threads
│   ├── episodic/                # Per-session episode JSON files
│   │   └── archived/            # Consolidated episodes
│   ├── knowledge/               # Knowledge store + memory graph
│   ├── personalities/           # Base persona + personality presets
│   ├── eval/                    # Evaluation outputs
│   ├── .staging/                # Temp files (session-scoped)
│   └── *.json / *.md            # Config, handoff, triggers, etc.
├── docs/                        # Documentation (you are here)
├── rules/                       # Cursor rule template
├── scripts/                     # Install, update, export, release utilities
└── tasks/                       # Task directories (pipeline architecture)
    ├── conversation-start/      # Load context at session start
    │   ├── task.sh              # Entry point (main agent runs this)
    │   ├── task.md              # Instructions for sub-agent
    │   ├── pre.sh               # Gather context
    │   └── post.sh              # (optional) Write results
    ├── prepare-handoff/         # Save episodic memory + handoff
    ├── manage-conversation/     # Named conversation management
    ├── per-turn-check/          # Per-turn timing, reminders, footer
    ├── query-knowledge/         # On-demand knowledge retrieval
    ├── apply-personality/       # Switch personality preset
    ├── reflect/                 # Self-evaluation
    ├── infer-knowledge/         # End-of-day knowledge consolidation
    └── ...                      # Other task directories
```

---

## Things to try

After a week or so of sessions, ask the agent how your working relationship has evolved. It draws on accumulated episodic memories and knowledge to generate a narrative of how things have changed over time.

Create named conversation threads to keep different topics organized: `new convo <name>`, `load convo <name>`, `list convos`.

---

## Further reading

| Doc | Description |
|-----|-------------|
| [architecture.md](architecture.md) | How orchestration and sub-agents work |
| [memory.md](memory.md) | Deep dive on the memory system |
| [personality.md](personality.md) | How personality adaptation works |
| [setup.md](setup.md) | Installation and configuration |
