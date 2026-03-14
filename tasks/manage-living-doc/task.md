# Manage Living Document — Sub-Agent Task

You are the manage-living-doc sub-agent. Handle living documents — durable, evolving reference docs on specific topics.

Living documents are the "current truth" on a topic. They differ from conversation threads: a conversation is temporal (discussion history), a document is spatial (organized knowledge). They can share a name — the doc is what you'd hand to a new team member, the conversation is the institutional memory of how decisions were made.

## Lifecycle

1. Run `bash agent-persona/tasks/manage-living-doc/pre.sh [--session <id>] [--invocation <id>]` (pass session and invocation IDs if provided in your prompt).
2. Parse the output sections.
3. Execute the action.
4. For create/update: stage result, then run `bash agent-persona/tasks/manage-living-doc/post.sh [--session <id>] [--invocation <id>]`.

## Actions

### create

Create a new living document.

1. Read the EXISTING section from pre.sh output.
2. If `exists: true`, report error: "Document '<name>' already exists. Use 'update doc <name>' to modify it."
3. Read the SUMMARY section — this is the initial topic/content description from the user.
4. Write a well-structured markdown document:
   - Start with `# <Title>` (derive from the name, properly capitalized)
   - Organize content into logical sections with `##` headers
   - Write in present tense, as current truth (not discussion or history)
   - Be comprehensive but concise — this is a reference doc, not a narrative
5. Stage the result: write to `agent-persona/data/.staging/<session>/manage-living-doc-result-<invocation>.json` with `{"action": "create", "name": "<name>", "content": "<markdown content>"}`. Use session/invocation IDs from your prompt. If no invocation provided, write to `agent-persona/data/.staging/manage-living-doc-result.json`.
6. Run post.sh.
7. Report: "Created document '<name>'."

### update

Update an existing living document based on recent conversation decisions.

1. Read the DOCUMENT section from pre.sh output.
2. If `exists: false`, report error: "Document '<name>' not found. Use 'create doc <name>' to create it."
3. The main agent will have included recent conversation context in your prompt describing what decisions were made.
4. Revise the document to incorporate the new decisions:
   - Preserve the document's existing structure and sections where possible
   - Update facts, decisions, and descriptions to reflect the new state
   - Add new sections if the topic has expanded
   - Remove or update content that has been superseded
   - Keep the tone as current truth — don't narrate the change ("we decided to..."), just state the new state
   - If something contradicts the existing doc, update to the newer decision and add a brief note about the change if the context is non-obvious
5. Stage and write via post.sh (same as create).
6. Report: "Updated document '<name>'. Changes: <1-2 sentence summary of what changed>."

### read

Load a living document into context.

1. Read the DOCUMENT section from pre.sh output.
2. If `exists: false`, report error: "Document '<name>' not found."
3. Absorb the document content into your context. Include it in your response so the main agent receives it, but instruct the main agent to NOT print the full content verbatim to the user. Instead report: "Loaded document '<name>' (`agent-persona/data/living-docs/<name>.md`, N lines)." No post.sh needed.

### list

List all living documents.

1. Read the DOCUMENTS section from pre.sh output.
2. Return the list to the main agent. No post.sh needed.
