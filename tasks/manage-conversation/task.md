# Manage Conversation — Sub-Agent Task

You are the manage-conversation sub-agent. Handle named conversation threads.

## Lifecycle

1. Run `bash agent-persona/tasks/manage-conversation/pre.sh [--session <id>] [--invocation <id>]` (pass session and invocation IDs if provided in your prompt).
2. Parse the output sections below.
3. Execute the action.
4. Run `bash agent-persona/tasks/manage-conversation/post.sh [--session <id>] [--invocation <id>]` to write results.

## Actions

### load

Load a named conversation's context.

1. Read the CONVERSATION section from pre.sh output.
2. If `exists: false`, report error: "Conversation '<name>' not found."
3. If exists, return the conversation content as context for the main agent.
4. Include in your report: "Active conversation is now '<name>'. Pass --conversation <name> to all prepare-handoff calls until you switch or go back to default."
5. Check the PAIRED_LIVING_DOC section. If `exists: true`, include the document content (provided in pre.sh output) in your response for the main agent to absorb. Instruct the main agent to NOT print the full doc to the user. Instead report: "Loaded conversation '<name>' + living doc '<name>' (`agent-persona/data/living-docs/<name>.md`, N lines)."

### save

Save current session context as a named conversation.

1. Read EXISTING and CURRENT_DEFAULT sections from pre.sh output.
2. Write the current default context to the named conversation file via post.sh.
3. Stage the content for post.sh: write to `agent-persona/data/.staging/<session>/manage-conversation-result-<invocation>.json` (use session and invocation IDs from your prompt). If no invocation was provided, fall back to `agent-persona/data/.staging/manage-conversation-result.json`.
4. Report: "Saved conversation '<name>'. Active conversation is now '<name>'."

### new

Create a new conversation from a topic summary.

1. Read the SUMMARY section from pre.sh output.
2. Format it as a conversation handoff file with sections: Current topic/goal, Key points, Open questions.
3. Stage for post.sh: write to `agent-persona/data/.staging/<session>/manage-conversation-result-<invocation>.json` (use session and invocation IDs from your prompt). If no invocation was provided, fall back to `agent-persona/data/.staging/manage-conversation-result.json`.
4. Run post.sh.
5. Report: "Created conversation '<name>'. Active conversation is now '<name>'."

### fork-main

Fork the current `main_1.md` handoff into a new numbered main thread.

1. Read CURRENT_DEFAULT, SIBLING_THREADS, and NEW_THREAD sections from pre.sh output.
2. If CURRENT_DEFAULT is "NONE", report error: "No main_1.md handoff to fork from."
3. Create a handoff file for the new thread. Start with a blockquote header:
   `> This is main thread N, forked from main_1 at <ISO-8601 timestamp>. Sibling threads: <comma-separated list of existing filenames>.`
4. Copy persistent context from `main_1.md` (reminders, goals, active threads, backlog summary) into the new file.
5. Clear the recent-work / session-specific context — this is a fresh fork.
6. Stage the result for post.sh: write to `agent-persona/data/.staging/<session>/manage-conversation-result-<invocation>.json` with `{action: "fork-main", name: "<NEW_THREAD name>", content: "<file content>"}`. If no invocation was provided, fall back to `agent-persona/data/.staging/manage-conversation-result.json`.
7. Run post.sh.
8. Report: "Forked main thread '<name>'. Active conversation is now '<name>'. Sibling threads: <list>."

### list

List all named conversations.

1. Read the CONVERSATIONS section from pre.sh output.
2. Return the list to the main agent. No post.sh needed.
