# Agent-Persona Architecture

Agent-persona is a system that gives Cursor AI agents **persistent memory** and **adaptable personality**. This document describes how it works under the hood.

---

## 1. Orchestration Model

The system is driven by a single Cursor rule file: `rules/agent-persona.mdc`. This rule gets loaded into every chat session and tells the main agent what to do and when.

The main agent acts as an **orchestrator**. It never reads or writes files directly. Instead, it spawns **sub-agents** (using Cursor's Task tool with `generalPurpose` type) that perform all file I/O. This is a hard constraint enforced by the rule — the main agent delegates all disk operations to sub-agents.

**Spawn format:** `"Read agent-persona/tasks/<name>.md and execute. <args>"`

---

## 2. Why Sub-Agents?

Several design reasons drive this architecture:

- **Context isolation** — Each sub-agent receives only the context it needs for its task. A task that writes episodic memory doesn't need the full conversation history; it gets the episode data and writes it. This keeps each operation focused.

- **Modularity** — Capabilities are defined in task files under `tasks/`. Adding a new capability means adding a new task file and a rule to invoke it. No changes to the orchestrator's core logic.

- **Main agent focus** — The main agent's context stays centered on the conversation. It doesn't accumulate file contents, schemas, or implementation details. It decides *when* to call tasks and *what* to pass; the tasks handle the details.

- **Cost efficiency** — Sub-agents can use faster or cheaper models for routine operations (e.g., saving JSON, formatting handoffs). The main agent can reserve a more capable model for conversational reasoning.

---

## 3. Task System

Each capability is defined as a markdown task file in `tasks/`. When the main agent needs to perform an operation, it spawns a sub-agent with:

> Read agent-persona/tasks/[name].md and execute. [args]

The task file contains all instructions for that operation. Key tasks:

| Task | Purpose |
|------|---------|
| **conversation-start** | Loads prior context, personality, and reminders when a new chat begins |
| **per-turn-check** | Runs each turn; checks save timing and reminders |
| **prepare-handoff** | Saves episodic memory and session context for the next session |
| **store-episodic-memory** | Writes a session snapshot to JSON |
| **infer-knowledge** | Consolidates episodes into durable knowledge (patterns, preferences, facts) |
| **query-knowledge** | Retrieves relevant knowledge for a user question |
| **apply-personality** | Adjusts personality based on user feedback |
| **infer-base-persona** | Derives trait values from interaction history |
| **reflect** | Self-evaluation and improvement suggestions |
| **suggest-learned-behavior** | Proposes new procedural notes from patterns |
| **build-memory-graph** | Creates graph representation of knowledge |
| **check-reminders** | Scans for upcoming reminders |
| **eval-baseline** / **eval-report** | Evaluation and benchmarking |
| **proactive-initiative** | Suggests actions based on learned triggers |
| **generate-narrative** | Creates human-readable memory summaries |
| **memory-diff** | Shows what changed between saves |
| **session-handoff** | Transfers context between sessions |

---

## 4. Session Lifecycle

```
Chat opens
    │
    ▼
conversation-start  ← Load prior context, personality, reminders
    │
    ▼
┌─────────────────────────────────────────┐
│  [User turns + per-turn-check]          │
│  • Per-turn-check runs every response   │
│  • Triggers: reminders, save timing     │
└─────────────────────────────────────────┘
    │
    ▼
prepare-handoff  ← On save due, user says "save", or end-of-day
    │
    ▼
Chat closes
```

**Triggers:**

- **conversation-start** — First non-trivial turn in a new chat
- **per-turn-check** — Every response; uses current time
- **prepare-handoff** — When save is due, user says "save"/"remember"/"prepare handoff", after substantial work, or at end-of-day (which also triggers infer-knowledge consolidation)

---

## 5. Data Flow

Data moves through the system as follows:

1. **Episodic memories** — Saved per-session to `data/episodic/`. Each session produces one or more episode JSON files. These are raw snapshots of what happened.

2. **End-of-day consolidation** — When the user signals end-of-day (e.g., "good night", "done for today"), `prepare-handoff` runs, then `infer-knowledge` extracts patterns, preferences, and facts into `data/knowledge/knowledge.json`.

3. **Archival** — Old episodes move to `data/episodic/archived/` to keep the active episodic folder manageable.

4. **Visualization** — Knowledge can be rendered as a graph at `data/knowledge/memory_graph.html` (and related 3D/timeline views) for inspection.

5. **Handoff file** — `data/current_session_handoff.md` bridges sessions. It summarizes the last session so `conversation-start` can load it when a new chat opens.

---

*Technical but approachable. For implementation details, see the task files in `tasks/`.*
