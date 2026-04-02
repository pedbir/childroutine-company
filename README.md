# ChildRoutine Company — Paperclip AI Workspace

This repository is the source-controlled configuration for a [Paperclip AI](https://paperclip.ing) company. It runs inside a VS Code Dev Container using Docker Compose and manages all agent instructions in git, so you never lose work when rebuilding the container.

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

### 3. Open in Dev Container

Open the repo in VS Code and run **Dev Containers: Reopen in Container** from the command palette (`Cmd/Ctrl+Shift+P`).

The container will automatically:

1. Start a Node.js 22 environment via Docker Compose with Claude Code CLI pre-installed
2. Create a `paperclip-data` Docker volume for persistent Paperclip data
3. Run `npx paperclipai onboard --yes` to initialize Paperclip
4. Run `sync-agents.sh` to symlink your git-managed instructions into Paperclip

Once the container is running, start the Paperclip server:

```bash
npx paperclipai run
```

The UI and API are available at **http://localhost:3100**.

## How It Works: Docker Compose

The devcontainer uses a `docker-compose.yml` to manage the development environment. This follows the [Paperclip Docker deployment guide](https://docs.paperclip.ing/deploy/docker) pattern of persisting all Paperclip data in a single volume.

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Docker Compose                                         │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  workspace (node:22)                              │  │
│  │                                                   │  │
│  │  /workspaces/childroutine-company  ← bind mount   │  │
│  │    └── agents/ (git-managed instructions)         │  │
│  │                                                   │  │
│  │  /home/node/.paperclip  ← Docker named volume     │  │
│  │    └── instances/default/                         │  │
│  │        ├── db/            (embedded PostgreSQL)    │  │
│  │        ├── data/storage/  (uploaded assets)       │  │
│  │        ├── secrets/       (master.key)            │  │
│  │        └── companies/     (agent workspaces)      │  │
│  │              └── <id>/agents/<id>/instructions/   │  │
│  │                   └── SOUL.md → symlink to repo   │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  paperclip-data (named volume)                          │
│    Persists: database, storage, secrets, agent data     │
└─────────────────────────────────────────────────────────┘
```

### Why Docker Compose?

Following the [Paperclip Docker docs](https://docs.paperclip.ing/deploy/docker), all Paperclip data is stored under a single path (`PAPERCLIP_HOME`). The Docker Compose setup:

- Uses a **named volume** (`paperclip-data`) for Paperclip data, which survives container rebuilds — no need to create host directories manually
- Sets `PAPERCLIP_HOME=/home/node/.paperclip` so Paperclip knows where its data lives
- Bind-mounts the workspace, Claude Code config, and SSH keys from the host
- Loads API keys from `.env.secrets`

### Key files

| File | Purpose |
|---|---|
| `.devcontainer/devcontainer.json` | Dev Container config — references Compose, sets features and postCreateCommand |
| `.devcontainer/docker-compose.yml` | Service definition, volumes, environment, and mounts |
| `.devcontainer/sync-agents.sh` | Push: symlinks repo instructions into Paperclip on container start |
| `.devcontainer/pull-agents.sh` | Pull: copies new/changed instructions from Paperclip into the repo |

## Repository Structure

```
.
├── .devcontainer/
│   ├── devcontainer.json       # Dev Container config (references docker-compose.yml)
│   ├── docker-compose.yml      # Docker Compose services and volumes
│   ├── sync-agents.sh          # Push: repo → Paperclip (symlinks)
│   └── pull-agents.sh          # Pull: Paperclip → repo (copies)
├── agents/
│   ├── agent-map.json          # Maps friendly names to Paperclip agent UUIDs
│   ├── ceo/
│   │   └── instructions/
│   │       ├── AGENTS.md       # Role definition and working instructions
│   │       ├── SOUL.md         # Persona, voice, and decision-making style
│   │       ├── HEARTBEAT.md    # Per-heartbeat execution checklist
│   │       └── TOOLS.md        # Tool inventory and usage notes
│   ├── engineer/
│   │   └── instructions/
│   │       └── AGENTS.md
│   └── sre/
│       └── instructions/
│           └── AGENTS.md
├── .env.secrets.example        # Template for API keys and tokens
├── .gitignore
└── README.md
```

## Agent Instruction Sync

Paperclip stores agent instructions at `~/.paperclip/instances/default/companies/<company-id>/agents/<agent-id>/instructions/`. These files are what agents read every heartbeat. By default, they only exist in the Docker volume and are not version-controlled.

This repo solves that with a **bidirectional sync** between git and Paperclip's directory.

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

When `pull-agents.sh` discovers a new agent, it adds an entry here automatically. You can also edit entries manually if you prefer a different friendly name.

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

If you (or the CEO agent) create a new agent through the Paperclip UI or API, its instructions will only exist in the Docker volume. Pull them into git:

```bash
bash .devcontainer/pull-agents.sh
# Output: NEW agent discovered: marketing-lead (a1b2c3d4-...)
#         NEW     marketing-lead/AGENTS.md

git add agents/
git commit -m "Add marketing-lead agent instructions"
```

Then run `sync-agents.sh` to replace the plain files with symlinks:

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

This ensures any instructions created or modified through Paperclip are safely in git.

Note: Because Paperclip data lives on a **named Docker volume**, it survives container rebuilds. The pull-and-commit step is still important as a backup and for collaboration — the volume is local to your machine and not shared with other developers.

### After rebuilding the container

The `postCreateCommand` in `devcontainer.json` runs both Paperclip onboarding and `sync-agents.sh` automatically. Your instructions are restored from git via symlinks.

## Volumes and Data Persistence

### Docker volumes

| Volume | Container path | Purpose |
|---|---|---|
| `paperclip-data` (named) | `/home/node/.paperclip` | All Paperclip data — survives container rebuilds |
| Bind mount | `/workspaces/childroutine-company` | This repo |
| Bind mount | `/home/node/.claude` | Claude Code config and session data |
| Bind mount | `/home/node/.claude.json` | Claude Code authentication |
| Bind mount (read-only) | `/home/node/.ssh` | SSH keys for git |

The `paperclip-data` named volume is managed by Docker. Unlike host bind mounts, it doesn't require pre-creating directories on the host. Docker handles its lifecycle automatically.

### What's inside the Paperclip volume

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

### Backing up the volume

To export the Paperclip volume for backup or migration:

```bash
docker run --rm -v paperclip-data:/data -v $(pwd):/backup alpine tar czf /backup/paperclip-backup.tar.gz -C /data .
```

To restore:

```bash
docker run --rm -v paperclip-data:/data -v $(pwd):/backup alpine tar xzf /backup/paperclip-backup.tar.gz -C /data
```

## Environment Variables

Set these in `.env.secrets` (see `.env.secrets.example` for the full template):

| Variable | Required | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | Powers Claude-based agents |
| `OPENAI_API_KEY` | Optional | For OpenAI/Codex-based agents |
| `GITHUB_TOKEN` | Optional | GitHub access for agents |
| `PAPERCLIP_API_KEY` | Optional | Paperclip API authentication |

The container also sets `PAPERCLIP_HOME=/home/node/.paperclip` automatically via the Docker Compose environment.

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

## Troubleshooting

### Container fails to start

Make sure Docker is running and the Claude config files exist on the host:

```bash
mkdir -p ~/.claude
touch ~/.claude.json
```

The `paperclip-data` volume is created automatically by Docker Compose — no manual setup needed.

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

Because Paperclip data lives on a named Docker volume, it persists across container rebuilds. If the volume was accidentally removed, restore from your git-committed agent instructions — they'll be re-synced automatically on the next container start.

If you had new agents that weren't pulled into git yet, check if the volume still exists:

```bash
docker volume ls | grep paperclip
```

### New agent not showing up in the repo

Run `pull-agents.sh` to discover it:

```bash
bash .devcontainer/pull-agents.sh
```

The script auto-detects new agents and names them from the role in their `AGENTS.md` file. If you want a different name, rename the directory and update `agent-map.json` manually.

### Resetting Paperclip completely

To start fresh, remove the Docker volume and rebuild:

```bash
docker volume rm paperclip-data
```

Then reopen the container — `postCreateCommand` will re-onboard and re-sync from your git-managed instructions.
