# Auto-Deploying a Docker Compose Stack to a Raspberry Pi 5 from GitHub — Alternatives to Portainer's Git Deploy

## The Real Problem to Solve

Portainer's "Deploy from Git repository" only writes the compose file (and any explicitly listed "Additional paths") into its own internal storage. Any *other* file your compose references via a relative bind‑mount — `./postgres/init.sh`, scripts, config, certs — is absent. Because Docker creates a missing bind‑mount source as an *empty directory*, the Postgres container then mounts a directory over `/docker-entrypoint-initdb.d/init.sh` and the init script never runs. The fix is conceptually trivial: **the deployment tool must `git clone` (or `git pull`) the whole repository onto the Pi's filesystem and then run `docker compose up -d` from that working copy**, so every relative path the compose file references resolves to a real file.

That single requirement disqualifies the entire class of "image‑level" updaters (Watchtower, Diun) and the entire class of opinionated PaaS tools that abstract the compose file away (Coolify, Dokploy, CapRover, Dokku). It leaves a small, well‑defined set of viable candidates, the best of which is **Komodo**.

---

## Candidate-by-Candidate Comparison

### 1. Watchtower — *Not a fit*
- **Model:** Pull/poll. Watches the Docker registry for new image digests on the *exact tag* a container was started with.
- **Full git clone on host?** No — Watchtower never touches your repo at all.
- **What it actually solves:** Refreshing a running container when its upstream image (e.g. `n8nio/n8n:latest`) gets a new digest. It re‑creates the container with the new image, reusing the original run parameters.
- **Why it doesn't help here:** Changes to `docker-compose.yml`, to `postgres/init.sh`, or to environment variables on GitHub are invisible to Watchtower. It also has a long‑standing documented gotcha — updates are locked to the running image tag; it does not follow semver. ARM64‑native, ~10–20 MB RAM. Still useful as a *complement* (e.g. keep `n8n:latest` fresh) but it cannot replace Portainer Git deploy.

### 2. Komodo (formerly Monitor, by moghtech) — *Top recommendation*
- **Model:** Hybrid. A Core service (typically on the Pi itself for a single‑host setup) plus a lightweight Periphery agent. Supports both GitHub webhook (push) and polling intervals (`KOMODO_RESOURCE_POLL_INTERVAL`).
- **Full git clone on host?** **Yes — this is the architectural default.** In "Git Repo" Stack mode the Periphery agent clones the entire repo into `/etc/komodo/stacks/<stack-name>/...` on the host, then runs `docker compose -f <run_directory>/<file_paths>` from inside that working copy. All relative paths in your compose file — `./postgres/init.sh` included — resolve correctly because they sit beside the compose file on the Pi's real filesystem. Komodo's FAQ states this explicitly: "For any project built from a dockerfile/compose.yaml file that is based on a git repo it must be possible to build it if the repo is cloned, so this is exactly what Komodo does."
- **ARM64 / Pi 5:** Fully supported. Core is published as multi‑arch images (`ghcr.io/moghtech/komodo-core`). Periphery is even smaller — a single Rust binary; one user reports `Memory: 4.9M (peak: 13.9M)` for the systemd agent. Core + FerretDB/Postgres backend on the Pi 5 sits comfortably under ~400 MB.
- **Setup complexity:** Medium. Two compose files (`compose.env` + `ferretdb.compose.yaml` or `mongo.compose.yaml`), an initial sign‑up via the UI, then one Stack created in the UI that points at your GitHub repo. For a single Pi, install Periphery in the *same* compose file as Core.
- **Secrets / env vars:** Three good options. (a) Built‑in **Variables & Secrets** store in Komodo with `[[VARIABLE]]` / `[[SECRET]]` interpolation into the compose's environment block, written to a `.env` file at deploy time. (b) An `environment` text field per Stack — also interpolated and written to disk before `compose up`. (c) `additional_env_files` pointing at a file kept on the Pi (e.g. `/etc/komodo/secrets/n8n.env`) so secrets never leave the host. The official Komodo guides explicitly recommend *not* storing real secrets in the committed `.env`.
- **Redeploy trigger:** Per‑stack GitHub webhook (Komodo exposes `/listener/github/repo/<id>/pull`), or polling. Both work; webhook is the typical homelab pattern.
- **Rebuild vs restart:** Configurable per stack — `run_build`, `auto_pull`, `destroy_before_deploy`, plus `pre_deploy` / `post_deploy` hooks. By default it pulls images and runs `compose up -d`.
- **Maintenance / community:** Very active in 2025–2026 (regular releases, 10k+ GitHub stars under `moghtech/komodo`, healthy Discord). GPLv3, no paywall.
- **Gotchas:** (1) In a monorepo with many stacks, Komodo will clone the repo once per stack — fine here since the user has just one. (2) Make sure Periphery's `PERIPHERY_ROOT_DIRECTORY` is *bind‑mounted to the same path on host and inside the container*, otherwise Docker's bind‑mount resolution from the running compose project will mismatch. The simpler alternative is to run Periphery as a **systemd service** (Komodo provides `setup-periphery.py`), which sidesteps the container‑path issue entirely and is what most experienced Komodo users end up doing.

