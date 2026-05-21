# Portainer Stack Setup

IMPORTANT:
This project already migrated to Komodo.
Portainer approach did not work. The init script for postgress did not run, because Portainer stack only operates on the compose file itself, and any relative bind-mounts (e.g. `./postgres/init.sh`) resolve to a missing path. Docker silently creates a directory there instead of a file. The scrips is never executed.

## Deploying from Git repository

In Portainer → Stacks → Add stack → **Repository**.

| Field                | Value                    |
| -------------------- | ------------------------ |
| Repository URL       | your repo URL            |
| Repository reference | `refs/heads/main`        |
| Compose path         | `n8n/docker-compose.yml` |
| Additional paths     | `n8n/postgres/init.sh`   |

**Additional paths is required.** Without it Portainer only fetches the compose file itself — any relative bind-mounts (e.g. `./postgres/init.sh`) will resolve to a missing path, and Docker silently creates a directory there instead of a file. The postgres entrypoint then fails with:

```
/docker-entrypoint-initdb.d/init.sh: Is a directory
```

## Environment variables

Set these in Portainer → Stack → Environment variables:

```
POSTGRES_USER
POSTGRES_PASSWORD
N8N_DB
N8N_DB_USER
N8N_DB_PASSWORD
REALESTATE_DB
REALESTATE_DB_USER
REALESTATE_DB_PASSWORD
N8N_ENCRYPTION_KEY
N8N_USER
N8N_PASSWORD
```

## Fresh deploy (first time or after wiping data)

The postgres init script only runs on an empty data directory. If the volume already exists from a previous broken deploy, remove it first:

Portainer → Volumes → `real-estate-search-flow_postgres_storage` → Remove

Then redeploy the stack.
