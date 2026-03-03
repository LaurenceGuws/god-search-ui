# Troubleshooting

Status: active  
Owner: shell  
Last-Reviewed: 2026-03-03  
Canonical: yes

## Baseline

```bash
scripts/dev.sh check
zig build -Denable_gtk=true
```

## GTK Build Errors

Symptoms:
- `gtk/gtk.h` missing
- GTK c-import failures

Checks:
1. install GTK4 dev packages and `pkg-config`
2. verify `pkg-config --cflags --libs gtk4`
3. rerun `zig build -Denable_gtk=true`

## Empty / Wrong Results

Checks:
1. refresh query state (`Ctrl+R` in GTK)
2. confirm provider prerequisites:
- apps cache at `~/.cache/waybar/wofi-app-launcher.tsv`
- `hyprctl` + `jq` for window/workspace providers
- `zoxide` for dirs provider

If app icons are missing:
1. ensure apps cache has icon metadata column when possible
2. run icon diagnostics:
```bash
scripts/check_icondiag_json.sh
MAX_GLYPH_FALLBACK_PCT=5 scripts/check_icondiag_threshold.sh
```

## Control Plane Not Working

Symptoms:
- `--ctl ping` exits `10`
- summon/hide/toggle appears to do nothing

Checks:
1. verify runtime namespace:
```bash
echo "${XDG_RUNTIME_DIR:-<unset>}"
```
2. start daemon in same shell and retry:
```bash
god-search-ui --ui-daemon
god-search-ui --ctl ping
```
3. run control-plane smoke:
```bash
scripts/control_plane_smoke.sh
```

## Shell Health Stuck Offline

Symptoms:
- `--print-shell-health` shows offline snapshot while daemon should be up

Checks:
1. run `god-search-ui --ctl ping`
2. if reachable, rerun `god-search-ui --print-shell-health`
3. validate contract:
```bash
scripts/check_shell_health_contract.sh
```

## Placement Confusion

Checks:
1. inspect outputs:
```bash
god-search-ui --print-outputs
```
2. inspect effective policy:
```bash
god-search-ui --print-config
```
3. run placement smoke:
```bash
scripts/placement_smoke.sh
```