### 3. Dockge — *Not Git‑aware*
- **Model:** A web UI on top of your local compose stacks directory. It edits files in `/opt/stacks/<name>/` and runs `docker compose` commands against them.
- **Full git clone on host?** No, not on its own. Dockge has no Git integration; it manages files that are already on disk.
- **Pi support:** Excellent — created by Louis Lam (Uptime Kuma), ARM64 images, ~50 MB RAM.
- **Where it fits:** Pair it with a separate `git pull` mechanism (systemd timer or webhook) so the files in `/opt/stacks/n8n/` come from your repo. Then Dockge is the dashboard/log viewer/restart button. Without a separate puller, it doesn't solve the auto‑deploy problem at all.
- **Maintenance:** Active. Note: a community fork (`cmcooper1980/dockge`) carries unmerged PRs because upstream merge cadence is slow.

### 4. Diun — *Notification only*
- **Model:** Polls registries on a cron schedule, sends a notification (ntfy, email, Slack, webhook) when an image digest changes.
- **Full git clone on host?** No — it never deploys anything.
- **Fit:** Pure observability companion. Listed in the user's question for comparison; not a deployment tool.

### 5. GitHub Actions self‑hosted runner on the Pi — *Strong runner‑up*
- **Model:** Push. The runner is a long‑lived agent on the Pi that listens for jobs assigned by GitHub. The job itself runs `git checkout` and `docker compose up -d -- pull always` on the Pi.
- **Full git clone on host?** Yes. The default `actions/checkout` does a real checkout into `_work/<repo>/<repo>/` on the Pi. From there, your workflow can simply `cd n8n && docker compose --env-file ../.env up -d`. Every relative path is real.
- **ARM64 / Pi 5:** GitHub publishes an official `actions-runner-linux-arm64` tarball. Pi 5 16 GB handles it easily; idle runner ~150–250 MB RAM.
- **Setup:** ~10 minutes via Settings → Actions → Runners → New self‑hosted runner. Install as a systemd service (`./svc.sh install`). Write a `.github/workflows/deploy.yml` with `runs-on: self-hosted`.
- **Secrets:** Excellent. Use GitHub Actions **repository secrets** (`POSTGRES_PASSWORD`, `N8N_ENCRYPTION_KEY`) and have the workflow render them into `.env` on the Pi at deploy time. The runner has no offline copy.
- **Trigger:** Native `on: push` from GitHub — no router port to open, no public webhook to expose.
- **Rebuild vs restart:** Whatever the workflow says: `docker compose pull && docker compose up -d --build --remove-orphans`.
- **Maintenance / community:** First‑party GitHub product; effectively permanent.
- **Gotchas:** A self‑hosted runner has the GitHub‑recommended security caveat — anyone who can push to the repo can run arbitrary code on the Pi. Fine for a private personal repo; do **not** expose this on public repos without "require approval for all outside collaborators" enabled. Also: the runner auto‑updates itself, which has been known to break on ARM after major version bumps — keep an eye on the service.

