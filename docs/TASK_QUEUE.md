# Task Queue

Use this as the authoritative queue for autonomous agent cycles.

## Ready
- [ ] M2: Implement baseline blended ranking (exact/prefix/source weights).
- [ ] M2: Add recency boost from action history.

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
- [x] M1: Implement apps provider from `.desktop` cache/source with graceful fallback.
- [x] M1: Implement windows provider with optional `hyprctl`/`jq` diagnostics.
- [x] M1: Implement dirs provider with optional `zoxide` diagnostics.
- [x] M1: Add provider registry and health snapshot report.
- [x] M2: Add query parser for prefix routing (`@ # ~ > = ?`).
