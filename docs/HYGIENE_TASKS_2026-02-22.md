# Hygiene Tasks (2026-02-22)

## T1: Query Flag Data Race (High)
- Files:
  - src/ui/gtk/results_flow.zig
  - src/ui/gtk/controller.zig
  - src/app/search_service.zig (or helper module)
- Problem:
  - UI reads `last_query_used_stale_cache` and `last_query_refreshed_cache` without query mutex, while async worker writes under mutex.
- Done when:
  - Reads are synchronized (via accessor helper or locked snapshot API).
  - Existing behavior preserved.
  - Tests added/updated where practical.

## T2: Refresh Thread Spawn Failure Leaves Running Flag Set (Medium)
- Files:
  - src/app/search_service.zig
  - src/app/search_service/refresh_worker.zig (if needed)
- Problem:
  - `refresh_thread_running` is marked true before `Thread.spawn`; spawn failure exits early and leaves flag stuck true.
- Done when:
  - Failure path resets running flag.
  - Regression test covers spawn-failure behavior if practical.

## T3: Provider Owned String Growth Across Collects (High)
- Files:
  - src/providers/apps.zig
  - src/providers/dirs.zig
  - src/providers/windows.zig
- Problem:
  - Repeated collects append to `owned_strings` without clearing previous generation.
- Done when:
  - Old owned strings are reclaimed per-collect in a safe way.
  - Existing output semantics unchanged.
  - Tests added to call `collect` multiple times and verify bounded ownership.

## T4: Ranking Canonicalization Allocation Failure Fallback (Medium)
- Files:
  - src/search/rank.zig
- Problem:
  - Allocation failure in `lowerAsciiLossyAlloc` silently degrades to empty needle and broad matches.
- Done when:
  - Behavior is explicit (propagate error or fallback to raw term) without broad silent degradation.
  - Regression test covers failure path.

## T5: CI Release-Validate Guard Hides Failure Output (Medium)
- Files:
  - scripts/check_release_validate_ci.sh
- Problem:
  - Command output redirected to `/dev/null`, obscuring root cause on failure.
- Done when:
  - Failure output is preserved and printed when command exits non-zero or times out.
