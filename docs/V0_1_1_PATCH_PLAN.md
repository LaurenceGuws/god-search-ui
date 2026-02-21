# v0.1.1 Patch Plan

Post-`v0.1.0` patch scope focused on low-risk reliability and UX polish.

## Candidate Scope
- Fix publish/release script edge cases discovered in real repo setups.
- Polish GTK empty/loading/error row states for clearer operator feedback.
- Add one integration smoke path for GTK runtime launch (not just compile).
- Tighten release docs consistency (`README`, runbook, queue references).

## Priority Order
1. Release-script reliability fixes.
2. GTK runtime UX edge-state polish.
3. Packaging/install verification improvements.
4. Doc consistency sweep.

## Acceptance Criteria
- `scripts/dev.sh check` passes.
- `scripts/release_smoke.sh` passes.
- One manual GTK run verified:
  - `zig build run -Denable_gtk=true -- --ui`
- Patch notes drafted in `docs/release-notes-v0.1.1.md`.

## Execution Order
Run in this order for each `v0.1.1` patch slice:
1. `scripts/dev.sh check`
2. `scripts/check_release_helpers.sh`
3. `scripts/release_smoke.sh`
   - optional GTK runtime check: `scripts/release_smoke.sh --with-gtk-runtime`
4. Manual GTK run:
   - `zig build run -Denable_gtk=true -- --ui`
5. Update patch notes draft:
   - `scripts/gen_release_notes.sh v0.1.1 docs/release-notes-v0.1.1.md`

## Out of Scope
- New provider classes.
- Large ranking-model changes.
- UI redesign.

## Triage Intake
Use:
- `docs/POST_RELEASE_TRIAGE_TEMPLATE.md`
- `docs/TRIAGE_LOG.md` for accepted items

## Release Ops Reference
- `docs/RELEASE_SCRIPT_MATRIX.md`

## Post-v0.1.1 Maintenance Checklist
1. Confirm `v0.1.1` tag exists locally and on `origin`.
2. Run `scripts/release_smoke.sh` on latest `main`.
3. Append any new findings to `docs/TRIAGE_LOG.md`.
4. If patch follow-up is needed, queue next item in `docs/TASK_QUEUE.md` under `Ready`.
