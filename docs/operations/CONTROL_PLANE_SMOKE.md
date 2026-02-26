# Control Plane Smoke

Status: active  
Owner: shell  
Last-Reviewed: 2026-02-25  
Canonical: yes

## Purpose

Validate resident daemon control-plane command behavior with an isolated socket namespace.

## Prerequisites

```bash
zig build -Doptimize=ReleaseFast -Denable_gtk=true
```

Requires an active display session (`WAYLAND_DISPLAY` or `DISPLAY`).

## Run

```bash
scripts/control_plane_smoke.sh
```

## What It Covers

1. starts daemon (`--ui-daemon`) in a temporary `XDG_RUNTIME_DIR`
2. checks `--ctl ping`
3. checks `--ctl summon`
4. checks `--ctl hide`
5. checks `--ctl toggle`
6. checks `--ctl wm_event_stats`
7. verifies `--print-shell-health` includes launcher/notifications module lines

## Expected Result

```text
control plane smoke passed
```
