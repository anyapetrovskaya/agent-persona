# Agent-Persona Architecture

Agent-persona is a system that gives Cursor AI agents **persistent memory** and **adaptable personality**. This document describes how it works under the hood.

---

## 1. Orchestration Model

The system is driven by a single Cursor rule file: `rules/agent-persona.mdc`. This rule gets loaded into every chat session and tells the main agent what to do and when.

The main agent acts as an **orchestrator**. It never reads or writes files directly. Instead, it spawns **sub-agents** (using Cursor's Task tool with `generalPurpose` type) that perform all file I/O. This is a hard constraint enforced by the rule — the main agent delegates all disk operations to sub-agents.

**How a task is invoked:**

1. Main agent runs `task.sh` via Shell (e.g., `bash agent-persona/tasks/conversation-start/task.sh --session abc123`)
2. `task.sh` stages arguments, performs any setup, and prints a `spawn:` instruction to stdout
3. Main agent follows the spawn instruction — creates a sub-agent with the specified prompt
4. Sub-agent reads `task.md`, runs `pre.sh` (if present), executes the task, then runs `post.sh` (if present)

The main agent does **not** directly say "Read tasks/X.md" — it always runs `task.sh` first and follows the returned spawn instruction.

---

## 2. Why Sub-Agents?

Several design reasons drive this architecture:

- **Context isolation** — Each sub-agent receives only the context it needs for its task. A task that writes episodic memory doesn't need the full conversation history; it gets the episode data and writes it. This keeps each operation focused.

- **Modularity** — Capabilities are defined as task directories under `tasks/`. Adding a new capability means adding a new directory with `task.sh`, `task.md`, and optional scripts. No changes to the orchestrator's core logic.

- **Main agent focus** — The main agent's context stays centered on the conversation. It doesn't accumulate file contents, schemas, or implementation details. It decides *when* to call tasks and *what* to pass; the tasks handle the details.

- **Cost efficiency** — Sub-agents can use faster or cheaper models for routine operations (e.g., saving JSON, formatting handoffs). The main agent can reserve a more capable model for conversational reasoning.

---

## 3. Task System

Each capability is a **task directory** under `tasks/` with a pipeline architecture:

### Pipeline components

| Component | Role |
|-----------|------|
| `task.sh` | Entry point. Main agent runs this via Shell. Accepts args (e.g., `--conversation mythread`, `--session abc123`), stages them as JSON in `.staging/`, and outputs a `spawn:` instruction to stdout. |
| `task.md` | Instructions for the sub-agent. Describes what to do, what files to read/write, and how to format output. |
| `pre.sh` | (optional) Run by the sub-agent before main work. Gathers context, reads staged args from `.staging/`, assembles data the sub-agent needs. |
| `post.sh` | (optional) Run by the sub-agent after main work. Writes results to disk — episodes, handoff files, knowledge updates, etc. |

### Current tasks

| Task | Purpose |
|------|---------|
| **conversation-start** | Loads prior context, personality, named conversation at session start |
| **per-turn-check** | Per-turn timing, save checks, reminders; includes `footer.sh` for completion chime |
| **prepare-handoff** | Saves episodic memory and session handoff (supports named conversations) |
| **manage-conversation** | Named conversation management: save, load, new, list |
| **query-knowledge** | On-demand knowledge retrieval |
| **apply-personality** | Adjusts personality based on user feedback |
| **reflect** | Self-evaluation and improvement suggestions |
| **infer-knowledge** | End-of-day consolidation: episodes → durable knowledge |
| **infer-base-persona** | Derives base persona trait values from interaction history |
| **suggest-learned-behavior** | Proposes procedural notes from observed patterns |
| **build-memory-graph** | Generates knowledge graph visualization |
| **proactive-initiative** | Context-aware suggestions based on learned triggers |
| **generate-narrative** | Creates human-readable relationship/memory narratives |
| **memory-diff** | Shows what changed between saves |
| **toggle-debug** | Enables/disables debug output |

---

## 4. Session Lifecycle

```
Chat opens
    │
    ▼
conversation-start  ← Load prior context, personality, named conversation
    │                  (includes per-turn-check internally)
    │
    ▼
┌─────────────────────────────────────────┐
│  [User turns + per-turn-check]          │
│  • Per-turn-check runs every response   │
│  • Triggers: save timing, reminders     │
│  • footer.sh runs at end of each turn   │
└─────────────────────────────────────────┘
    │
    ▼
prepare-handoff  ← On save due, user says "save", or end-of-day
    │               (saves to named conversation if one is active)
    ▼
[end-of-day only: infer-knowledge consolidation]
    │
    ▼
Chat closes
```

**Triggers:**

- **conversation-start** — First non-trivial turn in a new chat. Can load a specific named conversation or fall back to `_default.md`.
- **per-turn-check** — Every response; uses current time. Included in conversation-start's first run.
- **prepare-handoff** — When save is due, user says "save"/"remember"/"prepare handoff", after substantial work, or at end-of-day (which also triggers infer-knowledge consolidation).
- **manage-conversation** — User says "save convo", "load convo", "new convo", or "list convos".

---

## 5. Data Flow

Data moves through the system as follows:

1. **Episodic memories** — Saved per-session to `data/episodic/`. Each session produces one or more episode JSON files. These are raw snapshots of what happened.

2. **End-of-day consolidation** — When the user signals end-of-day (e.g., "good night", "done for today"), `prepare-handoff` runs, then `infer-knowledge` extracts patterns, preferences, and facts into `data/knowledge/knowledge.json`.

3. **Archival** — Old episodes move to `data/episodic/archived/` to keep the active episodic folder manageable.

4. **Visualization** — Knowledge can be rendered as a graph at `data/knowledge/memory_graph.html` (and related 3D/timeline views) for inspection.

5. **Handoff files** — Named conversation threads live in `data/conversations/`. The active thread (e.g., `data/conversations/myproject.md` or `data/conversations/_default.md`) bridges sessions — `conversation-start` loads the relevant thread when a new chat opens.

6. **Session-scoped staging** — Each chat session gets a unique ID. Task arguments, intermediate results, and temporary files are namespaced under `data/.staging/<session-id>/` to prevent conflicts when multiple chats share a workspace.

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

*Technical but approachable. For implementation details, see the task directories in `tasks/`.*