### 6. `adnanh/webhook` + a deploy script — *Simplest reliable webhook option*
- **Model:** A ~5 MB Go binary that listens on a port and runs shell commands when a hook URL is hit. You define hooks in `hooks.yml`. GitHub sends a webhook on push; the script runs `cd /srv/n8n && git pull && docker compose up -d --build`.
- **Full git clone on host?** Yes — your script does the clone/pull. This is the **closest possible mental model to Portainer Git deploy without Portainer**, but without the broken file‑resolution behavior.
- **ARM64:** Available in Debian/Ubuntu apt (`apt install webhook`) and as Docker images for ARM64. ~10 MB RAM.
- **Setup:** Multi‑step but each step is small. Install binary, write `hooks.yml` with HMAC validation against the GitHub webhook secret, run as systemd, expose either via a tunnel (Cloudflare Tunnel, Tailscale Funnel) or a reverse proxy. Add a `trigger-rule` matching the `X-Hub-Signature-256` header.
- **Secrets:** Keep `/srv/n8n/.env` on the Pi only (never committed); the deploy script does *not* rewrite it. Optionally use `sops` or `age` to commit an encrypted `.env.enc` and decrypt at deploy time.
- **Trigger:** GitHub webhook (push event), with HMAC secret.
- **Rebuild vs restart:** Script‑controlled.
- **Maintenance:** `adnanh/webhook` is mature; commits are infrequent but it's effectively complete software. Still widely used in 2025.
- **Gotchas:** (1) You must expose the listener to GitHub somehow — Cloudflare Tunnel is the cleanest. (2) Validate the HMAC; an open webhook URL is a remote shell. (3) The script needs `git` SSH keys or a deploy token to clone private repos.

### 7. Argo CD / Flux CD — *Overkill, dismissed*
Both are Kubernetes‑native GitOps controllers. They expect a `kubectl`‑addressable cluster, manage Kubernetes manifests (Deployments, StatefulSets), and have no first‑class notion of "run docker compose." To use them on a Pi you would have to install k3s, convert the compose stack to Kubernetes manifests (or run it via `kompose`/Docker‑inside‑K8s), and accept the operational complexity of a single‑node K8s cluster. For one Pi running three services, that is a 10× tax in moving parts. Mention only — do not adopt.

