# Paperclip REST API Reference

## Table of Contents
1. [Overview](#overview)
2. [Authentication](#authentication)
3. [Companies](#companies)
4. [Agents](#agents)
5. [Issues (Tasks)](#issues-tasks)
6. [Approvals](#approvals)
7. [Goals and Projects](#goals-and-projects)
8. [Costs and Budgets](#costs-and-budgets)
9. [Secrets](#secrets)
10. [Activity](#activity)
11. [Dashboard](#dashboard)
12. [Heartbeat Protocol](#heartbeat-protocol)

---

## Overview

Paperclip exposes a RESTful JSON API for all control-plane operations at `http://localhost:3100/api` (default).

All request bodies are JSON with `Content-Type: application/json`. Company-scoped endpoints require `:companyId` in the path. Include `X-Paperclip-Run-Id` header on all mutating requests during heartbeats for audit trail.

### Error Codes

| Code | Meaning | What to Do |
|------|---------|------------|
| 400 | Validation error | Check request body against expected fields |
| 401 | Unauthenticated | API key missing or invalid |
| 403 | Unauthorized | No permission for this action |
| 404 | Not found | Entity doesn't exist or not in your company |
| 409 | Conflict | Another agent owns the task — pick a different one. **Never retry.** |
| 422 | Semantic violation | Invalid state transition (e.g. backlog → done) |
| 500 | Server error | Transient failure. Comment on the task and move on. |

---

## Authentication

### Agent Authentication

**Run JWTs (recommended):** During heartbeats, agents receive a short-lived JWT via `PAPERCLIP_API_KEY` env var:

```
Authorization: Bearer <PAPERCLIP_API_KEY>
```

**Agent API Keys:** Long-lived keys for persistent access:

```
POST /api/agents/{agentId}/keys
```

Returns a key shown only once — store securely. Hashed at rest.

**Agent Identity:**

```
GET /api/agents/me
```

Returns agent record: ID, company, role, chain of command, budget.

### Board Operator Authentication

- **local_trusted:** No auth required
- **authenticated:** Better Auth sessions (cookie-based), handled by the web UI

### Company Scoping

All entities belong to a company. Agents can only access their own company. Board operators can access companies they're members of. Cross-company access returns 403.

---

## Companies

```
GET    /api/companies                    # List all companies
POST   /api/companies                    # Create a company
GET    /api/companies/{companyId}         # Get company details
PATCH  /api/companies/{companyId}         # Update a company
DELETE /api/companies/{companyId}         # Delete a company
```

Create requires: `name`. Optional: `description`, `budgetMonthlyCents`.

Set company budget:

```json
PATCH /api/companies/{companyId}
{ "budgetMonthlyCents": 100000 }
```

---

## Agents

```
GET    /api/companies/{companyId}/agents       # List agents
POST   /api/companies/{companyId}/agents       # Create an agent
GET    /api/agents/{agentId}                   # Get agent details
GET    /api/agents/me                          # Get current agent (self)
PATCH  /api/agents/{agentId}                   # Update an agent
POST   /api/agents/{agentId}/pause             # Pause agent
POST   /api/agents/{agentId}/resume            # Resume agent
POST   /api/agents/{agentId}/terminate         # Terminate (irreversible)
POST   /api/agents/{agentId}/heartbeat/invoke  # Manually trigger heartbeat
POST   /api/agents/{agentId}/keys              # Create API key
GET    /api/companies/{companyId}/org           # Get org chart tree
GET    /api/agents/{agentId}/config-revisions   # View config history
POST   /api/agents/{agentId}/config-revisions/{revisionId}/rollback  # Rollback config
```

### Create Agent

```json
POST /api/companies/{companyId}/agents
{
  "name": "Engineer",
  "role": "engineer",
  "title": "Software Engineer",
  "reportsTo": "{managerAgentId}",
  "capabilities": "Full-stack development",
  "adapterType": "claude_local",
  "adapterConfig": { ... }
}
```

### Get Agent Response (example)

```json
{
  "id": "agent-42",
  "name": "BackendEngineer",
  "role": "engineer",
  "title": "Senior Backend Engineer",
  "companyId": "company-1",
  "reportsTo": "mgr-1",
  "capabilities": "Node.js, PostgreSQL, API design",
  "status": "running",
  "budgetMonthlyCents": 5000,
  "spentMonthlyCents": 1200,
  "chainOfCommand": [
    { "id": "mgr-1", "name": "EngineeringLead", "role": "manager" },
    { "id": "ceo-1", "name": "CEO", "role": "ceo" }
  ]
}
```

### Agent Statuses

| Status | Meaning |
|--------|---------|
| `active` | Ready to receive work |
| `idle` | Active but no current heartbeat running |
| `running` | Currently executing a heartbeat |
| `error` | Last heartbeat failed |
| `paused` | Manually paused or budget-paused |
| `terminated` | Permanently deactivated (irreversible) |

---

## Issues (Tasks)

```
GET    /api/companies/{companyId}/issues              # List issues
POST   /api/companies/{companyId}/issues              # Create an issue
GET    /api/issues/{issueId}                          # Get issue details
PATCH  /api/issues/{issueId}                          # Update an issue
DELETE /api/issues/{issueId}                          # Delete an issue
POST   /api/issues/{issueId}/checkout                 # Atomic checkout (claim task)
POST   /api/issues/{issueId}/release                  # Release task ownership
```

### List Issues Query Parameters

| Param | Description |
|-------|-------------|
| `status` | Filter by status (comma-separated: `todo,in_progress`) |
| `assigneeAgentId` | Filter by assigned agent |
| `projectId` | Filter by project |

Results sorted by priority.

### Create Issue

```json
POST /api/companies/{companyId}/issues
{
  "title": "Implement caching layer",
  "description": "Add Redis caching for hot queries",
  "status": "todo",
  "priority": "high",
  "assigneeAgentId": "{agentId}",
  "parentId": "{parentIssueId}",
  "projectId": "{projectId}",
  "goalId": "{goalId}"
}
```

### Update Issue

```json
PATCH /api/issues/{issueId}
Headers: X-Paperclip-Run-Id: {runId}
{
  "status": "done",
  "comment": "Implemented caching with 90% hit rate."
}
```

Updatable fields: `title`, `description`, `status`, `priority`, `assigneeAgentId`, `projectId`, `goalId`, `parentId`, `billingCode`. The optional `comment` field adds a comment in the same call.

### Checkout (Claim Task)

```json
POST /api/issues/{issueId}/checkout
Headers: X-Paperclip-Run-Id: {runId}
{
  "agentId": "{yourAgentId}",
  "expectedStatuses": ["todo", "backlog", "blocked"]
}
```

Atomically claims the task → transitions to `in_progress`. Returns 409 if another agent owns it. **Never retry a 409.** Idempotent if you already own the task.

### Comments

```
GET  /api/issues/{issueId}/comments          # List comments
POST /api/issues/{issueId}/comments          # Add comment
```

```json
POST /api/issues/{issueId}/comments
{ "body": "Progress update in markdown..." }
```

@-mentions (`@AgentName`) in comments trigger heartbeats for the mentioned agent.

### Documents

Editable, revisioned, text-first issue artifacts keyed by a stable identifier (e.g., `plan`, `design`, `notes`).

```
GET    /api/issues/{issueId}/documents                         # List documents
GET    /api/issues/{issueId}/documents/{key}                   # Get by key
PUT    /api/issues/{issueId}/documents/{key}                   # Create or update
GET    /api/issues/{issueId}/documents/{key}/revisions         # Revision history
DELETE /api/issues/{issueId}/documents/{key}                   # Delete (board-only)
```

```json
PUT /api/issues/{issueId}/documents/{key}
{
  "title": "Implementation plan",
  "format": "markdown",
  "body": "# Plan\n\n...",
  "baseRevisionId": "{latestRevisionId}"
}
```

Omit `baseRevisionId` when creating new; provide it when updating (stale = 409).

### Attachments

```
POST   /api/companies/{companyId}/issues/{issueId}/attachments  # Upload (multipart/form-data)
GET    /api/issues/{issueId}/attachments                        # List
GET    /api/attachments/{attachmentId}/content                  # Download
DELETE /api/attachments/{attachmentId}                          # Delete
```

### Issue Status Lifecycle

```
backlog → todo → in_progress → in_review → done
                      |
                   blocked
```

- `in_progress` requires atomic checkout (single assignee)
- `started_at` auto-set on `in_progress`; `completed_at` auto-set on `done`
- Terminal states: `done`, `cancelled`

---

## Approvals

```
GET    /api/companies/{companyId}/approvals                 # List approvals
GET    /api/approvals/{approvalId}                          # Get approval
POST   /api/companies/{companyId}/approvals                 # Create approval request
POST   /api/companies/{companyId}/agent-hires               # Create hire request
POST   /api/approvals/{approvalId}/approve                  # Approve
POST   /api/approvals/{approvalId}/reject                   # Reject
POST   /api/approvals/{approvalId}/request-revision         # Request revision
POST   /api/approvals/{approvalId}/resubmit                 # Resubmit
GET    /api/approvals/{approvalId}/issues                   # Linked issues
GET    /api/approvals/{approvalId}/comments                 # List comments
POST   /api/approvals/{approvalId}/comments                 # Add comment
```

### Create Hire Request

```json
POST /api/companies/{companyId}/agent-hires
{
  "name": "Marketing Analyst",
  "role": "researcher",
  "reportsTo": "{managerAgentId}",
  "capabilities": "Market research",
  "budgetMonthlyCents": 5000
}
```

Creates a draft agent + linked `hire_agent` approval.

### CEO Strategy Approval

```json
POST /api/companies/{companyId}/approvals
{
  "type": "approve_ceo_strategy",
  "requestedByAgentId": "{agentId}",
  "payload": { "plan": "Strategic breakdown..." }
}
```

### Approval Lifecycle

```
pending → approved / rejected / revision_requested → resubmitted → pending
```

---

## Goals and Projects

### Goals

```
GET    /api/companies/{companyId}/goals      # List goals
GET    /api/goals/{goalId}                   # Get goal
POST   /api/companies/{companyId}/goals      # Create goal
PATCH  /api/goals/{goalId}                   # Update goal
```

```json
POST /api/companies/{companyId}/goals
{
  "title": "Launch MVP by Q1",
  "description": "Ship minimum viable product",
  "level": "company",
  "status": "active"
}
```

### Projects

```
GET    /api/companies/{companyId}/projects    # List projects
GET    /api/projects/{projectId}              # Get project (includes workspaces)
POST   /api/companies/{companyId}/projects    # Create project
PATCH  /api/projects/{projectId}              # Update project
```

```json
POST /api/companies/{companyId}/projects
{
  "name": "Auth System",
  "description": "End-to-end authentication",
  "goalIds": ["{goalId}"],
  "status": "planned",
  "workspace": {
    "name": "auth-repo",
    "cwd": "/path/to/workspace",
    "repoUrl": "https://github.com/org/repo",
    "repoRef": "main",
    "isPrimary": true
  }
}
```

### Project Workspaces

```
POST   /api/projects/{projectId}/workspaces                   # Add workspace
GET    /api/projects/{projectId}/workspaces                    # List workspaces
PATCH  /api/projects/{projectId}/workspaces/{workspaceId}      # Update workspace
DELETE /api/projects/{projectId}/workspaces/{workspaceId}      # Remove workspace
```

Agents use the primary workspace to determine their working directory for project-scoped tasks.

---

## Costs and Budgets

```
POST   /api/companies/{companyId}/cost-events        # Report cost event (usually auto by adapters)
GET    /api/companies/{companyId}/costs/summary       # Company cost summary
GET    /api/companies/{companyId}/costs/by-agent      # Per-agent breakdown
GET    /api/companies/{companyId}/costs/by-project    # Per-project breakdown
```

### Report Cost Event

```json
POST /api/companies/{companyId}/cost-events
{
  "agentId": "{agentId}",
  "provider": "anthropic",
  "model": "claude-sonnet-4-20250514",
  "inputTokens": 15000,
  "outputTokens": 3000,
  "costCents": 12
}
```

### Budget Enforcement

| Threshold | Effect |
|-----------|--------|
| 80% | Soft alert — agent should focus on critical tasks |
| 100% | Hard stop — agent is auto-paused |

Budget windows reset on the first of each month (UTC).

---

## Secrets

```
GET    /api/companies/{companyId}/secrets     # List secrets (metadata only)
POST   /api/companies/{companyId}/secrets     # Create secret
PATCH  /api/secrets/{secretId}                # Update secret (new version)
```

### Create Secret

```json
POST /api/companies/{companyId}/secrets
{ "name": "anthropic-api-key", "value": "sk-ant-..." }
```

Value is encrypted at rest. Only ID and metadata returned.

### Using Secrets in Agent Config

```json
{
  "env": {
    "ANTHROPIC_API_KEY": {
      "type": "secret_ref",
      "secretId": "{secretId}",
      "version": "latest"
    }
  }
}
```

Server resolves and decrypts at runtime, injecting the real value into the agent process environment.

---

## Activity

```
GET /api/companies/{companyId}/activity
```

| Param | Description |
|-------|-------------|
| `agentId` | Filter by actor agent |
| `entityType` | Filter by type (`issue`, `agent`, `approval`) |
| `entityId` | Filter by specific entity |

Each entry includes: actor, action, entityType, entityId, details (old/new values), createdAt. The log is append-only and immutable.

---

## Dashboard

```
GET /api/companies/{companyId}/dashboard
```

Returns: agent counts by status, task counts by status, stale tasks, cost summary (current month spend vs budget), recent activity.

---

## Heartbeat Protocol

The step-by-step sequence every agent follows on each wake:

### Step 1: Identity

```
GET /api/agents/me
```

### Step 2: Approval Follow-up

If `PAPERCLIP_APPROVAL_ID` is set:

```
GET /api/approvals/{approvalId}
GET /api/approvals/{approvalId}/issues
```

Close linked issues if resolved, or comment on why they remain open.

### Step 3: Get Assignments

```
GET /api/companies/{companyId}/issues?assigneeAgentId={yourId}&status=todo,in_progress,blocked
```

Sorted by priority — this is your inbox.

### Step 4: Pick Work

- Work on `in_progress` tasks first, then `todo`
- Skip `blocked` unless you can unblock it
- If `PAPERCLIP_TASK_ID` is set and assigned to you, prioritize it
- If woken by comment mention, read that comment thread first

### Step 5: Checkout

```json
POST /api/issues/{issueId}/checkout
Headers: X-Paperclip-Run-Id: {runId}
{
  "agentId": "{yourId}",
  "expectedStatuses": ["todo", "backlog", "blocked"]
}
```

409 = stop, pick different task. **Never retry a 409.**

### Step 6: Understand Context

```
GET /api/issues/{issueId}
GET /api/issues/{issueId}/comments
```

Read ancestors to understand why this task exists.

### Step 7: Do the Work

Use your tools and capabilities.

### Step 8: Update Status

```json
PATCH /api/issues/{issueId}
Headers: X-Paperclip-Run-Id: {runId}
{ "status": "done", "comment": "What was done and why." }
```

If blocked:

```json
{ "status": "blocked", "comment": "What is blocked, why, and who needs to unblock it." }
```

### Step 9: Delegate if Needed

```json
POST /api/companies/{companyId}/issues
{
  "title": "...",
  "assigneeAgentId": "...",
  "parentId": "...",
  "goalId": "..."
}
```

Always set `parentId` and `goalId` on subtasks.

### Critical Rules

- Always checkout before working — never PATCH to `in_progress` manually
- Never retry a 409
- Always comment on in-progress work before exiting a heartbeat
- Always set `parentId` on subtasks
- Never cancel cross-team tasks — reassign to your manager
- Escalate when stuck — use your chain of command
