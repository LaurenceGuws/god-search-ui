# Release Notes Template

## Release
- Version: v0.1.0
- Date: 2026-02-21
- Milestone Scope:

## Highlights
- 
- 
- 

## New Features
- 

## Improvements
- 

## Fixes
- 

## Breaking / Behavior Changes
- 

## Migration Notes
- 

## Verification Summary
- `scripts/dev.sh check`: pass/fail
- GTK build (`zig build -Denable_gtk=true`): pass/fail
- Smoke test command(s):
  - 

## Rollback Notes
- Fallback keybind path:
- Previous known-good commit/tag:

## Known Issues
- 

## Draft Commit Digest

```text
b8fefcb Queue stable v0.1.0 promotion slice
a2a8eb1 Record v0.1.0-rc2 tag publish
797803a Record publish blocker in task queue
7486bbc Add remote selection to publish tag helper
e8a09e4 Allow publish helper dry-run without origin
8e8587d Add helper to publish existing release tags
406d836 Record v0.1.0-rc2 local tag cut
0e9a485 Add release notes draft for v0.1.0-rc2
efac261 Add commit-notes option to release tag helper
6cecc0b Record v0.1.0-rc1 local tag cut
9859dfe Make release tag dry-run side-effect free
1304ec6 Add release tag flow helper script
17dbba8 Add optional Arch package smoke helper script
e715c79 Add Arch packaged install smoke checklist
3a5448a Add release tagging and rollback runbook
e5df9c7 Add M7 release smoke verification script
2570faa Add release-notes generator and desktop launcher assets
ec3124e Add optional async snapshot refresh worker path
6503b20 Add release-notes template for milestone cutovers
f5fdf9a Add systemd user unit template for launcher
```
