# Real Estate Search Agent — Architectural Decisions

## Project Goal

A personal automated agent that monitors Czech real estate portals, detects new listings and price changes, and sends notifications via Telegram. Future phases will add AI-powered property validation, commute analysis, and a UI for managing saved properties.

---

## ADR-001 — Orchestration: Local n8n (self-hosted)

**Status:** Accepted

**Decision:** Use n8n as the workflow orchestration engine, self-hosted on a Raspberry Pi 5 via Docker.

**Reasons:**

- Free to self-host with no workflow or execution limits (Sustainable Use License)
- Built-in nodes for HTTP requests, Telegram, Postgres, Cron scheduling, and JavaScript code — covers all core needs without custom code
- Visual workflow editor makes the branching logic (new listing vs. price change) easy to reason about and modify
- Runs comfortably on Pi 5 hardware (~0.5 GB RAM)
- Low-frequency, I/O-bound workloads (scraping every 30–60 minutes) are well within Pi 5 capabilities

**Rejected alternatives:**

- n8n Cloud — paid after free tier, unnecessary for a personal project
- Custom Node.js/Python scheduler — more code to maintain, no visual editor

---

## ADR-002 — Data Sources: Sreality.cz + Bezrealitky.cz (Phase 1)

**Status:** Accepted

**Decision:** Start with sreality.cz and bezrealitky.cz as the only data sources in Phase 1.

**Reasons:**

**Sreality.cz:**

- Largest Czech real estate portal (Seznam.cz), covering agency listings across all regions
- Exposes an undocumented but stable public JSON API at `/api/cs/v2/estates`
- No heavy bot protection (no DataDome, Akamai, or Cloudflare challenge)
- Plain HTTP requests return structured JSON — no browser rendering needed
- Example endpoint: `https://www.sreality.cz/api/cs/v2/estates?category_main_cb=1&locality_region_id=10&per_page=20&page=1`

**Bezrealitky.cz:**

- Second major Czech portal, specialising in direct owner-to-buyer listings (no agency commission)
- Complements sreality.cz — together they cover the full Czech market
- Scrapeable without a headless browser

**Rejected for Phase 1:**

- Remax.cz — RE/MAX EU has an official Datahub Listings API (OAuth 2.0), but it appears designed for RE/MAX partner agents, not public consumers. The public website may also require a headless browser. Many remax.cz listings appear on sreality.cz anyway. Deferred to a later phase.

---

## ADR-003 — Headless Browser: Browserless deferred

**Status:** Deferred

**What it is:** Browserless is a Docker container that runs headless Chromium as a service. It is called via HTTP from n8n and returns fully rendered HTML from JavaScript-heavy pages — solving the problem where a plain HTTP request returns an empty shell instead of actual listings.

**Decision:** Do not include Browserless in Phase 1.

**Reasons:**

- Both Phase 1 sources (sreality.cz, bezrealitky.cz) expose JSON APIs or are scrapeable with plain HTTP — a headless browser is not needed
- Browserless consumes ~1.5 GB RAM, which is better reserved for Ollama (local LLM) on the Pi 5
- Adding complexity before it is needed goes against the goal of validating the core flow first

**When to reconsider:**

- Adding a source whose listings are only available via JavaScript rendering (e.g. remax.cz if its API is not accessible)
- If any existing source changes to JS-only rendering in the future

**Alternative if needed:** Playwright Docker container — more control via scripted browser interactions, at similar RAM cost.

---

## ADR-004 — Storage: Postgres

**Status:** Accepted

**Decision:** Use Postgres (Docker container) as the property memory store.

**Reasons:**

- Persistent, queryable storage for property state (price history, seen/unseen flags, user notes)
- Native n8n Postgres node — no custom integration needed
- Lightweight on Pi 5 (~0.3 GB RAM)
- Scales naturally as feature set grows (indexes, full-text search for description analysis)

---

## ADR-005 — Notifications: Telegram Bot

**Status:** Accepted

**Decision:** Send all notifications (new listings, price changes) via a Telegram bot.

**Reasons:**

- n8n has a built-in Telegram node — zero custom code required
- Telegram bots are free, instant, and work on all devices
- Supports rich messages: text, photos, inline buttons (useful for future accept/reject UI)
- Creating a bot takes under 5 minutes via @BotFather

---

## ADR-006 — Local LLM: Ollama with Llama 3.1 8B (planned)

**Status:** Planned

**Decision:** Run a local LLM via Ollama for AI-powered property validation in a future phase.

**Model choice:** Llama 3.1 8B (Q4_K_M quantisation)

**Reasons:**

- Fits comfortably in Pi 5 RAM alongside other services (~6 GB)
- Sufficient quality for text analysis tasks: parsing descriptions, checking criteria, cross-site deduplication
- ~3–5 tokens/second on Pi 5 CPU — acceptable for a background agent running on a schedule
- Ollama exposes a simple HTTP API, callable from n8n via HTTP Request node
- No cloud API costs or data privacy concerns

**Estimated RAM budget (all services running):**

| Service                  | RAM         |
| ------------------------ | ----------- |
| Ollama (Llama 3.1 8B Q4) | ~6.0 GB     |
| n8n                      | ~0.5 GB     |
| Postgres                 | ~0.3 GB     |
| OS + headroom            | ~1.5 GB     |
| **Total**                | **~8.3 GB** |

This fits within the 16 GB available on the Raspberry Pi 5.

**Deferred to Phase 2** — the core scrape/notify loop should be validated first.

---

## Infrastructure

**Host:** Raspberry Pi 5, 16 GB RAM, running Docker (Docker Compose)

**Deployment model:** All services run as Docker containers on the Pi, managed via a single `docker-compose.yml`.

**Network access:** n8n UI accessible on the local network (port 5678). No public exposure required for Phase 1.
