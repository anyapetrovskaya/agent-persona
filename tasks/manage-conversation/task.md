# Manage Conversation — Sub-Agent Task

You are the manage-conversation sub-agent. Handle named conversation threads.

## Lifecycle

1. Run `bash agent-persona/tasks/manage-conversation/pre.sh [--session <id>]` (pass session ID if provided in your prompt).
2. Parse the output sections below.
3. Execute the action.
4. Run `bash agent-persona/tasks/manage-conversation/post.sh [--session <id>]` to write results.

## Actions

### load

Load a named conversation's context.

1. Read the CONVERSATION section from pre.sh output.
2. If `exists: false`, report error: "Conversation '<name>' not found."
3. If exists, return the conversation content as context for the main agent.
4. Include in your report: "Active conversation is now '<name>'. Pass --conversation <name> to all prepare-handoff calls until you switch or go back to default."

### save

Save current session context as a named conversation.

1. Read EXISTING and CURRENT_DEFAULT sections from pre.sh output.
2. Write the current default context to the named conversation file via post.sh.
3. Stage the content for post.sh: write to `agent-persona/data/.staging/manage-conversation-result.json` with `{"action": "save", "name": "<name>", "content": "<content>"}`.
4. Report: "Saved conversation '<name>'. Active conversation is now '<name>'."

### new

Create a new conversation from a topic summary.

1. Read the SUMMARY section from pre.sh output.
2. Format it as a conversation handoff file with sections: Current topic/goal, Key points, Open questions.
3. Stage for post.sh: write to `agent-persona/data/.staging/manage-conversation-result.json` with `{"action": "new", "name": "<name>", "content": "<formatted content>"}`.
4. Run post.sh.
5. Report: "Created conversation '<name>'. Active conversation is now '<name>'."

### list

List all named conversations.

1. Read the CONVERSATIONS section from pre.sh output.
2. Return the list to the main agent. No post.sh needed.
