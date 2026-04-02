# ChildRoutine Company — Paperclip AI Workspace

This repository is the source-controlled configuration for a [Paperclip AI](https://paperclip.ing) company. It runs inside a VS Code Dev Container and manages all agent instructions in git, so you never lose work when rebuilding the container.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or any Docker-compatible runtime)
- [VS Code](https://code.visualstudio.com/) with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
- An [Anthropic API key](https://console.anthropic.com/) (for Claude-powered agents)

## Quick Start

### 1. Clone the repo

```bash
git clone <your-repo-url>
cd childroutine-company
```

### 2. Set up secrets

```bash
cp .env.secrets.example .env.secrets
```

Edit `.env.secrets` and fill in your API keys. This file is git-ignored and never committed.

### 3. Prepare host directories

The container bind-mounts several directories from your host machine. Make sure they exist:

```bash
mkdir -p ~/.paperclip ~/.claude
```

### 4. Open in Dev Container

Open the repo in VS Code and run **Dev Containers: Reopen in Container** from the command palette (`Cmd/Ctrl+Shift+P`). The container will:

1. Start a Node.js 22 environment with Claude Code CLI pre-installed
2. Run `npx paperclipai onboard --yes` to initialize Paperclip
3. Run `sync-agents.sh` to symlink your git-managed instructions into Paperclip

Once the container is running, start the Paperclip server:

```bash
pnpm dev
```

The UI and API are available at **http://localhost:3100**.

## Repository Structure

```
.
├── .devcontainer/
│   ├── devcontainer.json    # Container config, volume mounts, post-create setup
│   ├── sync-agents.sh       # Push: repo → Paperclip (symlinks)
│   └── pull-agents.sh       # Pull: Paperclip → repo (copies)
├── agents/
│   ├── agent-map.json       # Maps friendly names to Paperclip agent UUIDs
│   ├── ceo/
│   │   └── instructions/
│   │       ├── AGENTS.md    # Role definition and working instructions
│   │       ├── SOUL.md      # Persona, voice, and decision-making style
│   │       ├── HEARTBEAT.md # Per-heartbeat execution checklist
│   │       └── TOOLS.md     # Tool inventory and usage notes
│   ├── engineer/
│   │   └── instructions/
│   │       └── AGENTS.md
│   └── sre/
│       └── instructions/
│           └── AGENTS.md
├── .env.secrets.example     # Template for API keys and tokens
├── .gitignore
└── README.md
```

## How Agent Instruction Sync Works

Paperclip stores agent instructions at `~/.paperclip/instances/default/companies/<company-id>/agents/<agent-id>/instructions/`. These files are what the agents read every heartbeat. By default, they only exist inside the container and are not version-controlled.

This repo solves that with a **bidirectional sync** between git and Paperclip's local directory using two scripts:

### Push: `sync-agents.sh` (repo → Paperclip)

```
agents/ceo/instructions/SOUL.md  →  symlink  →  ~/.paperclip/.../agents/<uuid>/instructions/SOUL.md
```

- Reads `agents/agent-map.json` to map friendly names (e.g., `ceo`) to Paperclip agent UUIDs
- Replaces each instruction file in Paperclip's directory with a **symlink** pointing to the repo
- Paperclip reads the symlinks transparently — no copies, always in sync
- **Runs automatically** on container creation via `postCreateCommand`
- Safe to re-run anytime: `bash .devcontainer/sync-agents.sh`

### Pull: `pull-agents.sh` (Paperclip → repo)

```
~/.paperclip/.../agents/<uuid>/instructions/SOUL.md  →  copy  →  agents/ceo/instructions/SOUL.md
```

- Scans all agents in Paperclip's directory
- **Discovers new agents** not yet in `agent-map.json` — auto-names them from their role (e.g., "You are the QA engineer" becomes `qa-engineer/`)
- Copies any new or changed instruction files into the repo
- Updates `agent-map.json` with new agent mappings
- Skips files that are already symlinked (already managed by git)
- **Run manually** before shutdown: `bash .devcontainer/pull-agents.sh`

### The agent-map.json file

This file is the bridge between your human-readable directory names and Paperclip's UUIDs:

```json
{
  "companyId": "d447e052-1c5c-40f8-af99-c767cc8885da",
  "agents": {
    "ceo": "30c780b4-f591-42aa-aa5d-797f3eb9cc17",
    "engineer": "bfb905ba-d6f8-4763-8d84-ec9ee5332e6c",
    "sre": "2caccd56-bbdd-4231-b261-b18345a687e2"
  }
}
```

When `pull-agents.sh` discovers a new agent, it adds an entry here automatically. You can also add entries manually if you prefer a different friendly name.

## Day-to-Day Workflow

### Editing agent instructions

Edit files directly in `agents/<name>/instructions/`. Because Paperclip reads via symlinks, changes take effect immediately — no restart or re-sync needed.

```bash
# Edit the CEO's persona
vim agents/ceo/instructions/SOUL.md

# Commit when you're happy
git add agents/
git commit -m "Refine CEO voice and tone guidelines"
```

### When Paperclip creates a new agent

If you (or the CEO agent) create a new agent through the Paperclip UI or API, its instructions will only exist in `~/.paperclip`. Pull them into git:

```bash
bash .devcontainer/pull-agents.sh
# Output: NEW agent discovered: marketing-lead (a1b2c3d4-...)
#         NEW     marketing-lead/AGENTS.md

git add agents/
git commit -m "Add marketing-lead agent instructions"
```

After committing, run `sync-agents.sh` to replace the plain files with symlinks:

```bash
bash .devcontainer/sync-agents.sh
```

### Before shutting down or rebuilding the container

Always pull and commit first:

```bash
bash .devcontainer/pull-agents.sh
git add agents/
git commit -m "Sync agent instructions"
git push
```

This ensures any instructions created or modified through Paperclip are safely in git before the container is destroyed.

### After rebuilding the container

The `postCreateCommand` in `devcontainer.json` runs both Paperclip onboarding and `sync-agents.sh` automatically. Your instructions are restored from git via symlinks.

## Volume Mounts

The devcontainer mounts these host directories into the container:

| Host path | Container path | Purpose |
|---|---|---|
| `~/.paperclip` | `/home/node/.paperclip` | Paperclip data: database, config, agent workspaces, storage |
| `~/.claude` | `/home/node/.claude` | Claude Code configuration and session data |
| `~/.claude.json` | `/home/node/.claude.json` | Claude Code authentication |
| `~/.ssh` | `/home/node/.ssh` | SSH keys for git operations (read-only) |

The `~/.paperclip` mount is critical — it persists the embedded PostgreSQL database, secrets master key, run logs, and agent workspace data across container rebuilds.

## Environment Variables

Set these in `.env.secrets` (see `.env.secrets.example` for the full template):

| Variable | Required | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | Powers Claude-based agents |
| `OPENAI_API_KEY` | Optional | For OpenAI/Codex-based agents |
| `GITHUB_TOKEN` | Optional | GitHub access for agents |
| `PAPERCLIP_API_KEY` | Optional | Paperclip API authentication |

## Agents

### CEO (`agents/ceo/`)

The CEO agent owns strategic direction, hiring, delegation, and unblocking. It manages the company's goals, creates tasks, and assigns work to other agents.

**Instruction files:**
- `AGENTS.md` — Role definition, safety rules, and references to other instruction files
- `SOUL.md` — Persona, strategic posture, voice and tone guidelines
- `HEARTBEAT.md` — Step-by-step checklist executed every heartbeat cycle
- `TOOLS.md` — Inventory of available tools (populated as the agent acquires them)

### Engineer (`agents/engineer/`)

The founding full-stack engineer. Owns the Little Helpers Dash codebase — ships features, fixes bugs, writes tests.

**Instruction files:**
- `AGENTS.md` — Role, working style, tech context, git workflow, and communication guidelines

### SRE (`agents/sre/`)

The Site Reliability Engineer. Owns infrastructure, deployment, and reliability. Focused on GCP hosting and Supabase Cloud integration.

**Instruction files:**
- `AGENTS.md` — Role, infrastructure principles, tech context, and deployment guidelines

## Paperclip Data Locations

All Paperclip data lives under `~/.paperclip/instances/default/`:

| Path | Contents |
|---|---|
| `config.json` | Server, database, storage, and auth configuration |
| `db/` | Embedded PostgreSQL data |
| `data/storage/` | Uploaded assets and file storage |
| `data/backups/` | Automatic database backups (hourly, 30-day retention) |
| `data/run-logs/` | Agent heartbeat execution logs |
| `secrets/master.key` | Encryption key for stored secrets |
| `logs/` | Server logs |
| `companies/<id>/agents/<id>/` | Agent workspaces: instructions, memory, life data |

## Troubleshooting

### Container fails to start with mount errors

Make sure the host directories exist:

```bash
mkdir -p ~/.paperclip ~/.claude
touch ~/.claude.json
```

### Agent instructions not taking effect

Verify symlinks are in place:

```bash
ls -la ~/.paperclip/instances/default/companies/*/agents/*/instructions/
```

If files are plain copies instead of symlinks, re-run:

```bash
bash .devcontainer/sync-agents.sh
```

### Lost instructions after container rebuild

If you forgot to pull before rebuilding, check if the `~/.paperclip` mount was active. If it was, the data still exists on your host at `~/.paperclip` — run `pull-agents.sh` to recover.

If the mount wasn't active (first-time setup), the data in the container is gone. This is why the pull-and-commit workflow matters.

### New agent not showing up in the repo

Run `pull-agents.sh` to discover it:

```bash
bash .devcontainer/pull-agents.sh
```

The script auto-detects new agents and names them from the role in their `AGENTS.md` file. If you want a different name, rename the directory and update `agent-map.json` manually.
