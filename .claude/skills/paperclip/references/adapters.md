# Paperclip Adapters Reference

## Table of Contents
1. [What Are Adapters](#what-are-adapters)
2. [Built-in Adapters](#built-in-adapters)
3. [Claude Local Adapter](#claude-local-adapter)
4. [Adapter Architecture](#adapter-architecture)
5. [Request Flow](#request-flow)
6. [Creating Custom Adapters](#creating-custom-adapters)

---

## What Are Adapters

Adapters are the bridge between Paperclip's control plane and the runtimes where agents execute. Paperclip doesn't run agents — it orchestrates them. Adapters handle spawning an agent process, passing it the right context, and capturing results.

When a heartbeat fires, Paperclip looks up the agent's `adapterType` and `adapterConfig`, calls the adapter's `execute()` function with execution context, and the adapter spawns/calls the agent runtime, captures stdout, parses usage/cost data, and returns a structured result.

---

## Built-in Adapters

| Adapter | Type Key | Description |
|---------|----------|-------------|
| Claude Local | `claude_local` | Runs Claude Code CLI locally |
| Codex Local | `codex_local` | Runs OpenAI Codex CLI locally |
| Gemini Local | `gemini_local` | Runs Gemini CLI locally |
| OpenCode Local | `opencode_local` | Runs OpenCode CLI locally (multi-provider) |
| Cursor Local | `cursor` | Runs Cursor CLI locally |
| OpenClaw Gateway | `openclaw_gateway` | Sends wake payloads to OpenClaw gateway |
| Hermes Local | `hermes_local` | Runs Hermes Agent CLI locally |
| Pi Local | `pi_local` | Runs Pi CLI locally |
| Process | `process` | Executes arbitrary shell commands |
| HTTP | `http` | Sends webhooks to external agents |

### Choosing an Adapter

- **Coding agent?** → `claude_local`, `codex_local`, `gemini_local`, or `opencode_local`
- **Run a script or command?** → `process`
- **Call an external service?** → `http`
- **Something custom?** → Create your own adapter

---

## Claude Local Adapter

The most commonly used adapter. Runs Anthropic's Claude Code CLI with session persistence, skills injection, and structured output parsing.

### Prerequisites

- Claude Code CLI installed (`claude` command available)
- `ANTHROPIC_API_KEY` set in environment or agent config

### Configuration Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `cwd` | string | Yes | Working directory (absolute path; auto-created if missing) |
| `model` | string | No | Claude model (e.g. `claude-opus-4-6`) |
| `promptTemplate` | string | No | Prompt used for all runs |
| `env` | object | No | Environment variables (supports secret refs) |
| `timeoutSec` | number | No | Process timeout (0 = no timeout) |
| `graceSec` | number | No | Grace period before force-kill |
| `maxTurnsPerRun` | number | No | Max agentic turns per heartbeat |
| `dangerouslySkipPermissions` | boolean | No | Skip permission prompts (dev only) |

### Prompt Templates

Templates support `{{variable}}` substitution:

| Variable | Value |
|----------|-------|
| `{{agentId}}` | Agent's ID |
| `{{companyId}}` | Company ID |
| `{{runId}}` | Current run ID |
| `{{agent.name}}` | Agent's name |
| `{{company.name}}` | Company name |

### Session Persistence

The adapter persists Claude Code session IDs between heartbeats. On next wake, it resumes the existing conversation so the agent retains full context. Session resume is cwd-aware — if the working directory changed, a fresh session starts. Unknown session errors trigger automatic retry with a fresh session.

### Skills Injection

Creates a temporary directory with symlinks to Paperclip skills and passes it via `--add-dir`. Skills are discoverable without polluting the agent's working directory.

### Environment Test

Use the "Test Environment" button in the UI to validate: CLI installed, working directory available, API key/auth mode, live hello probe.

---

## Adapter Architecture

Each adapter is a package with three modules:

```
packages/adapters/<name>/
  src/
    index.ts              # Shared metadata (type, label, models)
    server/
      execute.ts          # Core execution logic
      parse.ts            # Output parsing
      test.ts             # Environment diagnostics
    ui/
      parse-stdout.ts     # Stdout → transcript entries for run viewer
      build-config.ts     # Form values → adapterConfig JSON
    cli/
      format-event.ts     # Terminal output for `paperclipai run --watch`
```

Three registries consume these modules:

| Registry | What it does |
|----------|-------------|
| Server | Executes agents, captures results |
| UI | Renders run transcripts, provides config forms |
| CLI | Formats terminal output for live watching |

---

## Request Flow

When a heartbeat fires:

1. **Trigger** — scheduler, manual invoke, or event fires the heartbeat
2. **Adapter invocation** — server calls `execute()` with agent identity, assignments, resolved env vars, and prompt
3. **Agent process** — adapter spawns agent runtime with Paperclip env vars injected
4. **Agent work** — agent calls Paperclip REST API (check identity, review assignments, checkout tasks, do work, update status)
5. **Result capture** — adapter captures stdout, parses usage/cost data, extracts session state
6. **Run record** — server records run result, costs, duration, and session state for next heartbeat

### Agent Environment Variables

| Variable | Description |
|----------|-------------|
| `PAPERCLIP_AGENT_ID` | Agent's unique ID |
| `PAPERCLIP_COMPANY_ID` | Company the agent belongs to |
| `PAPERCLIP_API_URL` | Base URL for the Paperclip API |
| `PAPERCLIP_API_KEY` | Short-lived JWT for API auth |
| `PAPERCLIP_RUN_ID` | Current heartbeat run ID |
| `PAPERCLIP_TASK_ID` | Issue that triggered this wake (if applicable) |
| `PAPERCLIP_WAKE_REASON` | Why the agent was woken (e.g. `issue_assigned`, `issue_comment_mentioned`) |
| `PAPERCLIP_WAKE_COMMENT_ID` | Specific comment that triggered this wake |
| `PAPERCLIP_APPROVAL_ID` | Approval that was resolved |
| `PAPERCLIP_APPROVAL_STATUS` | Approval decision (`approved`, `rejected`) |

---

## Creating Custom Adapters

Any runtime that can call an HTTP API can be a Paperclip agent.

### Step 1: Root Metadata

`src/index.ts` — imported by all three consumers, keep dependency-free:

```typescript
export const type = "my_agent";       // snake_case, globally unique
export const label = "My Agent (local)";
export const models = [
  { id: "model-a", label: "Model A" },
];
export const agentConfigurationDoc = `# my_agent configuration
Use when: ...
Don't use when: ...
Core fields: ...
`;
```

### Step 2: Server Execute

`src/server/execute.ts` — receives `AdapterExecutionContext`, returns `AdapterExecutionResult`:

- Read config using safe helpers (`asString`, `asNumber`, etc.)
- Build environment with `buildPaperclipEnv(agent)` plus context vars
- Resolve session state from `runtime.sessionParams`
- Render prompt with `renderTemplate(template, data)`
- Spawn the process with `runChildProcess()` or call via `fetch()`
- Parse output for usage, costs, session state, errors
- Handle unknown session errors (retry fresh, set `clearSession: true`)

### Step 3: Environment Test

`src/server/test.ts` — return structured diagnostics:
- `error` for invalid/unusable setup
- `warn` for non-blocking issues
- `info` for successful checks

### Step 4: UI Module

- `parse-stdout.ts` — converts stdout lines to `TranscriptEntry[]` for run viewer
- `build-config.ts` — converts form values to `adapterConfig` JSON
- Config fields React component in `ui/src/adapters/<name>/config-fields.tsx`

### Step 5: CLI Module

`format-event.ts` — pretty-prints stdout for `paperclipai run --watch` using `picocolors`.

### Step 6: Register

Add adapter to all three registries:

```
server/src/adapters/registry.ts
ui/src/adapters/registry.ts
cli/src/adapters/registry.ts
```

### Skills Injection Strategies

Make Paperclip skills discoverable to your agent runtime without writing to the agent's working directory:

1. **Best: tmpdir + flag** — create tmpdir, symlink skills, pass via CLI flag, clean up after
2. **Acceptable: global config dir** — symlink to the runtime's global plugins directory
3. **Acceptable: env var** — point a skills path env var at the repo's `skills/` directory
4. **Last resort: prompt injection** — include skill content in the prompt template

### Security

- Treat agent output as untrusted (parse defensively, never execute)
- Inject secrets via environment variables, not prompts
- Configure network access controls if the runtime supports them
- Always enforce timeout and grace period
