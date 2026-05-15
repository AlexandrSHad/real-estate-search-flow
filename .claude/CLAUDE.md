# Real Estate Search Agent

## What this is

Automated agent monitoring Czech real estate portals (sreality.cz, bezrealitky.cz),
detecting new listings and price changes, sending Telegram notifications.

## Stack

- Orchestration: n8n (self-hosted, Docker, Raspberry Pi 5)
- Storage: Postgres
- Notifications: Telegram bot
- Future: Ollama/Llama 3.1 8B for AI validation, Vue or ASP.NET Core UI

## Key decisions

See architecture-decisions.md for full ADRs.

## Current phase

Phase 1 — scrape → compare → notify
