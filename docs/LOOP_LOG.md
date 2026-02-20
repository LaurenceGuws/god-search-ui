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
