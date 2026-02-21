# Release Notes Template

## Release
- Version: v0.1.2
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
21a528c Add dry-run example for default-safe notes mode
eae25bb Document default-safe notes mode migration
a49852c Default cut helper to safe notes reuse mode
232ab3b Queue first v0.1.2 candidate from triage
514790e Add post-v0.1.1 maintenance checklist
26e1e2f Add release-notes lint guardrail
a2a23ed Add release notes curation checklist
1540f16 Document reuse-notes workflow in v0.1.1 notes
7764338 Add reuse-notes mode to release cut helper
a292cd8 Record v0.1.1 release publish
998e18d Add release notes draft for v0.1.1
515d9d5 Queue v0.1.1 apply release slice
2f4bc9c Record v0.1.1 release dry-run result
a4af88d Queue v0.1.1 dry-run release slice
9ac8132 Add v0.1.1 pre-cut readiness gate script
0d78e2b Fill v0.1.1 release notes details
c1286a6 Add v0.1.1 patch release notes draft
2c7ae56 Add release matrix validator script
740f1ea Add release helper script usage matrix
3adbc0b Add optional GTK runtime mode to release smoke
```
