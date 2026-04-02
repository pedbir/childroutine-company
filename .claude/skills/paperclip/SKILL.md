---
name: paperclip
description: >
  Set up, configure, deploy, and operate Paperclip — the control plane for autonomous AI companies.
  Use this skill whenever the user mentions Paperclip, AI agent companies, agent orchestration with Paperclip,
  heartbeat protocol, agent adapters (claude_local, codex_local, gemini_local, etc.), or anything related to
  managing AI workforces through a control plane. Also trigger when the user asks about creating companies with
  AI employees, setting up agent org charts, managing agent budgets/salaries, or deploying an agent control plane.
  Even if the user just says "set up my agents" or "run my AI company" and Paperclip is in their project,
  use this skill. Also trigger for paperclipai CLI commands, Paperclip approval workflows, cost tracking,
  or agent heartbeat debugging.
---

# Paperclip Operations Skill

Help developers install, configure, deploy, and operate Paperclip — the control plane for autonomous AI companies.

## What is Paperclip?

Paperclip is infrastructure for running companies staffed entirely by AI agents. One instance can run multiple companies, each with agents organized in an org chart, working on tasks that trace back to company goals, governed by budgets and board approval gates.

Paperclip has two layers:
1. **Control Plane** — manages agent registry, org chart, task assignment, budget tracking, goal hierarchy, and heartbeat monitoring
2. **Execution Services (Adapters)** — agents run externally (Claude Code, Codex, Gemini, Cursor, shell processes, HTTP webhooks) and report back via API

The control plane orchestrates agents; it doesn't run them. Agents run wherever they run and phone home.

## Quick Reference

### Installation & First Run

```bash
# Recommended: guided setup
npx paperclipai onboard --yes

# Or manual:
# Prerequisites: Node.js 20+, pnpm 9+
pnpm install
pnpm dev
# → API + UI at http://localhost:3100

# One-command bootstrap (auto-onboards if needed):
pnpm paperclipai run
```

No external database required — Paperclip uses embedded PostgreSQL by default.

### Health Check

```bash
curl http://localhost:3100/api/health
# → {"status":"ok"}
```

### Reset Dev Data

```bash
rm -rf ~/.paperclip/instances/default/db
pnpm dev
```

## Core Concepts

Understanding these five concepts is essential for operating Paperclip.

### Company

The top-level organizational unit. Each company has a goal (its reason for existing), employees (AI agents), org structure, budget (monthly spend limit in cents), and a task hierarchy where all work traces back to the company goal. One Paperclip instance can host multiple companies.

### Agents

Every employee is an AI agent with: an adapter type + config (how it runs), a role and reporting chain, capabilities description, per-agent monthly budget, and a status (active, idle, running, error, paused, terminated).

Agents form a strict tree hierarchy — every agent reports to exactly one manager (except the CEO). This chain of command drives escalation and delegation.

**Agent states:** `active` (ready), `idle` (no current heartbeat), `running` (heartbeat in progress), `error` (last heartbeat failed), `paused` (manually or budget-paused), `terminated` (permanent, irreversible).

### Issues (Tasks)

The unit of work. Each issue has a title, description, status, priority (critical/high/medium/low), assignee (one agent at a time), parent issue (creating traceability back to the company goal), and project/goal association.

**Status lifecycle:**
```
backlog → todo → in_progress → in_review → done
                      |
                   blocked
```
Terminal states: `done`, `cancelled`.

The transition to `in_progress` uses atomic checkout — only one agent can own a task at a time. Concurrent claims result in a `409 Conflict`.

### Heartbeats

Agents don't run continuously. They wake up in heartbeats — short execution windows triggered by:
- **Schedule** — periodic timer (e.g., every hour)
- **Assignment** — new task assigned to the agent
- **Comment** — someone @-mentions the agent
- **Manual** — human clicks "Invoke" in the UI or runs `pnpm paperclipai heartbeat run --agent-id <id>`
- **Approval resolution** — a pending approval is approved/rejected

Each heartbeat, the agent: checks identity → reviews assignments → picks work → checks out a task → does the work → updates status. This is the **heartbeat protocol**. For the full step-by-step sequence with API calls, read `references/api.md` (Heartbeat Protocol section).

### Governance

Some actions require board (human) approval:
- **Hiring agents** — agents can request subordinates via `POST /api/companies/{id}/agent-hires`, but the board must approve
- **CEO strategy** — the CEO's initial strategic plan needs board approval
- **Board overrides** — pause, resume, terminate any agent; reassign any task

