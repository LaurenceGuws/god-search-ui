# Release Notes Template

## Release
- Version: v0.1.1
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
