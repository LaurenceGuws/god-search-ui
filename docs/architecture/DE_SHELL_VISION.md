Status: active
Owner: shell
Last-Reviewed: 2026-02-25
Canonical: yes

# DE Shell Vision

This document defines how `god-search-ui` evolves from launcher into a core shell daemon for a full Zig-first desktop stack.

Companion execution plan for weak areas:
- `docs/DE_WEAK_AREAS_ROADMAP.md`

## North Star

Build a modular shell daemon (`shelld`) that can run independently from the compositor and provide:
- launcher/summon UX
- notifications daemon behavior
- session overlays (power, OSD, clipboard, quick actions)
- stable control plane APIs for other in-house components (terminal, compositor, future agents)

## Current Baseline

`god-search-ui` already has:
- resident/daemon GTK lifecycle (`--ui-resident`, `--ui-daemon`)
- warm summon path with low startup overhead
- modular provider-driven search pipeline
- background cache prewarm and async refresh strategy
- telemetry and release automation discipline

This is a strong base for shell-daemon work.

## Strengths (Codebase)

1. Long-lived UI process path exists and is practical.
   - `src/main.zig`
   - `src/ui/gtk_shell.zig`
   - `src/ui/gtk/bootstrap.zig`
2. Search core is modular and mostly UI-agnostic.
   - `src/app/search_service.zig`
   - `src/app/search_service/*.zig`
   - `src/providers/registry.zig`
3. Provider architecture already supports partial failure and health reporting.
   - `src/providers/registry.zig`
4. Performance direction is correct: startup metrics + async prewarm + render debouncing.
   - `src/main.zig`
   - `src/ui/gtk_shell.zig`
   - `src/ui/gtk/results_flow.zig`

## Weaknesses (Against DE-Shell Goals)

1. No shell control-plane IPC yet.
   - Current summon model still depends on external process invocation (`god-search-ui --ui`).
2. Notifications are not first-class.
   - No `org.freedesktop.Notifications` implementation.
3. Module boundaries are still launcher-centric.
   - GTK shell orchestration is large and tightly coupled to launcher flows.
4. Compositor/session integration is command-driven (`hyprctl`, scripts), not event-driven protocol APIs.
   - `src/wm/hyprland.zig`
   - `src/providers/actions.zig`

## Target Architecture

1. `shelld` process (long-lived)
   - Owns lifecycle, IPC endpoints, module scheduler, telemetry.
2. Modules (independent feature slices)
   - `launcher`
   - `notifications`
   - `osd`
   - `session`
3. Control plane
   - D-Bus and/or Unix socket command surface
   - summon/hide/toggle, notify, dismiss, state query
4. UI surfaces
   - Launcher window
   - Notification popups/history
   - OSD overlays
5. Data/control contracts
   - Shared typed event bus in-process
   - Explicit module API traits for registration and lifecycle

## Phased Plan

### Phase A: Shell Daemon Foundation
- Add daemon identity and explicit runtime mode docs (`launcher` vs `shelld` behavior).
- Introduce minimal control endpoint (`summon`, `hide`, `ping`, `version`).
- Separate lifecycle code from launcher-specific rendering paths.

Exit criteria:
- Summon no longer requires process relaunch semantics.
- Control endpoint smoke tested from CLI.

### Phase B: Notifications MVP
- Implement freedesktop notifications subset.
- Render popup stack + timeout + close.
- Add actions callback handling.

Exit criteria:
- `notify-send` works against shell daemon.
- Basic popup UX and dismissal are stable.

### Phase C: Shell Module API
- Refactor launcher/notifications into explicit module interfaces.
- Add internal event bus and standardized telemetry labels.

Exit criteria:
- Modules can be initialized/shutdown independently.
- Cross-module events flow without direct hard coupling.

### Phase D: Compositor Integration Readiness
- Abstract WM/compositor adapters behind event-capable interfaces.
- Maintain Hyprland adapter while preparing compositor-native hooks.

Exit criteria:
- Shell can consume either external WM adapter or in-house compositor adapter with minimal conditional code.

## Immediate Priority Queue (Recommended)

1. Add control-plane MVP (`shelld ping/summon/hide`) with Unix socket.
2. Carve `src/ui/gtk_shell.zig` lifecycle into daemon/runtime + launcher module slices.
3. Add notifications daemon MVP (`Notify`, `CloseNotification`, capabilities).
4. Add performance SLO doc section:
   - summon-to-focus p50/p95
   - first-input acceptance rate
   - popup latency targets

## Non-Goals (Current Horizon)

- Writing a compositor inside this repo.
- Full settings UI.
- Remote/network notification transport.

Those should land after local daemon contracts are stable.