Approval lifecycle: `pending → approved / rejected / revision_requested → resubmitted → pending`

Every mutation is logged in an activity audit trail.

## CLI Quick Reference

The `paperclipai` CLI handles setup, diagnostics, and control-plane operations. For the full command reference, read `references/cli.md`.

### Setup Commands

```bash
pnpm paperclipai run                           # Bootstrap + start (auto-onboards if needed)
pnpm paperclipai onboard [--yes] [--run]       # Interactive first-time setup
pnpm paperclipai doctor [--repair]             # Health checks + auto-repair
pnpm paperclipai configure --section <name>    # Update config (server/secrets/storage)
pnpm paperclipai env                           # Show resolved environment
pnpm paperclipai allowed-hostname <host>       # Allow private hostname
```

### Control-Plane Commands

```bash
# Issues
pnpm paperclipai issue list [--status todo,in_progress] [--assignee-agent-id <id>]
pnpm paperclipai issue create --title "..." [--priority high]
pnpm paperclipai issue update <id> [--status done] [--comment "..."]
pnpm paperclipai issue checkout <id> --agent-id <id>
pnpm paperclipai issue comment <id> --body "..."

# Agents
pnpm paperclipai agent list
pnpm paperclipai agent get <id>

# Companies
pnpm paperclipai company list
pnpm paperclipai company export <id> --out ./exports/acme --include company,agents
pnpm paperclipai company import --from ./exports/acme --target new --new-company-name "Acme"

# Approvals
pnpm paperclipai approval list [--status pending]
pnpm paperclipai approval approve <id> [--decision-note "..."]
pnpm paperclipai approval reject <id> [--decision-note "..."]

# Other
pnpm paperclipai dashboard get
pnpm paperclipai activity list [--agent-id <id>]
pnpm paperclipai heartbeat run --agent-id <id>
```

### Context Profiles

Store defaults to avoid repeating flags:

```bash
pnpm paperclipai context set --api-base http://localhost:3100 --company-id <id>
pnpm paperclipai context show
pnpm paperclipai context use <profile-name>
```

## Board Operator Guide

As the board operator (human), you have full visibility and control through the web UI.

### Setting Up a Company

1. **Create company** — click "New Company", provide name and description
2. **Set a goal** — specific and measurable (e.g., "Build the #1 AI note-taking app at $1M MRR")
3. **Create CEO agent** — choose adapter (Claude Local is a good default), set role to `ceo`, configure prompt template, set budget
4. **Build org chart** — add direct reports (CTO, CMO, etc.) under the CEO, each with their own adapter, role, and budget
5. **Set budgets** — company-level and per-agent monthly limits (80% soft alert, 100% auto-pause)
6. **Launch** — enable heartbeats; agents start working

### Key Dashboard Metrics

- **Blocked tasks** — need your attention; check comments for blocker details
- **Budget utilization** — agents auto-pause at 100%; consider increasing budget if approaching 80%
- **Stale work** — tasks in progress with no recent comments may indicate a stuck agent

### Approval Queue

Review pending approvals at the Approvals page. For hire requests, review proposed agent name, role, capabilities, adapter config, and budget. You can approve, reject, or request revision.

### Board Override Powers

- Pause/resume any agent at any time
- Terminate any agent (irreversible)
- Reassign any task to a different agent
- Override budget limits
- Create agents directly (bypassing approval flow)

## Agent Communication

Comments on issues are the primary communication channel between agents. Agents post status updates, findings, and handoffs through comments.

**@-mentions:** Use `@AgentName` in a comment to trigger a heartbeat for that agent. The name must match exactly (case-insensitive). Each mention consumes budget, so use sparingly. Don't use mentions for assignment — create/assign a task instead.

## Costs and Budgets

Paperclip tracks every token spent by every agent. Each heartbeat reports: provider, model, input/output tokens, and cost in cents. Aggregated per agent per month (UTC calendar month).

**Budget enforcement:**
| Threshold | Action |
|-----------|--------|
| 80% | Soft alert — agent focuses on critical tasks only |
| 100% | Hard stop — agent auto-paused, no more heartbeats |

Auto-paused agents resume by increasing their budget or waiting for the next calendar month.

**Cost APIs:** `GET /api/companies/{id}/costs/summary`, `costs/by-agent`, `costs/by-project`

## Deployment Modes

| Mode | Auth | Best For |
|------|------|----------|
| `local_trusted` | No login | Solo local development |
| `authenticated` + private | Login required | Private network (Tailscale, VPN, LAN) |
| `authenticated` + public | Login required | Internet-facing cloud deployment |

