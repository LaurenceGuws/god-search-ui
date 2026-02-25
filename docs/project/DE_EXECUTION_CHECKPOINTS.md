Status: active
Owner: shell
Last-Reviewed: 2026-02-25
Canonical: yes

# DE Execution Checkpoints

This is the strict implementation gate for near-term shell-daemon work.

## CP-0 Docs Governance Baseline

Scope:
- categorized docs tree
- canonical ownership headers
- vendor artifact workflow

Done criteria:
1. `docs/README.md` exists and matches current structure.
2. Canonical DE docs contain status/owner/review headers.
3. Vendor fetch flow produces `.html` plus `.md`/`.txt`.
4. Release docs contracts still pass.

Verification:
```bash
scripts/check_release_contracts.sh --docs-only
```

## CP-1 Control Plane MVP

Scope:
- unix socket server in resident mode
- commands: `ping`, `summon`, `hide`, `toggle`, `version`
- `--ui` summon-first client behavior

Done criteria:
1. `--ui-resident` starts socket listener.
2. `--ctl ping` returns success when daemon exists.
3. `--ui` reuses resident daemon (no duplicate process).
4. `summon/hide/toggle` route through socket path.

Verification:
```bash
zig build -Denable_gtk=true
zig build test -Denable_gtk=true
./zig-out/bin/god_search_ui --ctl ping
./zig-out/bin/god_search_ui --ctl summon
./zig-out/bin/god_search_ui --ctl hide
./zig-out/bin/god_search_ui --ctl toggle
```

## CP-1.1 Control Plane Hardening

Scope:
- strict client response parsing
- explicit timeout behavior
- socket mode `0600`
- stale socket tests

Done criteria:
1. Client rejects malformed response payloads.
2. Timeout path is deterministic and non-hanging.
3. Socket file permissions are user-private.
4. Stale socket startup path has test coverage.

Verification:
```bash
zig build test -Denable_gtk=true
```

## CP-2 Notifications Signature Lock-In

Scope:
- signatures and signal behavior aligned to locked protocol file

Done criteria:
1. `docs/NOTIFICATIONS_PROTOCOL_LOCK.md` matches vendor protocol artifacts.
2. All deferred capabilities are explicit.
3. WA-2 implementation starts only after this checkpoint is marked done.

Verification:
```bash
rg -n "Notify\\(|CloseNotification\\(|GetCapabilities\\(|GetServerInformation\\(|NotificationClosed\\(|ActionInvoked\\(|ActivationToken\\(" docs/vendor/notifications/notification-protocol.txt
```

## CP-3 Notifications Daemon MVP (D-Bus)

Scope:
- register `org.freedesktop.Notifications` on session bus in resident shell mode
- implement methods: `GetCapabilities`, `Notify`, `CloseNotification`, `GetServerInformation`
- in-memory notification ID lifecycle with `replaces_id` support
- emit `NotificationClosed(id, 3)` on `CloseNotification` of existing notifications

Done criteria:
1. Resident mode owns `org.freedesktop.Notifications` on session bus.
2. `GetCapabilities` returns declared MVP subset.
3. `Notify` returns stable IDs and honors `replaces_id` when present.
4. `CloseNotification` returns success and emits `NotificationClosed` reason `3` for existing IDs.
5. Build/tests pass with GTK enabled.

Verification:
```bash
zig build -Denable_gtk=true
zig build test -Denable_gtk=true
./zig-out/bin/god_search_ui --ui-daemon
gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.GetServerInformation
gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.GetCapabilities
notify-send "god-search-ui" "dbus smoke"
```

## CP-4 Notifications Popup + Close Reasons

Scope:
- GTK popup stack for notifications in resident daemon mode
- `replaces_id` updates existing popup in place
- timeout and dismiss interactions close notifications with spec reasons

Done criteria:
1. Notification popups render in resident daemon mode.
2. `notify-send -p -r <id>` preserves notification ID (`replaces_id` behavior).
3. Timeout emits `NotificationClosed(id, 1)`.
4. D-Bus `CloseNotification` emits `NotificationClosed(id, 3)`.
5. Control daemon remains healthy (`--ctl ping` succeeds while popup flow is active).

Verification:
```bash
scripts/dev_notifications_takeover.sh takeover
scripts/dev_notifications_takeover.sh smoke
```

## CP-5 Notifications Actions + Hints (MVP)

Scope:
- parse `actions:as` and render action buttons in popup rows
- emit `ActionInvoked(id, action_key)` on action click
- parse MVP hints (`urgency`, `transient`) without request rejection

Done criteria:
1. `GetCapabilities` includes `actions`.
2. `Notify` accepts action arrays and popup renders action buttons.
3. Clicking an action button emits `ActionInvoked`.
4. Hints parsing does not break notifications with `urgency`/`transient`.

Verification:
```bash
scripts/dev_notifications_takeover.sh takeover
scripts/dev_notifications_takeover.sh smoke
# manual: click popup action button and confirm ActionInvoked via dbus-monitor
```
