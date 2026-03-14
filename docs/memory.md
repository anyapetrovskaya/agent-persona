# Memory

Agent Persona remembers your conversations, decisions, and preferences across sessions. Here's how it works from your perspective.

---

## The Problem It Solves

Without persistent memory, every AI chat starts from scratch. You repeat your preferences, re-explain your project, and re-establish context — every single time. Agent Persona eliminates that.

## Three Layers of Memory

### Recent Conversations

The agent keeps your recent conversation transcripts for a few sessions, so it can recall exactly what was said — not just a summary, but the actual exchange. This fades naturally as newer sessions replace older ones.

### Session Summaries

Each session produces a summary capturing the highlights: what was discussed, decisions made, what's in progress, and how the session went. These are more compact than full transcripts but richer than bare facts.

**Example:** After a session where you chose JWT over sessions for auth, the summary captures the decision, the reasoning, and the context.

### Long-Term Knowledge

Over time, the agent distills patterns from session summaries into lasting knowledge:

- Your preferences (communication style, tool choices, coding conventions)
- Project conventions (architecture, patterns, key decisions)
- Personal context (reminders, important dates)
- Relationship context (how you work together, what resonates)

Knowledge consolidation happens automatically at the end of each day.

## Forgetting

Memory naturally fades if it's not used or referenced — just like it does for people. Old one-off decisions drift away while important, frequently-referenced knowledge stays strong.

Just ask naturally. "What's fading?" shows items drifting away. "Remember this" or "pin this" keeps something permanently. "Forget this" archives it. "Bring back X" restores it. Nothing is permanently deleted.

## Conversations

Conversation threads let you maintain separate discussions on different topics. Each thread keeps its own context.

Just tell your partner what you want: "let's start a new conversation about X," "let's go back to the auth discussion," "save this conversation," or "what conversations do we have?"

## Living Documents

Living docs are reference documents that evolve over time. They represent the "current truth" on a topic — what you'd hand someone to get them up to speed.

They pair naturally with conversations: the conversation is the discussion history, the document is what the discussion produced.

Tell your partner: "create a doc about X," "update the architecture doc," "show me the roadmap doc," or "what docs do we have?"

## Email Import

You can bootstrap the agent's knowledge by importing your Gmail data (mbox format). This seeds the agent with information about your projects, contacts, and communication style from day one.

- One-time import — run it once, then work normally
- Fully local — your email never leaves your machine
- No raw content stored — only extracted facts and relationships make it into knowledge
