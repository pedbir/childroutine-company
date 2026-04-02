#!/usr/bin/env bash
# bootstrap-company.sh — Import company + agents from the exported package,
# update agent-map.json with the new UUIDs, then run sync-agents.sh to
# symlink git-managed instructions into Paperclip's directory.
#
# This script is idempotent: if the company already exists (by name), it skips
# the import. Run it after Paperclip is onboarded and the server is healthy.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPORT_DIR="$REPO_ROOT/exports/childroutine"
MAP_FILE="$REPO_ROOT/agents/agent-map.json"
API_BASE="http://127.0.0.1:3100"

if [ ! -f "$EXPORT_DIR/.paperclip.yaml" ]; then
  echo "ERROR: Export package not found at $EXPORT_DIR"
  exit 1
fi

# ── Check if company already exists ──────────────────────────────────────────
EXISTING=$(curl -sf "$API_BASE/api/companies" | jq -r '.[] | select(.name == "ChildRoutine") | .id')

if [ -n "$EXISTING" ]; then
  echo "Company 'ChildRoutine' already exists (id: $EXISTING). Checking agents..."
  AGENT_COUNT=$(curl -sf "$API_BASE/api/companies/$EXISTING/agents" | jq 'length')
  if [ "$AGENT_COUNT" -gt 0 ]; then
    echo "Company has $AGENT_COUNT agent(s). Skipping import, updating agent-map.json."
    COMPANY_ID="$EXISTING"
  else
    echo "Company exists but has no agents. Will import agents into it."
    IMPORT_RESULT=$(npx paperclipai company import "$EXPORT_DIR" \
      --target existing \
      --company-id "$EXISTING" \
      --include agents \
      --collision skip \
      --yes --json 2>&1)
    echo "$IMPORT_RESULT" | jq '.result.agents // empty' 2>/dev/null || true
    COMPANY_ID="$EXISTING"
  fi
else
  # ── Import as a new company ──────────────────────────────────────────────
  echo "No existing company found. Importing from export package..."
  IMPORT_RESULT=$(npx paperclipai company import "$EXPORT_DIR" \
    --target new \
    --new-company-name "ChildRoutine" \
    --include company,agents \
    --yes --json 2>&1)

  COMPANY_ID=$(echo "$IMPORT_RESULT" | jq -r '.result.companyId // empty')
  if [ -z "$COMPANY_ID" ]; then
    echo "ERROR: Import failed. Output:"
    echo "$IMPORT_RESULT"
    exit 1
  fi
  echo "Company imported (id: $COMPANY_ID)"
fi

# ── Build updated agent-map.json ─────────────────────────────────────────────
# Fetch agents from the API and map slug (url_key or lowercased name) to UUID.
AGENTS_JSON=$(curl -sf "$API_BASE/api/companies/$COMPANY_ID/agents")

# Build the agents object: use urlKey if available, otherwise lowercase name
AGENTS_MAP=$(echo "$AGENTS_JSON" | jq -r '
  reduce .[] as $a ({};
    . + { ($a.urlKey // ($a.name | ascii_downcase)): $a.id }
  )')

# Write agent-map.json
jq -n \
  --arg cid "$COMPANY_ID" \
  --argjson agents "$AGENTS_MAP" \
  '{ companyId: $cid, agents: $agents }' > "$MAP_FILE"

echo "Updated agent-map.json:"
cat "$MAP_FILE"

# ── Symlink instructions ─────────────────────────────────────────────────────
echo ""
bash "$REPO_ROOT/.devcontainer/sync-agents.sh"

echo ""
echo "Bootstrap complete."
