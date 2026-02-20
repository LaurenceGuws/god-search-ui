# Task Queue

Use this as the authoritative queue for autonomous agent cycles.

## Ready
- [ ] M1: Implement apps provider from `.desktop` cache/source with graceful fallback.
- [ ] M1: Implement windows provider with optional `hyprctl`/`jq` diagnostics.
- [ ] M1: Implement dirs provider with optional `zoxide` diagnostics.
- [ ] M1: Add provider registry and health snapshot report.

## In Progress
- [ ] (empty)

## Blocked
- [ ] (empty)

## Done
- [x] M0: baseline dev loop + CI + deterministic starter
- [x] M0: Add `src/app/` module boundary and wire minimal app state bootstrap.
- [x] M0: Add structured logger with levels (`debug/info/warn/error`).
- [x] M1: Define `Candidate` model and `Provider` interface in `src/search/`.
- [x] M1: Implement actions provider with static candidates and executor mapping.
