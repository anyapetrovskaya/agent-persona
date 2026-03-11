# Agent Persona

*Think of Agent Persona as a partner who gets better at working with you over time. Not a tool you configure — a relationship you build.*

## Getting Started

### Install into a project

```bash
cd /path/to/your-project
git clone https://github.com/anyapetrovskaya/agent-persona.git agent-persona
bash agent-persona/scripts/init.sh
```

That's it — no standalone or web subsections. Just one install method.

## First Conversation

Open the project in Cursor and say hi.

 Agent Persona will introduce itself and start learning how you work. No configuration needed — just talk naturally.

### Switching Communication Style

You can change the tone anytime:

- "Be more concise" — direct and efficient
- "Be more supportive" — warm and encouraging
- "Be more critical" — challenges your assumptions
- Or describe what you want: "be brief but funny"

## Recommended Setup

Agent Persona works best with **high-capability models** (e.g. Claude Opus 4.6). The system relies on complex rule-following, sub-agent orchestration, and multi-step task execution — weaker models may not follow the full workflow reliably.

## Managing Your Data

All data lives in `agent-persona/data/` — memory, knowledge, personality, preferences. You own it.

### Export to another project

```bash
bash agent-persona/scripts/export-to-project.sh /path/to/other-project
```

### Update the framework

Get the latest improvements without touching your data. The script downloads the latest release, syncs framework files, and re-runs init.

```bash
bash agent-persona/scripts/update.sh
```

Or just ask your agent: "Could you update agent-persona for me?"

## Privacy

All data stays on your machine (or your private repo if using Cursor Web). Nothing is sent to third parties. The knowledge, personality, and memory files in `data/` are yours — readable, portable, and deletable at any time.

## Documentation

For architecture details, directory layout, and design decisions, see [docs/](docs/README.md).
