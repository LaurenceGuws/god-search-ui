# Lua Config

Status: active  
Owner: shell  
Last-Reviewed: 2026-02-25  
Canonical: yes

## Build Flag

Enable Lua config support at build time:

```bash
zig build -Denable_gtk=true -Denable_lua_config=true
```

## File Location

- default: `~/.config/god-search-ui/config.lua`
- override: `GOD_SEARCH_CONFIG_LUA=/absolute/path/config.lua`

If the file is missing, the app auto-creates a default config on startup (when built with `-Denable_lua_config=true`) and then uses it.

Generate a default config file:

```bash
scripts/init_lua_config.sh
```

Optional custom path:

```bash
scripts/init_lua_config.sh /tmp/god-search-ui-config.lua
```

## Contract

```lua
return {
  surface_mode = "auto", -- auto | toplevel | layer-shell
  placement = {
    launcher = {
      anchor = "center",
      monitor_policy = "primary", -- primary | focused
      -- monitor_name = "DP-1",   -- optional: sets policy to by_name
      margins = { top = 12, right = 12, bottom = 12, left = 12 },
      width_percent = 48,
      height_percent = 56,
      min_width_percent = 32,
      min_height_percent = 36,
      min_width_px = 560,
      min_height_px = 360,
      max_width_px = 1100,
      max_height_px = 760,
    },
    notifications = {
      anchor = "top_right",
      monitor_policy = "primary", -- primary | focused
      -- monitor_name = "DP-1",   -- optional: sets policy to by_name
      margins = { top = 24, right = 24, bottom = 24, left = 24 },
      width_percent = 26,
      height_percent = 46,
      min_width_px = 300,
      min_height_px = 280,
      max_width_px = 460,
      max_height_px = 620,
    },
  },
}
```

Supported anchors:
- `center`
- `top_left`, `top_center`, `top_right`
- `bottom_left`, `bottom_center`, `bottom_right`

## Precedence

For `surface_mode`:
1. `--surface-mode`
2. `GOD_SEARCH_SURFACE_MODE`
3. Lua config `surface_mode`
4. default (`auto`)

Placement policy currently comes from Lua/default policy.
If `monitor_name` is provided for launcher/notifications, that surface targets the named output directly.

Core env overrides (applied after Lua/default policy):

```bash
GOD_SEARCH_LAUNCHER_MONITOR=DP-1
GOD_SEARCH_NOTIFICATIONS_MONITOR=DP-1
GOD_SEARCH_LAUNCHER_ANCHOR=top_center
GOD_SEARCH_NOTIFICATIONS_ANCHOR=top_right
GOD_SEARCH_LAUNCHER_MONITOR_POLICY=by_name
GOD_SEARCH_NOTIFICATIONS_MONITOR_POLICY=by_name
GOD_SEARCH_LAUNCHER_MARGIN_TOP=12
GOD_SEARCH_LAUNCHER_MARGIN_RIGHT=12
GOD_SEARCH_LAUNCHER_MARGIN_BOTTOM=12
GOD_SEARCH_LAUNCHER_MARGIN_LEFT=12
GOD_SEARCH_NOTIFICATIONS_MARGIN_TOP=24
GOD_SEARCH_NOTIFICATIONS_MARGIN_RIGHT=24
GOD_SEARCH_NOTIFICATIONS_MARGIN_BOTTOM=24
GOD_SEARCH_NOTIFICATIONS_MARGIN_LEFT=24
GOD_SEARCH_LAUNCHER_WIDTH_PERCENT=48
GOD_SEARCH_LAUNCHER_HEIGHT_PERCENT=56
GOD_SEARCH_LAUNCHER_MIN_WIDTH_PERCENT=32
GOD_SEARCH_LAUNCHER_MIN_HEIGHT_PERCENT=36
GOD_SEARCH_LAUNCHER_MIN_WIDTH_PX=560
GOD_SEARCH_LAUNCHER_MIN_HEIGHT_PX=360
GOD_SEARCH_LAUNCHER_MAX_WIDTH_PX=1100
GOD_SEARCH_LAUNCHER_MAX_HEIGHT_PX=760
GOD_SEARCH_NOTIFICATIONS_WIDTH_PERCENT=26
GOD_SEARCH_NOTIFICATIONS_HEIGHT_PERCENT=46
GOD_SEARCH_NOTIFICATIONS_MIN_WIDTH_PX=300
GOD_SEARCH_NOTIFICATIONS_MIN_HEIGHT_PX=280
GOD_SEARCH_NOTIFICATIONS_MAX_WIDTH_PX=460
GOD_SEARCH_NOTIFICATIONS_MAX_HEIGHT_PX=620
```

Inspect resolved runtime config:

```bash
god-search-ui --print-config
```

List available output names:

```bash
god-search-ui --print-outputs
```

Smoke helper:

```bash
scripts/placement_smoke.sh
```

Placement contract checker:

```bash
scripts/check_placement_contracts.sh
```
