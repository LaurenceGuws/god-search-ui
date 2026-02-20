# Autonomous Agent Iteration Loop

Use this loop for each autonomous cycle.

## Global Rules
- Keep each cycle small and shippable.
- Do not mix unrelated concerns in one commit.
- Always end cycle with verification evidence.
- If blocked > 15 minutes, create `BLOCKED` note and pivot to next queued task.

## Loop Inputs
- `TARGET_MILESTONE`: one of `M0..M6`
- `TASK_SLICE`: a single objective that fits in one cycle
- `TIMEBOX_MIN`: default `45`

## Loop Steps

1. Plan Slice (5 min)
- Restate exact objective and acceptance criteria.
- Identify touched files/modules.
- Define tests/checks before edits.

2. Implement (20-30 min)
- Make minimal coherent changes.
- Keep architecture boundaries clean.
- Add/adjust tests in same cycle.

3. Verify (5-10 min)
- Run:
  - `zig fmt --check .`
  - `zig build`
  - `zig test`
- Run focused manual check if UI behavior changed.

4. Commit (2-5 min)
- Commit with clear scope in subject.
- Add short body: what/why/risk.

5. Record + Queue Next (3 min)
- Update `docs/LOOP_LOG.md` entry.
- If passed, enqueue next best slice.
- If failed, open `docs/BLOCKERS.md` entry.

## Definition of Done for a Slice
- Acceptance criteria met.
- Tests/checks pass.
- No known regression introduced.
- Commit created.
- Log entry written.

## Failure Policy
- Build fails twice: revert local experimental chunk and retry smaller.
- Unknown bug source: add temporary instrumentation, isolate, then remove.
- External dependency missing: document fallback and continue.

## Commit Cadence
- 1 to 3 commits per cycle.
- Each commit must be independently understandable.
- Avoid WIP commits unless session is being interrupted.

## Stop Conditions
- Timebox exceeded with unstable branch.
- Reproducible crash introduced and not isolated.
- Ambiguous product decision blocking progress.

When a stop condition occurs:
- Write blocker note.
- Propose 2 concrete resolution options.
