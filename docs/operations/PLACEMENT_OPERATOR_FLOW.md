# Placement Operator Flow

Status: active  
Owner: shell  
Last-Reviewed: 2026-02-25  
Canonical: yes

## Goal

One deterministic flow to configure and verify launcher/notifications placement.

## 1. Build

```bash
zig build -Denable_gtk=true -Denable_lua_config=true
```

Optional layer-shell backend:

```bash
zig build -Denable_gtk=true -Denable_lua_config=true -Denable_layer_shell=true
```

## 2. Initialize Config

Default config path: `~/.config/god-search-ui/config.lua`

```bash
scripts/init_lua_config.sh
```

Patch common keys:

```bash
scripts/set_lua_config.sh surface_mode layer-shell
scripts/set_lua_config.sh launcher.monitor_name DP-1
scripts/set_lua_config.sh launcher.anchor top_center
scripts/set_lua_config.sh notifications.anchor top_right
```

## 3. Inspect Outputs

```bash
god-search-ui --print-outputs
```

Use exact output names for `*.monitor_name` or `GOD_SEARCH_*_MONITOR` overrides.

## 4. Resolve Effective Runtime Policy

```bash
god-search-ui --print-config
```

Precedence summary:
1. CLI (`--surface-mode`)
2. env (`GOD_SEARCH_*`)
3. Lua config (`config.lua`)
4. defaults

## 5. Smoke Placement

Generic smoke:

```bash
scripts/placement_smoke.sh
```

Pinned-output smoke:

```bash
scripts/placement_smoke.sh DP-1
```

## 6. Validate Contracts

```bash
scripts/validate_lua_config.sh
scripts/check_lua_config_validator.sh
scripts/check_placement_precedence.sh
scripts/check_placement_contracts.sh
```

## 7. Summon Path Check

For warm summon setup:

```bash
god-search-ui --ui-daemon
god-search-ui --ui
```

Type immediately after summon and verify first-key reliability against your previous launcher baseline.
