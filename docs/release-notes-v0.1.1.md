# Release Notes Template

## Release
- Version: v0.1.1
- Date: 2026-02-21
- Milestone Scope: M8 Patch Release Cadence

## Highlights
- Release automation hardened with helper guard checks and matrix validation.
- GTK search UX improved with explicit empty/error rows and clearer empty-query guidance.
- Post-release patch cadence documented (plan, triage template/log, execution checklist).

## New Features
- `scripts/check_release_matrix.sh` validates release-matrix script references and command anchors.
- `scripts/release_smoke.sh --with-gtk-runtime` adds optional GTK runtime launch smoke.
- New operational references: `docs/RELEASE_SCRIPT_MATRIX.md`, `docs/POST_RELEASE_TRIAGE_TEMPLATE.md`, `docs/TRIAGE_LOG.md`.

## Improvements
- `scripts/publish_release_tag.sh` supports explicit `--remote` selection.
- Release runbook now includes SSH preflight guidance before first publish.
- Release helper CLI contract checks are integrated into release smoke flow.

## Fixes
- Corrected publish-helper help text to match `--remote` behavior.
- Removed ambiguous GTK empty state by rendering a clear “No results” row.
- Search errors in GTK now render visible status rows instead of silent empty list.

## Breaking / Behavior Changes
- None.

## Migration Notes
- No config migration required from `v0.1.0`.
- Existing release scripts remain compatible; optional flags (`--with-gtk-runtime`, `--remote`) are additive.

## Verification Summary
- `scripts/dev.sh check`: pass
- GTK build (`zig build -Denable_gtk=true`): pass
- Smoke test command(s):
  - `scripts/release_smoke.sh` (pass)
  - `scripts/release_smoke.sh --with-gtk-runtime` (pass)
  - `scripts/check_release_helpers.sh` (pass)
  - `scripts/check_release_matrix.sh` (pass)

## Rollback Notes
- Fallback keybind path: retain existing shell launcher binding on separate key.
- Previous known-good commit/tag: `v0.1.0`

## Known Issues
- SSH environment setup can still fail on first publish if private-key permissions are incorrect.

## Draft Commit Digest

```text
2c7ae56 Add release matrix validator script
740f1ea Add release helper script usage matrix
3adbc0b Add optional GTK runtime mode to release smoke
82f550e Add SSH preflight step to release runbook
4402a18 Add first post-release triage log entry
6633856 Add post-release triage template for v0.1.1
91b9afc Add GTK empty-query placeholder guidance
fd2d863 Add GTK empty and error state rows
18c7f65 Add post-release patch checklist order
dae366a Add release helper CLI contract guard checks
40fb054 Fix publish helper help text for remote mode
e96cb0f Add v0.1.1 post-release patch plan
5a16fea Record stable v0.1.0 release promotion
1a9481a Add release notes draft for v0.1.0
b8fefcb Queue stable v0.1.0 promotion slice
a2a8eb1 Record v0.1.0-rc2 tag publish
797803a Record publish blocker in task queue
7486bbc Add remote selection to publish tag helper
e8a09e4 Allow publish helper dry-run without origin
8e8587d Add helper to publish existing release tags
```
