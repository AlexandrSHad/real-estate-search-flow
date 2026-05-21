# Phased Roadmap

Legend:

- [x] - task is done
- [*] - task is in progress

## Phase 1 — Core agent (current)

- [x] Scrape sreality.cz and bezrealitky.cz via plain HTTP
- [x] Send Telegram notifications
- [*] Deploy n8n infrastructure to the Raspberry Pi
- [ ] Deploy n8n workflow to the Raspberry Pi instance
- [ ] Detect new listings and price changes via Postgres comparison

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

## Phase X (not yet defined)

- Replace `N8N_SECURE_COOKIE=false` workaround with a self-signed TLS certificate mounted into the n8n container — see `n8n-https-setup.md`
- Enable key rotation for Komodo, Decision: Disable automatic PKI key rotation in Komodo. Reason: Known bug — rotation closes the WebSocket connection but Core fails to persist the new Periphery public key before rejecting the reconnect attempt. Stack recreation required to recover. Will re-enable if/when fixed upstream.
