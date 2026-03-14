# Import Email — Knowledge Extraction

## Purpose
Extract durable knowledge from parsed email messages. Emails are pre-filtered (automated, newsletters, bulk removed). Your job is to identify meaningful facts, relationships, commitments, and preferences.

## Lifecycle
1. Run pre.sh: `bash agent-persona/tasks/import-email/pre.sh --session "$SESSION" --invocation "$INVOCATION"`
2. Read the output sections below
3. Extract knowledge following the rules in this document
4. If preview mode: output extracted knowledge and STOP (do not run post.sh)
5. If not preview: pipe your output to post.sh: `echo "<your output>" | bash agent-persona/tasks/import-email/post.sh --session "$SESSION" --invocation "$INVOCATION"`

## Input sections from pre.sh

- **PARSED_EMAILS** — JSON with metadata and email array from parse-mbox.py
- **EXISTING_KNOWLEDGE** — current knowledge.json (check for duplicates, verify entities)
- **EXISTING_GRAPH_ENTITIES** — list of known graph entity IDs (verify people/places against these)

## Extraction rules

### What to extract
For each email (or cluster of related emails), extract:

1. **People** — names, email addresses, relationship to user (infer from context: colleague, friend, family, service provider). Cross-reference against EXISTING_GRAPH_ENTITIES.
2. **Facts** — concrete information: dates, events, plans, locations, bookings, decisions made
3. **Commitments** — things the user agreed to do, or others committed to the user
4. **Preferences** — user preferences revealed in email content (e.g., dietary, travel, scheduling patterns)
5. **Relationships** — how people relate to each other and to the user

### What NOT to extract
- Transactional details with no lasting value (order numbers, tracking IDs, one-time codes)
- Redundant information already in EXISTING_KNOWLEDGE (check first!)
- Speculative inferences not supported by email content
- Verbatim email text — extract the knowledge, not the raw content

### Entity verification
CRITICAL: Before creating a knowledge item about a person, check EXISTING_GRAPH_ENTITIES and EXISTING_KNOWLEDGE. If the person already exists, reference them correctly. Do NOT invent relationships — only extract what the email content explicitly supports.

### Strength assignment
- Direct, explicit facts → strength 5-7
- Inferred but well-supported → strength 3-4
- Weak/single-mention → strength 1-2

## Output format

Output valid JSON:

```json
{
  "extracted": [
    {
      "type": "fact|trait|relationship|commitment|preference",
      "content": "Clear, concise statement of the knowledge",
      "scope": "personal",
      "strength": 5,
      "source": "email_import_YYYY-MM-DD",
      "entities": ["person-name", "place-name"],
      "graph_edges": [
        {"from": "entity-a", "to": "entity-b", "label": "relationship-type"}
      ]
    }
  ],
  "new_entities": [
    {
      "id": "entity-id-kebab-case",
      "type": "person|place|organization|event",
      "label": "Human-readable name",
      "category": "personal"
    }
  ],
  "summary": {
    "emails_processed": 50,
    "items_extracted": 12,
    "new_entities": 3,
    "duplicates_skipped": 5
  }
}
```

### Preview mode
If the FLAGS section shows `preview=true`:
- Output the same JSON format above
- Add a `"preview": true` field to the root
- Do NOT run post.sh
- The main agent will show the user what would be extracted

### Batching
If metadata shows more emails remain (batch_offset + batch_size < after_filter), note this in your summary:
```json
"summary": {
  "...": "...",
  "more_available": true,
  "next_batch_offset": 50
}
```
