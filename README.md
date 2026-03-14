# Agent Persona

An AI partner that starts generic and becomes increasingly *yours* over time.

## What Is It?

Agent Persona gives your AI a memory. It remembers your conversations, learns how you like to communicate, and keeps track of things you care about — so every time you talk, it picks up right where you left off.

Think of it as the difference between talking to a stranger every day versus having a partner who actually knows you.

## Getting Started

```bash
cd /path/to/your-project
git clone https://github.com/anyapetrovskaya/agent-persona.git agent-persona
bash agent-persona/scripts/init.sh
```

Open the project in Cursor and say hi. That's it — no configuration needed.

**Note:** Works best with a high-capability model like Claude Opus 4.6.

## How to Use It

Just talk naturally. Your partner remembers things automatically.

- **Adjust the personality** — "be more concise," "be warmer," "be brief but funny"
- **Track tasks** — "add to backlog: call the dentist"
- **Organize topics** — "let's start a new conversation about the redesign"
- **Create reference docs** — "create a doc about our architecture decisions"
- **Say good night** — when you're done for the day, say so. Your partner processes and consolidates everything — like sleeping on it.

Say `help` anytime to see what's available.

## Your Data

Everything lives in `agent-persona/data/`. It's all readable files — markdown and JSON. Nothing is sent anywhere. Your data is yours.

To copy your partner to another project, just ask: "export to my-other-project."

To update, just ask: "update agent-persona."

## Learn More

See [docs/](docs/overview.md) for how memory, personality, and forgetting work under the hood.
