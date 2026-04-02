# Paperclip Deployment Reference

## Table of Contents
1. [Local Development](#local-development)
2. [Docker Deployment](#docker-deployment)
3. [Deployment Modes](#deployment-modes)
4. [Database Configuration](#database-configuration)
5. [Secrets Management](#secrets-management)

---

## Local Development

### Prerequisites
- Node.js 20+
- pnpm 9+

### Start Dev Server

```bash
pnpm install
pnpm dev
```

This starts the API server and UI at `http://localhost:3100`. No Docker or external database required — Paperclip uses embedded PostgreSQL automatically.

### One-Command Bootstrap

```bash
pnpm paperclipai run
```

Auto-onboards if config is missing, runs `paperclipai doctor` with repair enabled, then starts the server.

### Tailscale/Private Auth Dev Mode

```bash
pnpm dev --tailscale-auth
```

Binds server to `0.0.0.0` for private-network access. Allow additional hostnames:

```bash
pnpm paperclipai allowed-hostname my-machine
```

### Health Checks

```bash
curl http://localhost:3100/api/health    # → {"status":"ok"}
curl http://localhost:3100/api/companies # → []
```

### Reset Dev Data

```bash
rm -rf ~/.paperclip/instances/default/db
pnpm dev
```

### Data Locations

| Data | Path |
|------|------|
| Config | `~/.paperclip/instances/default/config.json` |
| Database | `~/.paperclip/instances/default/db` |
| Storage | `~/.paperclip/instances/default/data/storage` |
| Secrets key | `~/.paperclip/instances/default/secrets/master.key` |
| Logs | `~/.paperclip/instances/default/logs` |

Override with environment variables:

```bash
PAPERCLIP_HOME=/custom/path PAPERCLIP_INSTANCE_ID=dev pnpm paperclipai run
```

---

## Docker Deployment

### Compose Quickstart (Recommended)

```bash
docker compose -f docker-compose.quickstart.yml up --build
```

Open `http://localhost:3100`.

Defaults: host port 3100, data directory `./data/docker-paperclip`.

Override with env vars:

```bash
PAPERCLIP_PORT=3200 PAPERCLIP_DATA_DIR=./data/pc \
  docker compose -f docker-compose.quickstart.yml up --build
```

### Manual Docker Build

```bash
docker build -t paperclip-local .

docker run --name paperclip \
  -p 3100:3100 \
  -e HOST=0.0.0.0 \
  -e PAPERCLIP_HOME=/paperclip \
  -v "$(pwd)/data/docker-paperclip:/paperclip" \
  paperclip-local
```

### Data Persistence

All data persists under the bind mount (`./data/docker-paperclip`): embedded PostgreSQL data, uploaded assets, local secrets key, agent workspace data.

### Claude and Codex Adapters in Docker

The Docker image pre-installs `claude` (Anthropic Claude Code CLI) and `codex` (OpenAI Codex CLI). Pass API keys to enable adapter runs inside the container:

```bash
docker run --name paperclip \
  -p 3100:3100 \
  -e HOST=0.0.0.0 \
  -e PAPERCLIP_HOME=/paperclip \
  -e OPENAI_API_KEY=sk-... \
  -e ANTHROPIC_API_KEY=sk-... \
  -v "$(pwd)/data/docker-paperclip:/paperclip" \
  paperclip-local
```

Without API keys, the app runs normally — adapter environment checks will surface missing prerequisites.

---

## Deployment Modes

### local_trusted (Default)

Optimized for single-operator local use.

- **Host binding:** loopback only (localhost)
- **Authentication:** no login required
- **Board identity:** auto-created local board user

```bash
pnpm paperclipai onboard
# Choose "local_trusted"
```

### authenticated + private

For private network access (Tailscale, VPN, LAN).

- **Authentication:** login required via Better Auth
- **URL handling:** auto base URL mode
- **Host trust:** private-host trust policy required

```bash
pnpm paperclipai onboard
# Choose "authenticated" → "private"

# Allow custom Tailscale hostnames:
pnpm paperclipai allowed-hostname my-machine
```

### authenticated + public

For internet-facing deployment.

- **Authentication:** login required
- **URL:** explicit public URL required
- **Security:** stricter deployment checks in doctor

```bash
pnpm paperclipai onboard
# Choose "authenticated" → "public"
```

### Board Claim Flow

When migrating from `local_trusted` to `authenticated`, Paperclip emits a one-time claim URL at startup:

```
/board-claim/<token>?code=<code>
```

A signed-in user visits this URL to claim board ownership. This promotes the current user to instance admin, demotes the auto-created local board admin, and ensures active company membership for the claiming user.

### Changing Modes

```bash
pnpm paperclipai configure --section server
```

Runtime override:

```bash
PAPERCLIP_DEPLOYMENT_MODE=authenticated pnpm paperclipai run
```

---

## Database Configuration

Paperclip uses PostgreSQL via Drizzle ORM with three options:

### 1. Embedded PostgreSQL (Default)

Zero config. If `DATABASE_URL` is not set, the server starts an embedded PostgreSQL instance automatically.

On first start:
- Creates `~/.paperclip/instances/default/db/` for storage
- Ensures the `paperclip` database exists
- Runs migrations automatically
- Starts serving requests

Data persists across restarts. Reset with: `rm -rf ~/.paperclip/instances/default/db`

### 2. Local PostgreSQL (Docker)

```bash
docker compose up -d
# Starts PostgreSQL 17 on localhost:5432

cp .env.example .env
# Set DATABASE_URL=postgres://paperclip:paperclip@localhost:5432/paperclip

# Push schema:
DATABASE_URL=postgres://paperclip:paperclip@localhost:5432/paperclip \
  npx drizzle-kit push
```

### 3. Hosted PostgreSQL (e.g., Supabase)

1. Create a project at `database.new`
2. Copy connection string from Project Settings → Database
3. Set `DATABASE_URL` in `.env`

Use direct connection (port 5432) for migrations; pooled connection (port 6543) for the app.

If using connection pooling, disable prepared statements:

```typescript
// packages/db/src/client.ts
export function createDb(url: string) {
  const sql = postgres(url, { prepare: false });
  return drizzlePg(sql, { schema });
}
```

### Switching Between Modes

| DATABASE_URL | Mode |
|---|---|
| Not set | Embedded PostgreSQL |
| `postgres://...localhost...` | Local Docker PostgreSQL |
| `postgres://...supabase.com...` | Hosted Supabase |

The Drizzle schema (`packages/db/src/schema/`) is the same regardless of mode.

---

## Secrets Management

Paperclip encrypts secrets at rest using a local master key.

### Default Provider: local_encrypted

Secrets are encrypted with a local master key at:

```
~/.paperclip/instances/default/secrets/master.key
```

Auto-created during onboarding. The key never leaves your machine.

### CLI Setup

```bash
pnpm paperclipai onboard           # writes default secrets config
pnpm paperclipai configure --section secrets  # update settings
pnpm paperclipai doctor             # validate config
```

### Environment Overrides

| Variable | Description |
|---|---|
| `PAPERCLIP_SECRETS_MASTER_KEY` | 32-byte key as base64, hex, or raw string |
| `PAPERCLIP_SECRETS_MASTER_KEY_FILE` | Custom key file path |
| `PAPERCLIP_SECRETS_STRICT_MODE` | Set to `true` to enforce secret refs |

### Strict Mode

When enabled, sensitive env keys (matching `*_API_KEY`, `*_TOKEN`, `*_SECRET`) must use secret references instead of inline plain values.

```bash
PAPERCLIP_SECRETS_STRICT_MODE=true
```

Recommended for any deployment beyond local trusted.

### Migrating Inline Secrets

```bash
pnpm secrets:migrate-inline-env         # dry run
pnpm secrets:migrate-inline-env --apply # apply migration
```

### Secret References in Agent Config

Agent env vars use secret references:

```json
{
  "env": {
    "ANTHROPIC_API_KEY": {
      "type": "secret_ref",
      "secretId": "8f884973-c29b-44e4-8ea3-6413437f8081",
      "version": "latest"
    }
  }
}
```

The server resolves and decrypts these at runtime, injecting the real value into the agent process environment.
