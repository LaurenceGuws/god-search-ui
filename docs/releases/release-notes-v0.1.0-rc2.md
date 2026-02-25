# Release Notes Template

## Release
- Version: v0.1.0-rc2
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
08fb767 Add operator troubleshooting runbook
72d4a02 Move stale snapshot refresh off query critical path
cdb7caf Add GTK migration rollout checklist
f016b2d Add stale-cache refresh indicators in query UX
ae0ade6 Add explicit snapshot refresh triggers in UI modes
b1bc3a7 Add cache invalidation strategy for provider snapshots
4ca8388 Add Hypr/Waybar integration and service docs
ecd57b0 Fix GTK-enabled build/link integration on Zig 0.15
```
