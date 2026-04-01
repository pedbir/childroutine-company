#!/usr/bin/env bash
set -euo pipefail

# Verify we're in the workspace with the cloned repo
if [ ! -f /workspace/package.json ]; then
  echo "ERROR: No package.json found in /workspace."
  echo ""
  echo "Make sure the Paperclip repo is cloned into this folder first:"
  echo "  git clone https://github.com/paperclipai/paperclip.git ."
  echo ""
  echo "The .devcontainer folder should be INSIDE the cloned repo."
  exit 1
fi

echo "==> Installing dependencies with pnpm..."
pnpm install

echo "==> Copying .env from example (if it doesn't exist)..."
if [ ! -f .env ] && [ -f .env.example ]; then
  cp .env.example .env
  echo "    Created .env from .env.example — edit it to add your API keys."
else
  echo "    .env already exists or no .env.example found, skipping."
fi

echo "==> Running database migrations..."
pnpm db:generate 2>/dev/null || echo "    db:generate skipped (may not be needed)"
pnpm db:migrate  2>/dev/null || echo "    db:migrate skipped (may not be needed)"

echo ""
echo "============================================"
echo "  Paperclip dev container is ready!"
echo ""
echo "  Run:  pnpm dev"
echo "    API  → http://localhost:3100"
echo "    UI   → http://localhost:5173"
echo "============================================"
