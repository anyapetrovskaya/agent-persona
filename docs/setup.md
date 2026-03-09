# agent-persona Setup Guide

Get agent-persona running in your project from scratch.

---

## 1. Prerequisites

- **Cursor IDE** — agent-persona is designed for Cursor and uses its rules system
- **A project or workspace** — a directory where you want the agent to operate (e.g. your codebase, notes, or any folder you work in)

---

## 2. Installation

Install agent-persona into a target project by running the install script from the agent-persona source (e.g. a repo checkout):

```bash
agent-persona/scripts/install.sh <target-path>
```

**Examples:**

```bash
# Install into your current project
agent-persona/scripts/install.sh .

# Install into a specific project
agent-persona/scripts/install.sh /path/to/my-project
```

The script:

- Copies the `agent-persona/` folder into the target project
- Creates the Cursor rule at `.cursor/rules/agent-persona.mdc`
- Seeds initial data on a fresh install (personality, knowledge, triggers)
- Adds `agent-persona/` to the target project's `.gitignore`

**Important:** You cannot install into the agent-persona source directory itself. The target must be a different project.

---

## 3. What Gets Installed

After installation, your target project will contain:

| Path | Contents |
|------|----------|
| `agent-persona/` | Framework and your data |
| `agent-persona/tasks/` | Task definitions the agent runs (conversation-start, per-turn-check, etc.) |
| `agent-persona/scripts/` | Install, update, export, and visualization scripts |
| `agent-persona/data/` | Episodic memory, knowledge graph, persona, triggers |
| `agent-persona/docs/` | Documentation |
| `agent-persona/personalities/` | Personality presets |
| `agent-persona/rules/` | Canonical rule files |
| `.cursor/rules/agent-persona.mdc` | Cursor rule that activates the system |

The Cursor rule tells the agent when to run tasks (e.g. at conversation start, per turn, when you say "save" or "remember"). Open the project in Cursor and the agent will use it automatically.

---

## 4. Updating

To update an existing installation with newer framework files (tasks, scripts, rules, docs) without touching your data:

```bash
agent-persona/scripts/update.sh --source <path-to-agent-persona-repo>
```

**Example:**

```bash
# From your project root (with agent-persona installed)
./agent-persona/scripts/update.sh --source /path/to/agent-persona-repo
```

The update script:

- Updates tasks, scripts, rules, docs, and default personalities
- **Does not modify** your episodic memory, knowledge, base persona, triggers, or session handoff
- Can remove files that no longer exist in the source
- Supports `--dry-run` to preview changes without applying them

---

## 5. Exporting

Export agent-persona (framework + your data) to another project. Use this to clone your setup and memories to a new workspace.

```bash
./agent-persona/scripts/export-to-project.sh <target-project-dir>
```

**Example:**

```bash
# From a project that has agent-persona installed
./agent-persona/scripts/export-to-project.sh /path/to/other-project
```

**Flags:**

- `--force` — Overwrite existing `agent-persona/` in the target without prompting
- `--git-init` — Initialize a git repo in the exported `data/` directory

**What it produces:** A full copy of `agent-persona/` (tasks, scripts, rules, docs, personalities, and data) plus the Cursor rule in the target project. The target gets your personality, knowledge, and episodic memory.

---

## 6. First Session

After installation:

1. **Open the project in Cursor** — The agent loads the rule and starts using agent-persona.

2. **Default personality** — The agent starts with a "supportive" persona. Traits (warmth, verbosity, etc.) are set to defaults and will adjust as you interact.

3. **No prior memory** — Episodic memory and knowledge are empty. They build up over sessions as you work and the agent runs its tasks.

4. **Knowledge consolidation** — After a few sessions (especially when you say things like "good night" or "done for today"), the agent runs knowledge inference and starts consolidating what it learned into the knowledge graph.

5. **Adjust personality** — Tell the agent your preferences (e.g. "be more concise" or "I prefer a critical tone"). It will apply personality changes and remember them.

**Next step:** Open the project in Cursor and say hi.
