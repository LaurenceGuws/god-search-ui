# Control Plane

Status: active  
Owner: shell  
Last-Reviewed: 2026-02-25  
Canonical: yes

## Overview

The control plane lets clients interact with a resident daemon over a local Unix socket.

Socket path resolution:
1. `$XDG_RUNTIME_DIR/god-search-ui.sock`
2. fallback: `/tmp/god-search-ui-<uid>.sock`

## Commands

```bash
god-search-ui --ctl --help
god-search-ui --ctl ping
god-search-ui --ctl summon
god-search-ui --ctl hide
god-search-ui --ctl toggle
god-search-ui --ctl version
god-search-ui --ctl shell_health
god-search-ui --ctl wm_event_stats
```

## Semantics

- `ping`: check daemon availability.
- `summon`: activate/show launcher surface.
- `hide`: hide launcher surface.
- `toggle`: show/hide launcher surface.
- `version`: daemon version string.
- `shell_health`: compact live module-health payload used by `--print-shell-health`.
- `wm_event_stats`: compact WM event-refresh counters (`events/scheduled/skipped/failed`).

## Exit Codes

- `0`: command accepted/succeeded.
- `10`: daemon unreachable or command rejected.
- `13`: invalid `--ctl` command value.

## Health Query Flow

`--print-shell-health` behavior:
1. try live query via `--ctl shell_health`
2. if unavailable/unreachable, print offline diagnostics snapshot

Manual smoke:

```bash
god-search-ui --ui-daemon
god-search-ui --ctl ping
god-search-ui --ctl shell_health
god-search-ui --print-shell-health
```

Scripted equivalent:

```bash
scripts/control_plane_smoke.sh
```

## Notes

- Control-plane commands are intended for daemon/resident mode.
- `shell_health` payload is compact transport text; human-readable formatting is applied by CLI diagnostics.
- Smoke workflow reference: `docs/operations/CONTROL_PLANE_SMOKE.md`
