# Loop Log

## 2026-02-21
- Milestone: M0 Foundation
- Task slice: Baseline dev loop tooling + CI + deterministic tests
- Changes:
  - Added `scripts/dev.sh` for `fmt/build/test/check` loop commands.
  - Added GitHub Actions workflow `/.github/workflows/ci.yml`.
  - Added `.gitignore` for Zig build artifacts.
  - Removed template fuzz/noise tests from `src/main.zig`.
  - Updated `README.md` with local loop commands.
- Verification:
  - `chmod +x scripts/dev.sh`
  - `scripts/dev.sh check`
- Commit(s):
  - pending (repo not initialized yet in this workspace)
- Risks/notes:
  - No git repository exists yet in `~/personal/god-search-ui`.
- Next slice:
  - M0: initialize git, create first baseline commit, and add issue/task queue file.

---
## 2026-02-21 (Cycle 2)
- Milestone: M0 Foundation
- Task slice: Add `src/app/` boundary with minimal app state bootstrap
- Changes:
  - Added `src/app/state.zig` with `UiMode` and `AppState`.
  - Added `src/app/bootstrap.zig` bootstrap function.
  - Added `src/app/mod.zig` module barrel export.
  - Wired `src/root.zig` to export `app`.
  - Updated `src/main.zig` to bootstrap and print initial mode.
  - Marked task complete in `docs/TASK_QUEUE.md`.
- Verification:
  - `scripts/dev.sh check`
- Commit(s):
  - pending
- Risks/notes:
  - State is intentionally minimal; logger/config not yet connected.
- Next slice:
  - M0: Add structured logger with levels (`debug/info/warn/error`).

---
## 2026-02-21 (Cycle 3)
- Milestone: M0 Foundation
- Task slice: Add structured logger with levels (`debug/info/warn/error`)
- Changes:
  - Added `src/app/logger.zig` with `Level` enum and `Logger`.
  - Added level helpers: `debug/info/warn/error`.
  - Added enablement test for level filtering.
  - Exported logger types from `src/app/mod.zig`.
  - Wired startup logging in `src/main.zig`.
  - Marked logger task complete in `docs/TASK_QUEUE.md`.
- Verification:
  - `scripts/dev.sh check`
- Commit(s):
  - pending
- Risks/notes:
  - Logger currently writes to stderr via `std.debug.print`.
- Next slice:
  - M1: Define `Candidate` model and `Provider` interface in `src/search/`.

---
## 2026-02-21 (Cycle 4)
- Milestone: M1 Data Model + Provider Contract
- Task slice: Define `Candidate` model and `Provider` interface in `src/search/`
- Changes:
  - Added `src/search/types.zig` with:
    - `CandidateKind`
    - `Candidate`
    - `ProviderHealth`
    - `Provider` vtable contract
    - `CandidateList`
  - Added unit test using fake provider context.
  - Added `src/search/mod.zig` exports.
  - Exported `search` from `src/root.zig`.
  - Marked search contract task complete in `docs/TASK_QUEUE.md`.
- Verification:
  - `scripts/dev.sh check`
- Commit(s):
  - pending
- Risks/notes:
  - Interface intentionally minimal; diagnostics payload can be expanded later.
- Next slice:
  - M1: Implement actions provider with static candidates and executor mapping.

---
## 2026-02-21 (Cycle 5)
- Milestone: M1 Data Model + Provider Contract
- Task slice: Implement actions provider with static candidates and executor mapping
- Changes:
  - Added `src/providers/actions.zig`:
    - static action candidates (`Settings`, `Power menu`, `Restart Waybar`, `Notifications panel`)
    - action key to command resolver
    - execution function using injected command runner
  - Added tests for provider collection and action execution mapping.
  - Added `src/providers/mod.zig` export barrel.
  - Exported `providers` from `src/root.zig`.
  - Updated `docs/TASK_QUEUE.md` with completion + next M1 slices.
- Verification:
  - `scripts/dev.sh check`
- Commit(s):
  - pending
- Risks/notes:
  - Command strings are static for now; later config overrides can be layered on top.
- Next slice:
  - M1: Implement apps provider from `.desktop` cache/source with graceful fallback.

