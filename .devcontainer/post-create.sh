#!/usr/bin/env bash
# post-create.sh — devcontainer postCreateCommand
# Onboards Paperclip (config + migrations), imports the company and agents
# from the exported package, then symlinks git-managed instructions.
set -euo pipefail

sudo chown -R node:node /home/node/.paperclip
mkdir -p /home/node/.paperclip/instances/default

# Run onboard with --yes (quickstart defaults).
# --yes implies --run which starts the server and blocks, so we launch it
# in the background, wait for the server to become healthy, then move on.
npx paperclipai onboard --yes &
ONBOARD_PID=$!

# Wait for the server to be ready (up to 120 s)
echo "Waiting for Paperclip server to start..."
for i in $(seq 1 120); do
  if curl -sf http://127.0.0.1:3100/api/health > /dev/null 2>&1; then
    echo "Paperclip server is healthy."
    break
  fi
  sleep 1
done

# Import company + agents from export, update agent-map.json, symlink instructions
bash .devcontainer/bootstrap-company.sh

echo "postCreateCommand complete — Paperclip running in background (PID $ONBOARD_PID)."