### 8. Coolify — *Works on Pi, but heavy and opinionated*
- ARM64 Pi 5 is officially supported (Coolify ships a `linux/arm64` image and has a dedicated Raspberry Pi OS setup guide).
- **Full clone:** Yes — Coolify clones the repo into `/data/coolify/...` and supports a "Raw Docker Compose Deployment" build pack that runs `docker compose` from the cloned working directory. So bind‑mounts would resolve.
- **Footprint:** ~1.5–2 GB RAM with all its workers, Soketi, Postgres, Redis. Fine on a 16 GB Pi 5 but disproportionate for one stack.
- **Secrets:** UI‑managed environment variables, written to the deployment's env file at build time.
- **Trigger:** GitHub webhook (auto‑configured) or manual deploy.
- **Gotchas:** There is an open issue (#7852, January 2026) where `coolify-helper:1.0.12` shipped without the docker compose plugin on ARM, causing deployments to fail with `unknown flag: --project-name`. Coolify on Pi has historically had ARM‑specific regressions. It also performs deep "magic" on your compose file (injects Traefik labels, network rewrites) — fine if you embrace it, friction if you want plain compose behavior.

### 9. Dokploy — *Works on Pi but currently buggy there*
- Pi 5 ARM64 install works (Docker Compose install method documented), and Dokploy does clone the repo for compose deploys.
- **Caveat (2025/2026):** Active GitHub issue #1924 reports broken authentication when accessing Dokploy from any browser/device other than the one used to register on Raspberry Pi (v0.22.6 on Pi OS Lite arm64). For a "low‑maintenance and reliability" use case, that's disqualifying right now.
- Initializes Docker Swarm at install — a permanent change to your Docker daemon that you may not want for a tiny stack.

### 10. CapRover — *ARM64 works but model mismatch*
- Multi‑arch image (`linux/amd64`, `linux/arm64`, `linux/arm`); officially "works on arm processors like Raspberry Pi" since v1.8.1.
- However, CapRover is a Heroku‑style app platform: it expects you to push apps it builds from a captain‑definition or Dockerfile, deployed as Swarm services. A custom multi‑service `docker-compose.yml` with bind‑mounts is not its happy path. Many one‑click apps lack ARM builds. Skip for this use case.

### 11. Ansible‑pull (or a cron `git pull` script) — *Simplest possible*
- **Model:** `ansible-pull` runs on a cron timer on the Pi, clones a playbook from GitHub, runs it locally. The playbook does `git pull` on your stack repo and `docker compose up -d`.
- **Full clone:** Yes — both the playbook repo and (separately) the stack repo are real clones on disk.
- **Footprint:** Ansible adds ~80 MB temporarily when a run fires; otherwise zero.
- **Secrets:** Ansible Vault, encrypting `.env` and decrypting in the playbook, is the standard pattern.
- **Trigger:** Poll only (cron). No instant push; updates land within whatever interval you set (every minute → near‑instant, every 5 minutes → typical).
- **Gotchas:** Ansible on Pi OS occasionally has Python/locale quirks; failures are silent unless you wire logging to journald or email.

### 12. systemd timer + git pull — *Even simpler than Ansible*
- A `deploy.service` that runs a 5‑line shell script (`cd /srv/n8n && git fetch && git reset --hard origin/main && docker compose pull && docker compose up -d --remove-orphans`) and a `deploy.timer` with `OnCalendar=*:0/2` (every two minutes).
- **Full clone:** Yes — your script controls it.
- **Footprint:** Effectively zero.
- **Secrets:** `.env` lives only on the Pi, in `/srv/n8n/.env` with mode 600, never committed. Or commit an encrypted `.env.sops` and decrypt in the script.
- **Trigger:** Poll only.
- **Maintenance:** Nothing to maintain; systemd is part of the OS.
- **Gotchas:** No native push trigger; no UI; "is the deploy healthy" must be observed via `journalctl -u deploy.service` or a status‑page tool like Uptime Kuma.

---

## Summary Table

| Tool | Full git clone? | ARM64 Pi 5 | Idle RAM | Push trigger | Setup effort | Secrets pattern | Recommendation |
|---|---|---|---|---|---|---|---|
| **Komodo** | **Yes (Stack/Git mode)** | Yes | ~150–400 MB | GitHub webhook + poll | Medium | Built‑in vars/secrets + env files | **Best choice** |
| GitHub Actions self‑hosted runner | Yes | Yes | ~150–250 MB | Native | Low | GitHub repo secrets → render `.env` | Excellent runner‑up |
| `adnanh/webhook` + script | Yes (your script) | Yes | ~10 MB | GitHub webhook | Low/Medium | `.env` on host or SOPS‑encrypted | Minimalist favorite |
| systemd timer + git | Yes | Yes | 0 | Poll only | Trivial | `.env` on host or SOPS | If you want zero tools |
| Ansible‑pull (cron) | Yes | Yes | ~0 idle | Poll only | Low | Ansible Vault | Fine but heavier than systemd |
| Dockge | No (needs companion) | Yes | ~50 MB | n/a | Trivial | Files on disk | Good UI companion only |
| Coolify | Yes | Yes (with caveats) | ~1.5–2 GB | Webhook | Medium | Coolify UI | Overkill; ARM regressions |
| Dokploy | Yes | Yes but bug #1924 | ~1 GB | Webhook | Medium | Dokploy UI | Skip until stable on Pi |
| CapRover | N/A (PaaS) | Yes | ~500 MB | Per‑app | High | Per‑app | Wrong model |
| Watchtower | No (image tags only) | Yes | ~15 MB | n/a | Trivial | n/a | Complement, not replacement |
| Diun | No (notifier) | Yes | ~10 MB | n/a | Trivial | n/a | Observability companion |
| Argo CD / Flux | Yes but K8s | Requires k3s | 500 MB+ | Webhook | High | K8s Secrets / SOPS | Overkill |

---

## Recommendation for This Use Case

**Use Komodo, with Periphery installed as a systemd service on the Pi.** Configure a single Stack in "Git Repo" mode pointed at your GitHub repo with `run_directory = "n8n"` and `file_paths = ["docker-compose.yml"]`. Enable the per‑stack GitHub webhook.

**Why this solves the Portainer failure exactly:**
Komodo's Stack/Git deployment is, by design, "clone the entire repo into the host's stacks directory, then `cd run_directory && docker compose up -d`." Every relative path in your compose file — including `./postgres/init.sh` — points at a real file inside the cloned working copy on the Pi. Docker never has to silently mkdir a missing source, so the Postgres entrypoint sees `init.sh` as an executable file and the database initializes correctly. This is the property Portainer's "compose file + additional paths" model lacks.

**Why over the alternatives:**
- It has a webhook trigger (so deploys are instant, not on a poll cycle).
- It has a real UI for "what's deployed, did it succeed, show me logs" — the thing the user explicitly liked about Portainer.
- The Periphery binary is tiny (~5 MB resident), so the Pi 5's resources stay free for n8n, Postgres, and Ollama.
- It is actively maintained, open‑source (GPLv3), and there is no paywalled tier that will later try to upsell you.
- It supports interpolated secrets out of the box, plus the ability to keep your real `.env` only on the host via `additional_env_files`.

**Strong runner‑up if you want zero new platforms:** a GitHub Actions self‑hosted runner on the Pi. It also does a real checkout, the trigger is `on: push`, and secrets are first‑class GitHub Actions secrets. The only reasons to prefer Komodo over it are the dashboard, the simpler "no workflow YAML to maintain" experience, and the visibility into which container is unhealthy after a deploy.

**Minimalist alternative if you distrust all UIs:** `adnanh/webhook` running under systemd, configured with a `hooks.yml` whose `trigger-rule` validates GitHub's HMAC, executing a 5‑line `deploy.sh` that does `git pull && docker compose up -d --build`. Total moving parts on the Pi: one 10 MB binary, one shell script, one systemd unit. This is the "Portainer Git Deploy, fixed by doing it right" approach.

---

## How to Handle `.env` / Secrets in Each Approach

A compose file that needs `POSTGRES_PASSWORD`, `N8N_ENCRYPTION_KEY`, and OpenAI/proxy tokens should *never* commit them to GitHub in plaintext. The recommended pattern per approach:

- **Komodo (recommended):** Define secrets once in **Settings → Variables & Secrets** in the Komodo UI. Reference them in the Stack's `environment` field as `POSTGRES_PASSWORD=[[POSTGRES_PASSWORD]]`. Komodo's Periphery agent interpolates them into a real `.env` file on disk before each `docker compose up`. Sensitive values are stored encrypted in Komodo's database and never leak into git or logs (commands are sanitized).
- **GitHub Actions runner:** Use GitHub **Actions Secrets**. In the workflow, echo them into `.env` at deploy time: `printf 'POSTGRES_PASSWORD=%s\n' "${{ secrets.POSTGRES_PASSWORD }}" >> n8n/.env`. They never touch your repo.
- **`adnanh/webhook` / systemd / Ansible-pull:** Keep `.env` *only* on the Pi (`/srv/n8n/.env`, mode 600, owned by root), excluded via `.gitignore`. The deploy script does `git pull` but never overwrites `.env`. Compose picks it up automatically because it sits next to `docker-compose.yml`. For multi‑host or backup scenarios, commit an **encrypted** version using **SOPS + age** (`sops -e .env > .env.sops`) and decrypt in the deploy script with a key stored on the Pi.
- **Ansible‑pull specifically:** Use **Ansible Vault** to encrypt `.env` in the playbook repo; decrypt with the vault password file kept only on the Pi.
- **Coolify/Dokploy/CapRover:** All manage env vars in their own UI and inject them at deploy time, similar to Komodo, but the env vars then live in *their* database — which becomes part of your backup surface.
- **Watchtower / Diun:** N/A — they don't deploy.

The pattern to avoid in all cases: committing a plaintext `.env` to the repo "just for the Pi to read after `git pull`." That is the failure mode SOPS, Ansible Vault, and Komodo's secret store all exist to prevent.