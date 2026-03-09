# Agent Persona

A collaborator that remembers. Agent Persona gives your AI assistant long-term memory, adaptive personality, and the ability to learn how you work — across sessions, across days, across projects.

## Getting Started

### Install

```bash
git clone https://github.com/anyapetrovskaya/agent-persona.git
cd agent-persona
./scripts/install.sh ~/path/to/your/project
```

### First Conversation

Open your project in Cursor and say hi. That's it.

 Agent Persona will introduce itself and start learning how you work. No configuration needed — just talk naturally, like you would with a colleague.

### Switching Communication Style

Agent Persona starts warm and encouraging. You can change this anytime:

- "Be more concise" or "switch to expert-laconic" — direct and efficient
- "Be more supportive" — warm and encouraging (default)
- "Be more critical" — challenges your assumptions
- Or describe what you want: "be brief but funny"

## How It Works

Agent Persona remembers your conversations and learns from them:

- **Episodic memory** — what happened in each session
- **Durable knowledge** — patterns, preferences, and facts extracted over time
- **Personality calibration** — adapts tone and style to how you like to work
- **Proactive initiative** — suggests next steps, catches things you might miss
- **Session continuity** — picks up exactly where you left off

Everything is stored locally in `agent-persona/data/`. You own your data.

## Directory Layout

| Path | What it is |
|------|-----------|
| `rules/` | The main rule file (copied to `.cursor/rules/` during install) |
| `tasks/` | Task definitions — the system's behavior, written in plain English |
| `scripts/` | Install, update, export, and visualization tools |
| `docs/` | Design documentation for the system's architecture |
| `data/` | Your personal data — memory, knowledge, personality, preferences |
| `personalities/` | Communication style definitions |

## Managing Your Data

### Version Control

Your data lives in `agent-persona/data/` and can be its own git repository:

```bash
cd your-project/agent-persona/data
git remote add origin git@github.com:you/my-agent-memory.git
git push -u origin main
```

### Export to Another Project

Take your memory and personality to a different project:

```bash
./agent-persona/scripts/export-to-project.sh /path/to/other-project
```

### Update the Framework

Get the latest improvements without touching your data:

```bash
./agent-persona/scripts/update.sh --source /path/to/agent-persona-release
```

Or just ask your agent: "Could you update agent-persona for me?"

## Privacy

All data stays on your machine. Nothing is sent anywhere. The knowledge, personality, and memory files in `data/` are yours — readable, portable, and deletable at any time.

---

*Think of Agent Persona as a colleague who gets better at working with you over time. Not a tool you configure — a relationship you build.*
