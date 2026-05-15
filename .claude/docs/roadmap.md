# Phased Roadmap

## Phase 1 — Core agent (current)

- Scrape sreality.cz and bezrealitky.cz via plain HTTP
- Detect new listings and price changes via Postgres comparison
- Send Telegram notifications

## Phase 2 — AI validation

- Add Ollama + Llama 3.1 8B
- Validate new listings against user rules: description keywords, size filters
- Attach a validation report to Telegram notifications

## Phase 3 — Commute analysis

- Integrate Google Distance Matrix API or Routes API
- Check driving and public transport commute times to a target location
- Include commute summary in the property report

## Phase 4 — Extended sources & UI

- Investigate remax.cz (direct API access or add Browserless if required)
- Cross-site deduplication (same property listed on multiple portals)
- VueJS or ASP.NET Core UI for browsing saved properties
- User notes, accept/reject workflow (via UI or Telegram inline buttons)
