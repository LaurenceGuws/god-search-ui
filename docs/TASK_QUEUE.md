# Task Queue

Use this as the authoritative queue for autonomous agent cycles.

## Ready
- [ ] M5: Add cache invalidation strategy for provider snapshot refresh.
- [ ] M5: Add explicit refresh trigger command/path in UI layer.

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
- [x] M2: Implement baseline blended ranking (exact/prefix/source weights).
- [x] M2: Add recency boost from action history.
- [x] M2: Wire query parser + ranking into a search service that consumes provider registry.
- [x] M2: Add history persistence store (file-backed) for recency reuse across launches.
- [x] M3: Add minimal GTK4 window shell (search entry + list placeholder).
- [x] M3: Wire search service into UI update loop (query -> ranked rows).
- [x] M3: Add fallback headless renderer mode for environments without GTK libs.
- [x] M3: Add keyboard navigation behaviors (`Esc`, arrows, Enter) in GTK shell.
- [x] M3: Render real ranked candidate rows in GTK list (instead of placeholder).
- [x] M3: Connect GTK search entry changes to `SearchService.searchQuery`.
- [x] M3: Add action execution hook for selected result (`Enter`).
- [x] M3: Add row-level icon/chip styling in GTK list renderer.
- [x] M3: Add grouped sections in GTK list (apps/windows/dirs/actions).
- [x] M4: Add confirmation mode for sensitive actions (`power`).
- [x] M4: Add telemetry event sink for action execution results.
- [x] M5: Add startup/query timing instrumentation.
- [x] M5: Add provider snapshot cache prewarm for faster first query.
- [x] M6: Add Arch packaging skeleton (`PKGBUILD` + install notes).
- [x] M6: Add install/service integration docs for Hypr/Waybar bindings.
