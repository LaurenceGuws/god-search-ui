# GTK Rollout Checklist

Use this checklist to migrate from shell launcher flow to GTK launcher flow safely.

## Phase 0: Prerequisites

- [ ] GTK build compiles locally:
  - `zig build -Denable_gtk=true`
- [ ] UI runs:
  - `zig build run -Denable_gtk=true -- --ui`
- [ ] Existing shell fallback still works:
  - `zig build run -- --ui`

## Phase 1: Parallel Run (No Cutover Yet)

Keep existing shell keybind active and assign GTK launcher to a secondary key.

Example:
```ini
bind = $mainMod, SPACE, exec, bash $HOME/.config/hypr/scripts/god-search.sh
bind = $mainMod SHIFT, SPACE, exec, god-search-ui --ui
```

Validation:
- [ ] Search query updates in GTK mode
- [ ] Enter executes selected app/action
- [ ] `power` requires second confirmation
- [ ] `Ctrl+R` refreshes snapshot cache

## Phase 2: Primary Keybind Cutover

Switch primary keybind to GTK launcher.

Example:
```ini
bind = $mainMod, SPACE, exec, god-search-ui --ui
```

Keep shell fallback on a backup bind for one release window:
```ini
bind = $mainMod SHIFT, SPACE, exec, bash $HOME/.config/hypr/scripts/god-search.sh
```

Validation:
- [ ] Daily usage pass for 24h+
- [ ] No crash under repeated open/close
- [ ] Query latency remains acceptable
- [ ] Telemetry log receives action events

## Phase 3: Waybar Integration Cutover

Point launcher button to GTK launcher:

```jsonc
"custom/wofi": {
  "on-click": "god-search-ui --ui"
}
```

Validation:
- [ ] Button launches GTK palette
- [ ] Keybind and button both use same runtime path

## Phase 4: Shell Flow Decommission

Only after stable burn-in:
- [ ] Remove old shell launcher keybind
- [ ] Remove old shell launcher button command paths
- [ ] Keep rollback branch/tag documented

## Go / No-Go Gates

Go only if:
- [ ] `scripts/dev.sh check` passing
- [ ] GTK build passing on target machine
- [ ] No blocker in `docs/BLOCKERS.md`

No-Go if any of:
- [ ] Startup crash
- [ ] Action execution regressions
- [ ] Unacceptable query stutter

## Rollback Plan

Immediate rollback command path:
1. Restore previous Hypr keybind (`god-search.sh`)
2. Restore Waybar launcher click command
3. Restart Waybar + reload Hyprland config

Post-rollback:
- [ ] Capture blocker in `docs/BLOCKERS.md`
- [ ] Record failing commit hash + repro steps

## Suggested Burn-in Window

- Minimum: 2 days personal usage
- Preferred: 5 days with mixed workflows (apps/windows/dirs/actions)
