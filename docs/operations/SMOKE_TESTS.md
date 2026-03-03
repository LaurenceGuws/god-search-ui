# Smoke Tests

Status: active  
Owner: shell  
Last-Reviewed: 2026-03-03  
Canonical: yes

## Goal

Fast checks for daemon control, shell health, placement, WM event refresh, and icon diagnostics.

## Build Prereq

```bash
zig build -Doptimize=ReleaseFast -Denable_gtk=true -Denable_layer_shell=true
```

Use a display session (`WAYLAND_DISPLAY` or `DISPLAY`) for daemon/GTK smokes.

## Control Plane

```bash
scripts/control_plane_smoke.sh
```

Covers:
1. daemon startup (`--ui-daemon`) in isolated runtime dir
2. `--ctl ping|summon|hide|toggle|wm_event_stats`
3. `--print-shell-health` module lines for launcher/notifications

## Shell Health Contract

```bash
scripts/check_shell_health_contract.sh
```

Covers:
1. offline fallback output when daemon is absent
2. live module-health output when daemon is running

## Placement

```bash
scripts/placement_smoke.sh
scripts/placement_smoke.sh DP-1
```

Covers:
1. output discovery via `--print-outputs`
2. effective runtime policy via `--print-config`
3. optional assertion that a named output exists

## WM Event Refresh

```bash
scripts/wm_event_refresh_smoke.sh
```

Covers:
1. WM event bridge wiring
2. `--ctl wm_event_stats` read path

## Icon Diagnostics

```bash
scripts/check_icondiag_json.sh
MAX_GLYPH_FALLBACK_PCT=5 scripts/check_icondiag_threshold.sh
```

Covers:
1. expected JSON keys from `:icondiag --json`
2. fallback-rate threshold gate (`glyph_fallback_pct`)
