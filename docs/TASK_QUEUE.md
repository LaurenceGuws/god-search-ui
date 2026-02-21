# Task Queue

Use this as the authoritative queue for autonomous agent cycles.

## Ready
- [ ] (empty)

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
- [x] M5: Add cache invalidation strategy for provider snapshot refresh.
- [x] M5: Add explicit refresh trigger command/path in UI layer.
- [x] M5: Add stale-cache indicator in UI when snapshot is auto-refreshed.
- [x] M5: Add background refresh strategy to avoid synchronous cache refresh on query path.
- [x] M5: Add async thread-based refresh worker (optional advanced path).
- [x] M6: Add Arch packaging skeleton (`PKGBUILD` + install notes).
- [x] M6: Add install/service integration docs for Hypr/Waybar bindings.
- [x] M6: Add rollout checklist for migrating from shell launcher to GTK launcher.
- [x] M6: Add operator troubleshooting runbook for common failures.
- [x] M6: Add systemd user unit example file under `packaging/systemd/`.
- [x] M6: Add release-notes template for milestone cutovers.
- [x] M6: Add changelog generation script for release notes draft.
- [x] M6: Add desktop file + icon assets for launcher integration.
- [x] M7: Add release smoke-test script for headless + GTK build verification.
- [x] M7: Add release tagging/rollback runbook with exact command sequence.
- [x] M7: Add packaged install smoke steps for Arch (`makepkg` + desktop entry check).
- [x] M7: Add optional Arch package smoke helper script.
- [x] M7: Add release tag flow helper script (dry-run + apply modes).
- [x] M7: Make release-tag dry-run mode side-effect free (no generated files).
- [x] M7: Execute local RC tag cut (`v0.1.0-rc1`) with release preflight.
- [x] M7: Add `--commit-notes` option so tags can include release-notes commit.
- [x] M7: Execute local RC tag cut (`v0.1.0-rc2`) with notes included in tagged commit.
- [x] M7: Add publish helper for existing local release tags (dry-run + push modes).
- [x] M7: Allow publish-helper dry-run without configured `origin` remote.
- [x] M7: Add `--remote` option to publish helper (default `origin`).
- [x] M7: Publish `v0.1.0-rc2` tag to `origin`.
- [x] M7: Promote stable `v0.1.0` tag from current main and publish to `origin`.
- [x] M8: Add post-release patch plan for `v0.1.1` (top bugs/polish/risk fixes).
- [x] M8: Fix publish-helper help text to reflect `--remote` behavior.
- [x] M8: Add guard script for release-helper CLI docs/output consistency.
- [x] M8: Add post-release patch checklist execution order to runbook docs.
- [x] M8: Add GTK explicit empty/error state rows in result list.
- [x] M8: Add GTK placeholder guidance for empty-query state.
- [x] M8: Add post-release issue triage template for v0.1.1 planning.
- [x] M8: Add first concrete triage entry from release publish session.
- [x] M8: Add SSH key preflight check step to release publish runbook.
- [x] M8: Add optional GTK runtime launch smoke mode to `scripts/release_smoke.sh`.
- [x] M8: Add release-helper script usage matrix documentation.
- [x] M8: Add lightweight script to validate release-matrix command references.
- [x] M8: Add patch release notes draft for `v0.1.1`.
- [x] M8: Fill concrete highlights/fixes in `docs/release-notes-v0.1.1.md`.
- [x] M8: Add pre-cut readiness gate script for `v0.1.1`.
- [x] M8: Run `v0.1.1` release cut dry-run and record outcome.
- [x] M8: Execute `v0.1.1` apply cut and publish to `origin`.
- [x] M8: Add `--reuse-notes` option to `cut_release_tag.sh` to preserve curated notes.
- [x] M8: Add `--reuse-notes` workflow note in `v0.1.1` release notes.
- [x] M8: Add release-notes curation checklist for patch cuts.
- [x] M8: Add lint script to detect placeholder text in release notes.
- [x] M8: Add post-`v0.1.1` maintenance checklist entry in docs.
- [x] M8: Queue first `v0.1.2` candidate from triage findings.
- [x] M8: Implement v0.1.2 candidate - default-safe notes mode in `cut_release_tag.sh`.
- [x] M8: Add migration note for default-safe notes mode in curation checklist.
- [x] M8: Add quick dry-run example for default-safe notes mode in release matrix.
- [x] M8: Add automated dry-run assertion for default-safe notes branch.
- [x] M8: Prevent recursive preflight in cut dry-run assertion checks.
- [x] M8: Run `v0.1.2` release cut dry-run with default-safe notes mode.
- [x] M8: Execute `v0.1.2` apply cut and publish to `origin`.
- [x] M8: UX Phase 1 - add scrolled results container and actionable-row-only selection.
- [x] M8: UX Phase 1 - switch GTK action execution to non-blocking spawn path.
- [x] M8: UX Phase 1 - add debounce for GTK `search-changed` updates.
- [x] M8: UX Phase 1 - add visible launch feedback row for async command dispatch.
- [x] M8: UX Phase 2 - replace placeholder status text with dedicated status line.
