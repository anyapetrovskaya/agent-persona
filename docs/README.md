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

For key concepts, directory layout, and implementation details, see [architecture.md](architecture.md).

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