---
## 2026-02-21 (Cycle 6)
- Milestone: M1 Data Model + Provider Contract
- Task slice: Implement apps provider from `.desktop` cache/source with graceful fallback
- Changes:
  - Added `src/providers/apps.zig` with:
    - cache-based TSV collection (`category\\tname\\texec`)
    - health reporting (`ready` when cache exists, `degraded` otherwise)
    - fallback candidate when cache is missing/empty
  - Added tests for cache collection and fallback behavior.
  - Exported apps provider via `src/providers/mod.zig`.
  - Updated queue status in `docs/TASK_QUEUE.md`.
- Verification:
  - `scripts/dev.sh check`
- Commit(s):
  - pending
- Risks/notes:
  - Candidate strings are retained in provider-owned memory until `deinit`.
- Next slice:
  - M1: Implement windows provider with optional `hyprctl`/`jq` diagnostics.

---
## 2026-02-21 (Cycle 7)
- Milestone: M1 Data Model + Provider Contract
- Task slice: Implement windows provider with optional `hyprctl`/`jq` diagnostics
- Changes:
  - Added `src/providers/windows.zig`:
    - provider health based on optional tool availability
    - window collection via `hyprctl clients -j` + `jq` projection
    - normalized window candidates (`title`, `class`, `address`)
    - owned-string lifecycle management
  - Added tests for ready/degraded health paths.
  - Exported `WindowsProvider` in `src/providers/mod.zig`.
  - Updated queue completion in `docs/TASK_QUEUE.md`.
- Verification:
  - `scripts/dev.sh check`
- Commit(s):
  - pending
- Risks/notes:
  - Runtime command execution currently shells through `sh -lc`.
- Next slice:
  - M1: Implement dirs provider with optional `zoxide` diagnostics.

---
## 2026-02-21 (Cycle 8)
- Milestone: M1 Data Model + Provider Contract
- Task slice: Implement dirs provider with optional `zoxide` diagnostics
- Changes:
  - Added `src/providers/dirs.zig`:
    - provider health based on optional `zoxide` availability
    - directory collection from `zoxide query -l`
    - normalized directory candidates (`basename`, `Directory`, `full path`)
    - owned-string lifecycle management
  - Added tests for ready/degraded health and candidate mapping.
  - Exported `DirsProvider` in `src/providers/mod.zig`.
  - Updated queue completion in `docs/TASK_QUEUE.md`.
- Verification:
  - `scripts/dev.sh check`
- Commit(s):
  - pending
- Risks/notes:
  - Runtime command execution currently shells for tool check.
- Next slice:
  - M1: Add provider registry and health snapshot report.

---
## 2026-02-21 (Cycle 9)
- Milestone: M1 Data Model + Provider Contract
- Task slice: Add provider registry and health snapshot report
- Changes:
  - Added `src/providers/registry.zig`:
    - provider aggregation (`collectAll`)
    - health snapshot generation (`healthSnapshot`)
    - text report rendering (`renderHealthReport`)
  - Added registry unit test covering aggregate collection + report content.
  - Exported `ProviderRegistry` and `ProviderStatus` in `src/providers/mod.zig`.
  - Updated `docs/TASK_QUEUE.md` to close M1 and open M2 ready slices.
- Verification:
  - `scripts/dev.sh check`
- Commit(s):
  - pending
- Risks/notes:
  - Aggregation currently ignores per-provider collect errors by design for resilience.
- Next slice:
  - M2: Add query parser for prefix routing (`@ # ~ > = ?`).

---
## 2026-02-21 (Cycle 10)
- Milestone: M2 Search + Ranking v1
- Task slice: Add query parser for prefix routing (`@ # ~ > = ?`)
- Changes:
  - Added `src/search/query.zig`:
    - route enum for blended/apps/windows/dirs/run/calc/web
    - parser for optional prefix-based routing
    - unit tests for empty, prefixed, and plain queries
  - Exported query types/parser in `src/search/mod.zig`.
  - Updated queue completion in `docs/TASK_QUEUE.md`.
- Verification:
  - `scripts/dev.sh check`
- Commit(s):
  - pending
- Risks/notes:
  - Parser currently trims surrounding whitespace and strips one prefix char only.
- Next slice:
  - M2: Implement baseline blended ranking (exact/prefix/source weights).

---
