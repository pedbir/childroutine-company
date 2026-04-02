#!/usr/bin/env bash
# sync-agents.sh — Symlink git-managed agent instructions into Paperclip's directory.
# Run after container creation so Paperclip reads from source-controlled files.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAP_FILE="$REPO_ROOT/agents/agent-map.json"

if [ ! -f "$MAP_FILE" ]; then
  echo "agent-map.json not found, skipping agent sync"
  exit 0
fi

COMPANY_ID=$(jq -r '.companyId' "$MAP_FILE")
PAPERCLIP_COMPANIES="$HOME/.paperclip/instances/default/companies/$COMPANY_ID/agents"

# For each agent in the map, symlink instruction files
for AGENT_NAME in $(jq -r '.agents | keys[]' "$MAP_FILE"); do
  AGENT_ID=$(jq -r ".agents[\"$AGENT_NAME\"]" "$MAP_FILE")
  SRC_DIR="$REPO_ROOT/agents/$AGENT_NAME/instructions"
  DEST_DIR="$PAPERCLIP_COMPANIES/$AGENT_ID/instructions"

  if [ ! -d "$SRC_DIR" ]; then
    echo "  skip $AGENT_NAME — no instructions dir in repo"
    continue
  fi

  # Create the target directory if Paperclip hasn't created it yet
  mkdir -p "$DEST_DIR"

  # Remove stale symlinks — files that were deleted from git but still
  # exist as symlinks in Paperclip's directory
  for EXISTING in "$DEST_DIR"/*; do
    [ -L "$EXISTING" ] || continue
    LINK_TARGET=$(readlink "$EXISTING")
    if [[ "$LINK_TARGET" == "$SRC_DIR/"* ]] && [ ! -e "$LINK_TARGET" ]; then
      rm "$EXISTING"
      echo "  removed stale link $(basename "$EXISTING") for $AGENT_NAME"
    fi
  done

  for FILE in "$SRC_DIR"/*; do
    [ -f "$FILE" ] || continue
    FILENAME=$(basename "$FILE")
    DEST_FILE="$DEST_DIR/$FILENAME"

    # Remove existing file/symlink so we can replace it
    if [ -e "$DEST_FILE" ] || [ -L "$DEST_FILE" ]; then
      rm "$DEST_FILE"
    fi

    ln -s "$FILE" "$DEST_FILE"
    echo "  linked $AGENT_NAME/$FILENAME"
  done
done

echo "Agent instructions synced."
