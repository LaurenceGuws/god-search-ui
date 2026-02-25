# WA-4.1 Module Trait PR Slices

Status: active  
Owner: shell  
Last-Reviewed: 2026-02-25  
Canonical: yes

## Scope

Break down WA-4.1 from `docs/roadmaps/DE_WEAK_AREAS_ROADMAP.md` into small implementation slices with explicit done criteria.

Target outcome: a reusable module contract for daemon-owned shell modules (launcher, notifications, future terminal/session modules).

## Current Baseline

- Runtime boot and orchestration are still centered in [main.zig](/home/home/personal/god-search-ui/src/main.zig).
- GTK shell startup wires control-plane, notifications daemon, popup manager, and launcher in [gtk_shell.zig](/home/home/personal/god-search-ui/src/ui/gtk_shell.zig).
- Notifications runtime already has partial isolation under `src/notifications/`.

## Proposed Contract (WA-4.1)

Module lifecycle vtable (interface shape):
- `init(allocator, deps) -> state`
- `start(state) -> void`
- `stop(state) -> void`
- `handle_event(state, event) -> void`
- `health(state) -> ModuleHealth`

Required properties:
- Deterministic start/stop order managed by one coordinator.
- No direct module-to-module imports in hot paths; use event dispatch and explicit deps.
- Health visibility available for diagnostics and smoke checks.

## PR Slice Plan

### Slice A: Define module contract + registry primitives

Files:
- add `src/shell/module.zig`
- add `src/shell/registry.zig`
- export from `src/root.zig` (or `src/app/mod.zig` if preferred boundary)

Done criteria:
- module interface types compile with unit tests.
- registry can register/start/stop modules in deterministic order.
- `zig build test` passes.

### Slice B: Adapter for launcher runtime module

Files:
- add `src/shell/modules/launcher_module.zig`
- minimal integration changes in [gtk_shell.zig](/home/home/personal/god-search-ui/src/ui/gtk_shell.zig) / [main.zig](/home/home/personal/god-search-ui/src/main.zig)

Done criteria:
- launcher activation path runs through module registry start.
- no behavior regression for `--ui`, `--ui-resident`, `--ui-daemon` summon paths.
- existing UI startup telemetry still logs (`startup.*`, runtime ready).

### Slice C: Adapter for notifications daemon module

Files:
- add `src/shell/modules/notifications_module.zig`
- bridge existing `src/notifications/runtime.zig` and popup wiring

Done criteria:
- DBus name ownership/teardown is module-managed (start/stop).
- action and close signals still flow (`ActionInvoked`, `NotificationClosed`).
- smoke: `scripts/dev_notifications_takeover.sh smoke` passes.

### Slice D: Minimal event bus + health diagnostics

Files:
- add `src/shell/event_bus.zig`
- add `src/shell/health.zig`
- optional CLI: extend diagnostics output with module health summary

Done criteria:
- launcher and notifications modules can exchange at least one typed event through bus.
- health snapshot available for both modules.
- no direct launcher->notifications imports in runtime orchestration.

## Non-Goals For WA-4.1

- No compositor-protocol event integration (belongs to WA-3).
- No deep feature expansion in notifications UX.
- No layer-shell/toplevel placement logic changes.

## Risks

- Startup regressions if ownership boundaries shift too quickly.
- Lifecycle mismatch between GTK application activation and module registry start.
- Double-start/stop hazards in resident mode unless idempotence is enforced.

## Validation Matrix

Per slice, run:

```bash
zig build test
zig build -Doptimize=ReleaseFast -Denable_gtk=true
scripts/dev_notifications_takeover.sh smoke
```

Resident summon sanity:

```bash
god-search-ui --ui-daemon
god-search-ui --ui
god-search-ui --ctl ping
```
