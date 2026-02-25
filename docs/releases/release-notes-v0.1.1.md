# Release Notes Template

## Release
- Version: v0.1.1
- Date: 2026-02-21
- Milestone Scope: M8 Patch Release Cadence

## Highlights
- Hardened release automation with contract/matrix validators and pre-cut gate script.
- Improved GTK query UX with explicit empty/error rows and clearer empty-query guidance.
- Added patch-operations docs: triage template/log, script matrix, and notes curation checklist.

## New Features
- `scripts/check_release_matrix.sh`
- `scripts/precut_v0_1_1.sh`
- `scripts/lint_release_notes.sh`

## Improvements
- `scripts/release_smoke.sh` supports optional `--with-gtk-runtime`.
- `scripts/cut_release_tag.sh` supports `--reuse-notes` to preserve edited notes.
- Release runbook now includes SSH preflight guidance.

## Fixes
- Corrected publish-helper help text for remote behavior.
- Added release-helper CLI contract checks to prevent flag/help drift.
- Avoided silent GTK empty state by rendering explicit status rows.

## Breaking / Behavior Changes
- None.

## Migration Notes
- Future patch cut workflow:
  - `scripts/cut_release_tag.sh --version <tag> --apply --commit-notes --reuse-notes --push`
  - Use `--reuse-notes` to preserve curated release-note content.

## Verification Summary
- `scripts/dev.sh check`: pass
- GTK build (`zig build -Denable_gtk=true`): pass
- Smoke test command(s):
  - `scripts/release_smoke.sh` (pass)
  - `scripts/precut_v0_1_1.sh` (pass)
  - `scripts/check_release_helpers.sh` (pass)
  - `scripts/check_release_matrix.sh` (pass)
  - `scripts/lint_release_notes.sh docs/release-notes-v0.1.1.md` (pass)

## Rollback Notes
- Fallback keybind path: existing shell launcher binding on separate key.
- Previous known-good commit/tag: `v0.1.0`

## Known Issues
- SSH auth can still fail in new workspaces with incorrect private-key permissions.

## Draft Commit Digest

```text
515d9d5 Queue v0.1.1 apply release slice
2f4bc9c Record v0.1.1 release dry-run result
a4af88d Queue v0.1.1 dry-run release slice
9ac8132 Add v0.1.1 pre-cut readiness gate script
0d78e2b Fill v0.1.1 release notes details
c1286a6 Add v0.1.1 patch release notes draft
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
```
