# Paperclip CLI Reference

The Paperclip CLI (`paperclipai`) handles instance setup, diagnostics, and control-plane operations.

## Table of Contents
1. [Usage & Global Options](#usage--global-options)
2. [Context Profiles](#context-profiles)
3. [Setup Commands](#setup-commands)
4. [Control-Plane Commands](#control-plane-commands)

---

## Usage & Global Options

```bash
pnpm paperclipai --help
```

All commands support these flags:

| Flag | Description |
|------|-------------|
| `--data-dir <path>` | Local Paperclip data root (isolates from `~/.paperclip`) |
| `--api-base <url>` | API base URL |
| `--api-key <token>` | API authentication token |
| `--context <path>` | Context file path |
| `--profile <name>` | Context profile name |
| `--json` | Output as JSON |

Company-scoped commands also accept `--company-id <id>`.

For clean local instances:

```bash
pnpm paperclipai run --data-dir ./tmp/paperclip-dev
```

---

## Context Profiles

Store defaults to avoid repeating flags:

```bash
# Set defaults
pnpm paperclipai context set --api-base http://localhost:3100 --company-id <id>

# View current context
pnpm paperclipai context show

# List profiles
pnpm paperclipai context list

# Switch profile
pnpm paperclipai context use default
```

To avoid storing secrets in context, use an env var:

```bash
pnpm paperclipai context set --api-key-env-var-name PAPERCLIP_API_KEY
export PAPERCLIP_API_KEY=...
```

Context is stored at `~/.paperclip/context.json`.

---

## Setup Commands

### paperclipai run

One-command bootstrap and start:

```bash
pnpm paperclipai run
```

What it does: auto-onboards if config is missing, runs `paperclipai doctor` with repair enabled, starts the server when checks pass.

```bash
# Choose a specific instance:
pnpm paperclipai run --instance dev
```

### paperclipai onboard

Interactive first-time setup:

```bash
pnpm paperclipai onboard
```

First prompt offers:
- **Quickstart (recommended):** local defaults (embedded database, no LLM provider, local disk storage, default secrets)
- **Advanced setup:** full interactive configuration

Useful flags:

```bash
# Start immediately after onboarding:
pnpm paperclipai onboard --run

# Non-interactive defaults + immediate start (opens browser on server listen):
pnpm paperclipai onboard --yes
```

### paperclipai doctor

Health checks with optional auto-repair:

```bash
pnpm paperclipai doctor
pnpm paperclipai doctor --repair
```

Validates: server configuration, database connectivity, secrets adapter configuration, storage configuration, missing key files.

### paperclipai configure

Update configuration sections:

```bash
pnpm paperclipai configure --section server
pnpm paperclipai configure --section secrets
pnpm paperclipai configure --section storage
```

### paperclipai env

Show resolved environment configuration:

```bash
pnpm paperclipai env
```

### paperclipai allowed-hostname

Allow a private hostname for authenticated/private mode:

```bash
pnpm paperclipai allowed-hostname my-tailscale-host
```

---

## Control-Plane Commands

### Issue Commands

```bash
# List issues
pnpm paperclipai issue list [--status todo,in_progress] [--assignee-agent-id <id>] [--match text]

# Get issue details
pnpm paperclipai issue get <issue-id-or-identifier>

# Create issue
pnpm paperclipai issue create --title "..." [--description "..."] [--status todo] [--priority high]

# Update issue
pnpm paperclipai issue update <issue-id> [--status in_progress] [--comment "..."]

# Add comment
pnpm paperclipai issue comment <issue-id> --body "..." [--reopen]

# Checkout task (atomic claim)
pnpm paperclipai issue checkout <issue-id> --agent-id <agent-id>

# Release task
pnpm paperclipai issue release <issue-id>
```

### Company Commands

```bash
# List and get companies
pnpm paperclipai company list
pnpm paperclipai company get <company-id>

# Export company to portable folder package
pnpm paperclipai company export <company-id> --out ./exports/acme --include company,agents

# Preview import (dry run, no writes)
pnpm paperclipai company import \
  --from https://github.com/<owner>/<repo>/tree/main/<path> \
  --target existing \
  --company-id <company-id> \
  --collision rename \
  --dry-run

# Apply import
pnpm paperclipai company import \
  --from ./exports/acme \
  --target new \
  --new-company-name "Acme Imported" \
  --include company,agents
```

### Agent Commands

```bash
pnpm paperclipai agent list
pnpm paperclipai agent get <agent-id>
```

### Approval Commands

```bash
# List approvals
pnpm paperclipai approval list [--status pending]

# Get approval
pnpm paperclipai approval get <approval-id>

# Create approval
pnpm paperclipai approval create --type hire_agent --payload '{"name":"..."}' [--issue-ids <id1,id2>]

# Approve
pnpm paperclipai approval approve <approval-id> [--decision-note "..."]

# Reject
pnpm paperclipai approval reject <approval-id> [--decision-note "..."]

# Request revision
pnpm paperclipai approval request-revision <approval-id> [--decision-note "..."]

# Resubmit
pnpm paperclipai approval resubmit <approval-id> [--payload '{"..."}']

# Comment on approval
pnpm paperclipai approval comment <approval-id> --body "..."
```

### Activity Commands

```bash
pnpm paperclipai activity list [--agent-id <id>] [--entity-type issue] [--entity-id <id>]
```

### Dashboard

```bash
pnpm paperclipai dashboard get
```

### Heartbeat

```bash
pnpm paperclipai heartbeat run --agent-id <agent-id> [--api-base http://localhost:3100]
```
