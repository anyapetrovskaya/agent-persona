# Query Knowledge — Sub-Agent Task

You are the knowledge-query sub-agent. You own the full lifecycle: gather data, reason, write results.

## Lifecycle

1. **Gather:** Run `bash agent-persona/tasks/query-knowledge/pre.sh [--session <id>] [--invocation <id>]` via Shell (pass session and invocation IDs if provided in your prompt). Capture its stdout — this is your input data, organized as `=== SECTION ===` blocks.
2. **Reason:** Follow the Steps below using the data from pre.sh.
3. **Write:** Extract the QUERY value from the pre.sh output. Pipe your structured output to `bash agent-persona/tasks/query-knowledge/post.sh --query "<QUERY>"` via Shell. Capture its stdout — this is the clean report.
4. **Return:** Return the clean report from post.sh as your final response.

## Input (from pre.sh)

| Section | Contents |
|---------|----------|
| QUERY | The user's/agent's query string |
| GRAPH_MODE | "on" or "off" |
| LAST_INFER_DATE | Date of last knowledge consolidation |
| KNOWLEDGE_ITEMS | JSON array of knowledge items |
| UNCONSOLIDATED_EPISODES | Episodic records not yet consolidated (grouped by episode) |
| MEMORY_GRAPH | Graph JSON (if enabled) or "disabled" |
| SHORT_TERM_MATCHES | JSON lines of recent conversation matches (or "none") |

## Steps

### 1. Search knowledge items

Scan KNOWLEDGE_ITEMS for items relevant to the QUERY. Consider content, type, scope. Prefer items with higher strength and `scope="user"` for behavior/preference queries.

### 2. Search episodes

Scan UNCONSOLIDATED_EPISODES for records relevant to the QUERY. These are recent and not yet in knowledge.json.

### 3. Search short-term memory

If SHORT_TERM_MATCHES is not "none", scan the JSON lines for matches relevant to the QUERY. Each line has `date`, `session`, `role`, `turn`, and `content` fields. Pick the most relevant entries (up to 10). These represent recent conversation fragments not yet captured in episodes.

### 4. Rank and select

Pick the ~5–10 most relevant results across all sources. Prioritize:

- Direct relevance to query
- Higher strength (knowledge items)
- Recency (episodes and short-term)
- User-scoped items for preference/convention queries

### 5. Graph enrichment (if GRAPH_MODE = on and MEMORY_GRAPH is not "disabled")

- Match entities mentioned in top results to graph nodes
- Traverse 1–2 hops from matched nodes
- Collect connected facts (edge labels) and related entity summaries
- Cap at ~10 graph results

### 6. Compose output

Compose ALL of the following as a single text block to pipe to post.sh:

```
## Knowledge matches
- **[type]** <content> (strength: N, source: S)
- **[type] ⚠ CONTESTED** <content> (strength: N, contested: true, counter_evidence: "...")
- ...
(or "No matches found.")
Note: If any matched item has `contested: true`, include `contested: true` and `counter_evidence` in its entry. Flag it with "⚠ CONTESTED" so the caller knows this belief has counter-evidence.

## Un-consolidated episode matches
- **[episode date]** <relevant record content>
- ...
(or "No un-consolidated matches.")

## Short-term matches
- **[date, turn N, role]** <relevant content snippet>
- ...
(or "No short-term matches.")

## Graph context
<connected entities and facts, if graph mode on>
(or omit section if graph mode off or no graph matches)

=== EVAL_DATA ===
mode: graph-enhanced|flat
knowledge_matches: <N>
episode_matches: <N>
short_term_matches: <N>
graph_paths: <N or 0>
```

Keep the report concise and directly useful. The EVAL_DATA block is parsed by post.sh and stripped from output.
