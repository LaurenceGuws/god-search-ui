# God Search UI Development Journey

## Mission
Build a production-quality, Spotlight-style launcher for Hyprland with:
- blended search results (apps, windows, dirs, actions, recents)
- modern GTK4/libadwaita UI
- fast local ranking
- robust config and logging

## Product Constraints
- Startup target: < 120ms to interactive UI on warm start
- Query target: < 35ms for local ranking on typical datasets
- No hard dependency on network
- Graceful degradation when optional tools are missing (`zoxide`, `jq`, etc.)

## Milestones

### M0: Foundation
- Zig project compiles and runs
- Project structure in place (`ui`, `providers`, `search`, `app`)
- Dev scripts: build, run, test, lint
- CI baseline (format + build + tests)

Exit criteria:
- `zig build` passes
- `zig test` passes
- basic logging enabled

### M1: Data Model + Provider Contract
- Define common `Candidate` model and `Provider` interface
- Implement providers:
  - Apps provider
  - Windows provider
  - Dirs provider
  - Actions provider
- Add provider health/status diagnostics

Exit criteria:
- All providers return normalized candidates
- Missing external tools produce warnings, not crashes

### M2: Search + Ranking v1
- Query parser for prefixes (`@`, `#`, `~`, `>`, `=`, `?`)
- Blended ranking strategy:
  - exact/prefix/fuzzy score
  - source weight
  - recency boost
- Top-N truncation and deterministic sorting

Exit criteria:
- Mixed results for empty and non-empty query
- Unit tests cover scorer behavior

### M3: GTK4/libadwaita UI Shell
- Main window + search entry + result list
- Keyboard-first navigation (`Esc`, arrows, `Enter`, shortcuts)
- Visual identity: icons, chips/tags, subtitles, section affordances
- Multi-monitor positioning near Waybar zone

Exit criteria:
- Smooth keyboard UX
- No blocking work on UI thread

### M4: Action Execution + Safety
- Per-type executor (`app`, `window`, `dir`, `action`, special prefixes)
- Confirmation mode for sensitive actions (power, session)
- History persistence and replay safety

Exit criteria:
- Correct execution for each candidate type
- Action telemetry events recorded

### M5: Performance + Stability
- Startup/query profiling
- Caching layers (provider snapshots + recent history)
- Failure injection and recovery tests
- Snapshot invalidation strategy (TTL + manual refresh path)

Exit criteria:
- Meets latency targets
- No fatal crash in integration test sweep

### M6: Packaging + Integration
- Arch packaging strategy (PKGBUILD/dev package)
- Hypr keybind integration and waybar hooks
- Migration notes from shell prototype

Exit criteria:
- install/uninstall documented
- user config path stable

### M7: Release Hardening
- Reproducible release smoke checks (headless + GTK build path)
- Tagging + rollback playbook
- Packaged install validation for launcher assets

Exit criteria:
- repeatable release checklist can be executed end-to-end
- rollback path validated against previous known-good commit/tag

## Backlog Buckets
- UX polish (animations, result grouping, inline preview)
- Search quality (synonyms, typo tolerance tuning)
- Plugin API for external providers
- Telemetry dashboard for score tuning

## Release Gates
- Alpha: M0-M3 complete
- Beta: M4-M5 complete
- Stable: M6 complete + docs and migration notes
- Hardened: M7 complete + reproducible release operations
