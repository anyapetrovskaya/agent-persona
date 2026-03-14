#!/usr/bin/env bash
# import-email/post.sh — write extracted email knowledge to knowledge store and graph
set -euo pipefail

AP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DATA_DIR="$AP_DIR/data"
KNOWLEDGE_FILE="$DATA_DIR/knowledge.json"
GRAPH_FILE="$DATA_DIR/memory_graph.json"

# Parse args
SESSION=""
INVOCATION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session)    SESSION="$2"; shift 2 ;;
    --invocation) INVOCATION="$2"; shift 2 ;;
    *)            shift ;;
  esac
done

# Read extracted knowledge from stdin
INPUT=$(cat)

# Parse the JSON — extract the "extracted" array and "new_entities" array
EXTRACTED=$(echo "$INPUT" | jq -r '.extracted // []')
NEW_ENTITIES=$(echo "$INPUT" | jq -r '.new_entities // []')
SUMMARY=$(echo "$INPUT" | jq -r '.summary // {}')
PREVIEW=$(echo "$INPUT" | jq -r '.preview // false')

# If preview mode, just output and exit
if [[ "$PREVIEW" == "true" ]]; then
  echo "=== PREVIEW MODE ==="
  echo "$INPUT" | jq .
  exit 0
fi

# --- Append extracted items to knowledge.json ---
ITEMS_ADDED=0
if [[ $(echo "$EXTRACTED" | jq 'length') -gt 0 ]]; then
  # Build knowledge entries in the format matching existing knowledge.json
  # Each extracted item becomes a knowledge entry
  TIMESTAMP=$(date -Iseconds)

  NEW_ITEMS=$(echo "$EXTRACTED" | jq --arg ts "$TIMESTAMP" '[.[] | {
    type: .type,
    content: .content,
    scope: (.scope // "personal"),
    strength: (.strength // 3),
    source: (.source // "email_import"),
    last_accessed: null,
    access_count: 0,
    pinned: false,
    retention_score: 1.0
  }]')

  # Merge into knowledge.json
  if [[ -f "$KNOWLEDGE_FILE" ]]; then
    EXISTING=$(jq '.items' "$KNOWLEDGE_FILE")
    MERGED=$(echo "$EXISTING" "$NEW_ITEMS" | jq -s '.[0] + .[1]')
    jq --argjson items "$MERGED" --arg ts "$TIMESTAMP" \
      '.items = $items | .last_infer_date = ($ts | split("T")[0])' \
      "$KNOWLEDGE_FILE" > "${KNOWLEDGE_FILE}.tmp" && mv "${KNOWLEDGE_FILE}.tmp" "$KNOWLEDGE_FILE"
  else
    jq -n --argjson items "$NEW_ITEMS" '{items: $items}' > "$KNOWLEDGE_FILE"
  fi

  ITEMS_ADDED=$(echo "$NEW_ITEMS" | jq 'length')
fi

# --- Add new entities and edges to memory_graph.json ---
NODES_ADDED=0
EDGES_ADDED=0
if [[ -f "$GRAPH_FILE" ]]; then
  # Add new entity nodes
  if [[ $(echo "$NEW_ENTITIES" | jq 'length') -gt 0 ]]; then
    EXISTING_NODES=$(jq '.nodes' "$GRAPH_FILE")
    EXISTING_IDS=$(echo "$EXISTING_NODES" | jq -r '.[].id')

    # Filter out entities that already exist
    NEW_NODES=$(echo "$NEW_ENTITIES" | jq --argjson existing "$EXISTING_NODES" '
      [.[] | . as $new |
        if ($existing | map(.id) | index($new.id)) then empty
        else {id: .id, type: .type, label: .label, category: (.category // "personal")}
        end
      ]')

    NODES_ADDED=$(echo "$NEW_NODES" | jq 'length')
    if [[ $NODES_ADDED -gt 0 ]]; then
      MERGED_NODES=$(echo "$EXISTING_NODES" "$NEW_NODES" | jq -s '.[0] + .[1]')
      jq --argjson nodes "$MERGED_NODES" '.nodes = $nodes' "$GRAPH_FILE" > "${GRAPH_FILE}.tmp" && mv "${GRAPH_FILE}.tmp" "$GRAPH_FILE"
    fi
  fi

  # Add new edges from extracted items
  ALL_EDGES=$(echo "$EXTRACTED" | jq '[.[].graph_edges // [] | .[]] | select(length > 0)')
  if [[ -n "$ALL_EDGES" ]] && [[ $(echo "$ALL_EDGES" | jq 'length') -gt 0 ]]; then
    EXISTING_EDGES=$(jq '.edges' "$GRAPH_FILE")

    # Filter out duplicate edges
    NEW_EDGES=$(echo "$ALL_EDGES" | jq --argjson existing "$EXISTING_EDGES" '
      [.[] | . as $new |
        if ($existing | map({from: .from, to: .to, label: .label}) | index({from: $new.from, to: $new.to, label: $new.label})) then empty
        else .
        end
      ]')

    EDGES_ADDED=$(echo "$NEW_EDGES" | jq 'length')
    if [[ $EDGES_ADDED -gt 0 ]]; then
      MERGED_EDGES=$(echo "$EXISTING_EDGES" "$NEW_EDGES" | jq -s '.[0] + .[1]')
      jq --argjson edges "$MERGED_EDGES" '.edges = $edges' "$GRAPH_FILE" > "${GRAPH_FILE}.tmp" && mv "${GRAPH_FILE}.tmp" "$GRAPH_FILE"
    fi
  fi
fi

# --- Output report ---
echo "=== EMAIL IMPORT RESULTS ==="
echo "Knowledge items added: $ITEMS_ADDED"
echo "Graph nodes added: $NODES_ADDED"
echo "Graph edges added: $EDGES_ADDED"
echo ""
echo "=== SUMMARY ==="
echo "$SUMMARY" | jq .
