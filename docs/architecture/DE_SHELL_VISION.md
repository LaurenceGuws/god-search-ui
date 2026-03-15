Status: active
Owner: shell
Last-Reviewed: 2026-03-03
Canonical: yes

# DE Shell Vision

This document defines the target shape of `wayspot` as a long-lived shell daemon.

## North Star

Build a modular daemon (`shelld`) that can run independently from the compositor and provide:
- launcher/summon UX
- notifications behavior
- session overlays (power, OSD, clipboard, quick actions)
- stable control interfaces for in-house components

## Current Baseline

`wayspot` currently has:
- resident/daemon GTK lifecycle (`--ui-resident`, `--ui-daemon`)
- warm summon path
- local control-plane IPC (`ping`, `summon`, `hide`, `toggle`, `version`, etc.)
- notifications popup stack with actions/history
- provider-driven search pipeline
- background cache prewarm and async refresh strategy

## Architecture Direction

1. `shelld` process (long-lived)
- owns lifecycle, IPC endpoints, module scheduler, telemetry

2. Modules
- `launcher`
- `notifications`
- `osd`
- `session`

3. Control plane
- local command surface (Unix socket)
- summon/hide/toggle, notify, dismiss, state query

4. UI surfaces
- launcher window
- notification popups/history
- OSD overlays

5. Placement stack
- `placement` engine (pure geometry policy)
- surface adapters (`gtk_toplevel`, `layer_shell`)
- `wm` adapter (`hyprland` now, compositor-native later)

## Active Priorities

1. Keep daemon lifecycle and summon flow predictable.
2. Keep control-plane behavior deterministic and documented.
3. Keep preview and popup UI abstractions generic.
4. Keep module boundaries clean as features expand.

## Non-Goals

- writing a compositor in this repo
- building a full settings UI right now
- remote/network control transport
