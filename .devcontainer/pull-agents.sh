#!/usr/bin/env bash
# pull-agents.sh — Pull agent instructions FROM Paperclip INTO the git repo.
# Run this before shutting down or rebuilding the container to capture any
# new agents, roles, or instruction changes made through Paperclip.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAP_FILE="$REPO_ROOT/agents/agent-map.json"
PAPERCLIP_BASE="$HOME/.paperclip/instances/default/companies"

# --- Discover company ID ---
# Use existing map if available, otherwise scan for the first company
if [ -f "$MAP_FILE" ]; then
  COMPANY_ID=$(jq -r '.companyId' "$MAP_FILE")
else
  COMPANY_ID=$(ls "$PAPERCLIP_BASE" 2>/dev/null | head -1)
  if [ -z "$COMPANY_ID" ]; then
    echo "No Paperclip companies found. Nothing to pull."
    exit 0
  fi
fi

AGENTS_DIR="$PAPERCLIP_BASE/$COMPANY_ID/agents"
if [ ! -d "$AGENTS_DIR" ]; then
  echo "No agents directory found for company $COMPANY_ID"
  exit 0
fi

# --- Load existing map or start fresh ---
if [ -f "$MAP_FILE" ]; then
  EXISTING_MAP=$(cat "$MAP_FILE")
else
  EXISTING_MAP=$(jq -n --arg cid "$COMPANY_ID" '{"companyId": $cid, "agents": {}}')
fi

# Build a reverse lookup: agent_id -> agent_name
declare -A ID_TO_NAME
for NAME in $(echo "$EXISTING_MAP" | jq -r '.agents | keys[]' 2>/dev/null); do
  ID=$(echo "$EXISTING_MAP" | jq -r ".agents[\"$NAME\"]")
  ID_TO_NAME[$ID]="$NAME"
done

CHANGES=0

for AGENT_ID_DIR in "$AGENTS_DIR"/*/; do
  AGENT_ID=$(basename "$AGENT_ID_DIR")
  INSTRUCTIONS_DIR="$AGENT_ID_DIR/instructions"

  [ -d "$INSTRUCTIONS_DIR" ] || continue

  # Determine friendly name — use existing mapping or derive from AGENTS.md
  if [ -n "${ID_TO_NAME[$AGENT_ID]:-}" ]; then
    AGENT_NAME="${ID_TO_NAME[$AGENT_ID]}"
  else
    # Try to extract role from first line of AGENTS.md
    if [ -f "$INSTRUCTIONS_DIR/AGENTS.md" ]; then
      ROLE=$(head -1 "$INSTRUCTIONS_DIR/AGENTS.md" | sed 's/^You are the //' | sed 's/[.!].*$//' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
      # Fallback to agent ID prefix if extraction fails
      AGENT_NAME="${ROLE:-agent-${AGENT_ID:0:8}}"
    else
      AGENT_NAME="agent-${AGENT_ID:0:8}"
    fi
    echo "  NEW agent discovered: $AGENT_NAME ($AGENT_ID)"
  fi

  DEST_DIR="$REPO_ROOT/agents/$AGENT_NAME/instructions"
  mkdir -p "$DEST_DIR"

  for FILE in "$INSTRUCTIONS_DIR"/*; do
    [ -f "$FILE" ] || continue
    FILENAME=$(basename "$FILE")
    DEST_FILE="$DEST_DIR/$FILENAME"

    # If it's a symlink pointing back to our repo, read the actual content from Paperclip
    # (symlinks mean we already manage this file — check if source changed)
    if [ -L "$FILE" ]; then
      # Symlink points to our repo — file is already managed, skip
      continue
    fi

    # Compare content if dest exists
    if [ -f "$DEST_FILE" ]; then
      if diff -q "$FILE" "$DEST_FILE" > /dev/null 2>&1; then
        continue
      fi
      echo "  UPDATED $AGENT_NAME/$FILENAME"
    else
      echo "  NEW     $AGENT_NAME/$FILENAME"
    fi

    cp "$FILE" "$DEST_FILE"
    CHANGES=$((CHANGES + 1))
  done

  # Update the map with this agent
  EXISTING_MAP=$(echo "$EXISTING_MAP" | jq --arg name "$AGENT_NAME" --arg id "$AGENT_ID" '.agents[$name] = $id')
done

# Write updated map
echo "$EXISTING_MAP" | jq '.' > "$MAP_FILE"

if [ "$CHANGES" -eq 0 ]; then
  echo "All agent instructions are up to date."
else
  echo "$CHANGES file(s) pulled into the repo. Review with 'git diff' and commit."
fi
