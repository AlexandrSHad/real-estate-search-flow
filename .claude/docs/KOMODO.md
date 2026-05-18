# Komodo Configuration

Komodo replaces Portainer as the Docker management layer for this project. It runs on the Raspberry Pi 5 alongside n8n and Postgres, and provides GitOps-based deployment of compose stacks with GitHub webhook integration.

> See [ADR-007](architecture-decisions.md#adr-007) for the rationale behind switching from Portainer.

---

## Architecture

Komodo consists of two components:

- **Core** — the web UI, REST/WebSocket API, and MongoDB-backed state store. Accessible on port `9120`.
- **Periphery** — an agent that runs on the same host (or remote hosts), executes Docker commands, and reports back to Core. It is what actually runs `docker compose up`.

Both are deployed via the official `mongo.compose.yaml`, which also includes MongoDB as the Komodo database.

---

## Installation

### 1. Download the official compose files

```bash
mkdir komodo && cd komodo
wget https://raw.githubusercontent.com/moghtech/komodo/main/compose/mongo.compose.yaml
wget https://raw.githubusercontent.com/moghtech/komodo/main/compose/compose.env
```

### 2. Edit `compose.env`

```env
# Image version
COMPOSE_KOMODO_IMAGE_TAG="2"

# Backup location on host
COMPOSE_KOMODO_BACKUPS_PATH=/etc/komodo/backups

# MongoDB credentials — never use defaults
KOMODO_DATABASE_USERNAME=komodo_admin
KOMODO_DATABASE_PASSWORD=<openssl rand -base64 32>

# Timezone
TZ=Europe/Prague

# Komodo host — use local IP or Tailscale address
KOMODO_HOST=http://<pi-ip>:9120
KOMODO_TITLE=Komodo

# First admin account
KOMODO_INIT_ADMIN_USERNAME=admin
KOMODO_INIT_ADMIN_PASSWORD=<strong password>

# Secrets — generate before first launch
KOMODO_WEBHOOK_SECRET=<openssl rand -hex 32>
KOMODO_JWT_SECRET=
KOMODO_JWT_TTL="1-day"

# Periphery root — all stack files must live under this path
PERIPHERY_ROOT_DIRECTORY=/etc/komodo
```

> **Security:** Set `chmod 600 compose.env` and never commit this file to git.
> Store a `compose.env.example` in the repo with placeholder values instead.

### 3. Deploy Komodo

```bash
docker compose -p komodo -f mongo.compose.yaml --env-file compose.env up -d
```

Komodo UI is available at `http://<pi-ip>:9120`.

---

## File Layout on the Pi

Periphery can only interact with files inside `PERIPHERY_ROOT_DIRECTORY`. All stack compose files must live under this path.

```
/etc/komodo/
├── stacks/
│   └── real-estate-search-flow/
│       ├── docker-compose.yml
│       └── postgres/
│           └── init.sh
└── backups/
```

---

## Configuring the Real Estate Stack

### Step 1 — Add a Git account (private repos only)

**Settings → Accounts → Git** — add a GitHub Personal Access Token.

### Step 2 — Create a Stack resource

**Stacks → New Stack**, then in the config tab:

| Field             | Value                     |
| ----------------- | ------------------------- |
| Server            | `Raspbery Pi 5`           |
| Git Provider      | `github.com`              |
| Git Account       | your GitHub account       |
| Repo              | `your-username/your-repo` |
| Branch            | `main`                    |
| Compose File Path | `n8n/docker-compose.yml`  |

### Step 3 — Set environment variables

In the Stack config **Environment** section, add all secrets that were previously set in Portainer. It is possible to copy the content of .env.example to that section and adjust the folowing values:

```
POSTGRES_USER=
POSTGRES_PASSWORD=
N8N_DB=
N8N_DB_USER=
N8N_DB_PASSWORD=
REALESTATE_DB=
REALESTATE_DB_USER=
REALESTATE_DB_PASSWORD=
N8N_ENCRYPTION_KEY=
N8N_USER=
N8N_PASSWORD=
```

### Step 4 — Deploy

Click **Deploy**. Monitor progress via:

- **Status badge** on the Stack page — shows live container state.
- **Logs tab** — raw `docker compose up` output, the first place to look on failure.
- **Services tab** — per-container health; useful to pinpoint which service failed.
- **Settings → Audit Log** — full history of all deploy actions.

---

## GitHub Webhook (Auto-deploy on Push)

This is not yet configured.

### Komodo side

On the Stack's Config page, scroll to **Webhooks** and copy the URL:

```
https://<komodo-host>/listener/github/stack/<stack-name>/deploy
```

### GitHub side

Go to your repo → **Settings → Webhooks → Add webhook**:

| Field        | Value                                               |
| ------------ | --------------------------------------------------- |
| Payload URL  | the URL copied from Komodo                          |
| Content type | `application/json`                                  |
| Secret       | value of `KOMODO_WEBHOOK_SECRET` from `compose.env` |
| Trigger      | Push events only                                    |

Komodo filters by branch — it only redeploys when a push matches the branch configured on the Stack (e.g. `main`), ignoring all other branches.

### Network requirement

GitHub must be able to reach Komodo. For a local Pi, use one of:

- **Tailscale Funnel** (recommended) — `tailscale funnel 9120` gives a public `*.ts.net` URL with no router config.
- **Router port forwarding** — forward port `9120` to the Pi. Only if comfortable exposing Komodo to the internet.

---

## Fresh Deploy (After Wiping Data)

Postgres only runs the init script on an empty data directory. If a volume exists from a previous broken deploy, remove it first via Komodo:

**Stacks → real-estate-search-flow → Services → postgres → Remove volume**

Or directly on the Pi:

```bash
docker volume rm real-estate-search-flow_postgres_storage
```

Then redeploy the stack.

---

## Database Separation

Komodo uses **MongoDB** for its own state (resource configs, audit logs, user accounts). This is separate from the **Postgres** container used by n8n and the real estate agent. Both databases run concurrently on the Pi — MongoDB is capped to `--wiredTigerCacheSizeGB 0.25` to stay lightweight.

| Database | Used by                | RAM     |
| -------- | ---------------------- | ------- |
| MongoDB  | Komodo Core            | ~0.2 GB |
| Postgres | n8n, real estate agent | ~0.3 GB |
