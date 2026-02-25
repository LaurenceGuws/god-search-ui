Status: active
Owner: shell
Last-Reviewed: 2026-02-25
Canonical: yes

# DE Weak Areas Roadmap

This roadmap tracks focused workstreams for the main architecture gaps identified in `docs/DE_SHELL_VISION.md`.

## WA-1: Shell Control Plane (IPC)

### Objective
Provide stable daemon control without process relaunch semantics.

### Milestones
1. WA-1.1 Unix socket server in daemon process.
   - Spec: `docs/WA1_CONTROL_PLANE_SPEC.md`
2. WA-1.2 Minimal commands: `ping`, `summon`, `hide`, `toggle`, `version`.
3. WA-1.3 CLI client mode uses socket first; fallback to spawn only when daemon unavailable.
4. WA-1.4 Smoke tests for command reliability and timeout behavior.

### Acceptance Criteria
- `god-search-ui --ui` summons existing daemon when available.
- No duplicate daemon process under repeated summon spam.
- Command timeout/failure produces deterministic exit codes.

## WA-2: Notifications Daemon

### Objective
Implement first-party notifications service compatible with desktop clients.

### Milestones
1. WA-2.0 Fetch and freeze full notifications spec sections from `docs/vendor/notifications/SOURCES.txt` (especially `protocol.html`, `hints.html`, `markup.html`) before coding.
   - Lock file: `docs/NOTIFICATIONS_PROTOCOL_LOCK.md`
2. WA-2.1 D-Bus service registration for `org.freedesktop.Notifications`.
3. WA-2.2 Lock exact method signatures from official protocol section and implement: `Notify`, `CloseNotification`, `GetCapabilities`, `GetServerInformation`.
4. WA-2.3 Implement required signals and close-reason behavior from protocol section (`NotificationClosed`, `ActionInvoked`), with exact payload signatures.
5. WA-2.4 Popup stack rendering + timeout + close interactions; honor `replaces_id`.
6. WA-2.5 Apply markup/hints/urgency behavior according to fetched spec sections (MVP subset explicitly documented).
7. WA-2.6 History buffer + dismiss-all behavior.

### Acceptance Criteria
- `notify-send` works end-to-end against daemon.
- Multiple notifications stack predictably.
- Replacing an existing ID updates in place.
- Method and signal signatures match `protocol.html` exactly.
- Implemented hint/markup behavior is documented as either "implemented" or "deferred" against vendor sections.

## WA-3: Event-Driven Compositor/Session Integration

### Objective
Reduce shell command polling and move toward event-capable adapters.

### Milestones
1. WA-3.1 Introduce WM adapter interface with explicit event hooks.
2. WA-3.2 Keep Hyprland command adapter as baseline implementation.
3. WA-3.3 Add event subscription path (socket/D-Bus/IPC) for workspace/window changes.
4. WA-3.4 Replace hot-path shell command calls with cached event-fed snapshots.

### Acceptance Criteria
- Workspace/window UI updates react to events, not repeated command execution.
- Fewer command invocations per summon/query cycle.
- Adapter contract supports future in-house compositor backend.

## WA-5: Surface Placement + WM Abstraction

### Objective
Make launcher and notification placement app-controlled, deterministic, and portable across backends.

### Current Status
- WA-5.1 done
- WA-5.2 done
- WA-5.3 done
- WA-5.4 in progress (GTK bridge active for shared sizing/anchor policy; Wayland toplevel absolute placement still compositor-managed)
- WA-5.5 done (gtk4-layer-shell adapter + runtime mode switch added)
- WA-5.6 pending

### Milestones
1. WA-5.1 Define explicit WM adapter contract (`active output`, `work area`, `focus hints`).
2. WA-5.2 Define surface contracts for launcher + notification windows.
3. WA-5.3 Add pure placement engine (`anchor`, `offset`, `monitor policy`, `stack direction`) with unit tests.
4. WA-5.4 Implement GTK toplevel surface adapter through placement engine.
5. WA-5.5 Add layer-shell surface adapter for deterministic Wayland anchoring.
6. WA-5.6 Add config/env controls for launcher/popup placement.

### Acceptance Criteria
- Placement is configured in app policy, not compositor-specific window rules.
- Launcher and notification windows share one placement engine.
- Hyprland integration stays isolated behind WM adapter boundaries.
- Toplevel and layer-shell adapters can be selected without changing placement logic.

## WA-4: Module Boundary Hardening

### Objective
Split launcher-centric orchestration into reusable shell modules.

### Milestones
1. WA-4.1 Define module trait (`init`, `start`, `stop`, `handle_event`, `health`).
2. WA-4.2 Extract launcher runtime from monolithic GTK shell orchestration.
3. WA-4.3 Add notifications module registration.
4. WA-4.4 Add shared in-process event bus and typed events.

### Acceptance Criteria
- Launcher and notifications compile as independent modules under one daemon.
- Module startup/shutdown ordering is explicit and testable.
- Cross-module communication no longer depends on direct imports.

## Suggested Execution Order
1. WA-1 Shell control plane.
2. WA-4 Module boundary hardening (minimal slice).
3. WA-2 Notifications MVP.
4. WA-5 Surface placement + WM abstraction.
5. WA-3 Event-driven compositor integration.

## Tracking Notes
- Keep each milestone shippable in 1-3 commits.
- Add each accepted slice to `docs/TASK_QUEUE.md`.
- Record architecture decisions in `docs/DE_SHELL_VISION.md` when plans change.