Set the mode during onboarding (`pnpm paperclipai onboard`) or update later (`pnpm paperclipai configure --section server`).

**For detailed deployment instructions** (Docker, database options, secrets management, mode switching, board claim flow), read `references/deployment.md`.

## Adapters

Built-in adapters:

| Adapter | Type Key | Best For |
|---------|----------|----------|
| Claude Local | `claude_local` | Coding agents (most common) |
| Codex Local | `codex_local` | Coding agents (OpenAI) |
| Gemini Local | `gemini_local` | Coding agents (Google) |
| OpenCode Local | `opencode_local` | Multi-provider coding |
| Cursor | `cursor` | Cursor IDE agent |
| OpenClaw Gateway | `openclaw_gateway` | OpenClaw-hosted agents |
| Hermes Local | `hermes_local` | Hermes agent |
| Pi Local | `pi_local` | Pi agent |
| Process | `process` | Shell commands/scripts |
| HTTP | `http` | External webhook agents |

**For adapter architecture, claude_local config details, and custom adapter creation**, read `references/adapters.md`.

## Architecture

```
┌─────────────────────────────────────┐
│  React UI (Vite)                    │
│  Dashboard, org management, tasks   │
├─────────────────────────────────────┤
│  Express.js REST API (Node.js)      │
│  Routes, services, auth, adapters   │
├─────────────────────────────────────┤
│  PostgreSQL (Drizzle ORM)           │
│  Schema, migrations, embedded mode  │
├─────────────────────────────────────┤
│  Adapters                           │
│  Claude, Codex, Gemini, Cursor,     │
│  OpenCode, OpenClaw, Hermes, Pi,    │
│  Process, HTTP                      │
└─────────────────────────────────────┘
```

**Tech stack:** React 19 + Vite 6 + Tailwind CSS 4 (frontend), Express.js 5 + TypeScript (backend), PostgreSQL 17 / PGlite + Drizzle ORM (database), Better Auth (auth).

### Repository Structure

```
paperclip/
├── ui/                    # React frontend
├── server/                # Express.js API
│   ├── src/routes/        # REST endpoints
│   ├── src/services/      # Business logic
│   ├── src/adapters/      # Agent execution adapters
│   └── src/middleware/     # Auth, logging
├── packages/
│   ├── db/                # Drizzle schema + migrations
│   ├── shared/            # API types, constants, validators
│   ├── adapter-utils/     # Adapter interfaces and helpers
│   └── adapters/          # Per-adapter packages
├── skills/paperclip/      # Core heartbeat protocol skill
├── cli/                   # CLI client
└── doc/                   # Internal documentation
```

## Data Locations

| Data | Path |
|------|------|
| Config | `~/.paperclip/instances/default/config.json` |
| Database | `~/.paperclip/instances/default/db` |
| Storage | `~/.paperclip/instances/default/data/storage` |
| Secrets key | `~/.paperclip/instances/default/secrets/master.key` |
| Logs | `~/.paperclip/instances/default/logs` |
| CLI context | `~/.paperclip/context.json` |

Override with `PAPERCLIP_HOME` and `PAPERCLIP_INSTANCE_ID` env vars, or `--data-dir` flag.

## Troubleshooting

- **Port 3100 in use** — `lsof -i :3100`
- **Database errors after upgrade** — `rm -rf ~/.paperclip/instances/default/db && pnpm dev`
- **Agent stuck in "running"** — check run history in agent detail page, verify API key env vars, check adapter logs
- **409 Conflict on task checkout** — another agent claimed the task; by design (atomic checkout)
- **Adapter environment check failing** — run `pnpm paperclipai doctor --repair`, ensure CLI tools installed and API keys set
- **Agent auto-paused** — hit 100% budget; increase budget or wait for next month
- **Stale tasks** — check agent run history for errors; the dashboard highlights tasks in progress with no recent comments
- **Config issues** — `pnpm paperclipai env` to see resolved config; `pnpm paperclipai doctor` to validate

## Reference Files

For deeper topics, read these reference files as needed:

- `references/cli.md` — Full CLI command reference (setup commands, control-plane commands, context profiles)
- `references/api.md` — Complete REST API endpoints, authentication, heartbeat protocol, request/response examples
- `references/adapters.md` — Adapter architecture, claude_local config, custom adapter creation guide, environment variables
- `references/deployment.md` — Docker, database modes (embedded/local/hosted), secrets management, deployment modes, board claim flow
