# Setup

How to install, update, and manage Agent Persona.

---

## Requirements

- **Cursor IDE** — Agent Persona is built for Cursor
- **A high-capability model** — Claude Opus 4.6 or equivalent. The system uses complex multi-step workflows that weaker models can't follow reliably.

## Install

```bash
cd /path/to/your-project
git clone https://github.com/anyapetrovskaya/agent-persona.git agent-persona
bash agent-persona/scripts/init.sh
```

That's it. Open the project in Cursor and say hi. The agent will introduce itself and start learning how you work.

## What Gets Created

| What | Where |
|------|-------|
| Agent Persona | `agent-persona/` in your project |
| Your data | `agent-persona/data/` — memory, knowledge, personality, everything |
| Cursor rule | `.cursor/rules/agent-persona.mdc` — activates the system |

Your data is yours — readable markdown and JSON files. Nothing is sent anywhere.

## Updating

Ask your partner: "update agent-persona" — they'll handle it. Your data stays untouched; only the framework files get updated.

## Exporting to Another Project

Ask your partner: "export to my-other-project" — they'll copy everything, including all your memories and preferences, to another project. Your partner in that project will know you from day one.

## First Session

1. Open the project in Cursor
2. Say hi
3. The agent starts with a friendly default personality — adjust anytime ("be more concise", "be more direct")
4. Memory builds up naturally over sessions
5. After your first "end of day," the agent consolidates what it learned

No configuration needed. Just talk naturally and the system adapts to you.
