# god-search-ui

Scaffold for a Spotlight-style launcher UI on Wayland.

## Bootstrapped
- `zig init` (Zig 0.15.2)
- base source: `src/main.zig`, `src/root.zig`
- project directories:
  - `src/ui`
  - `src/providers`
  - `src/search`
  - `assets/icons`
  - `docs`

## Run
```bash
zig build run
```

### UI Shell
Headless/stub UI:
```bash
zig build run -- --ui
```
In headless mode, type queries and press Enter. Commands:
- `:q` to exit
- `:refresh` to invalidate + prewarm provider snapshot cache
- `:icondiag` to print app icon metadata/fallback diagnostics
- `:icondiag --json` for machine-readable icon diagnostics output

GTK4 shell (requires GTK4 dev libraries):
```bash
zig build -Denable_gtk=true run -- --ui
```
In GTK mode, use `Ctrl+R` to refresh provider snapshot cache.
Route prefixes include `@ # ! ~ % & $ > = ?` (`$` = notifications history/dismiss route).
Optional deterministic Wayland anchoring via layer-shell:
```bash
zig build -Denable_gtk=true -Denable_layer_shell=true run -- --ui --surface-mode layer-shell
```
Surface mode can also be set by env:
```bash
GOD_SEARCH_SURFACE_MODE=layer-shell god-search-ui --ui
```
Accepted values: `auto` (default), `toplevel`, `layer-shell`.

Lua config:
```bash
zig build -Denable_gtk=true
```
Config file path defaults to `~/.config/god-search-ui/config.lua` (override with `GOD_SEARCH_CONFIG_LUA`).
When missing, a default config file is auto-created on app startup paths that load runtime config.
Generate default config:
```bash
scripts/init_lua_config.sh
```
Patch common Lua config keys quickly:
```bash
scripts/set_lua_config.sh surface_mode layer-shell
scripts/set_lua_config.sh launcher.monitor_name DP-1
```
Docs:
- docs index: `docs/INDEX.md`
- workflow + handoff: `docs/WORKFLOW.md`, `docs/AGENT_HANDOFF.md`
- design + coding standards: `docs/DESIGN_AND_STANDARDS.md`

Resident GTK modes (recommended for zero-drop fast summon):
```bash
# Keep GTK process alive and visible on first launch
god-search-ui --ui-resident

# Keep GTK process alive and hidden until summon
god-search-ui --ui-daemon
```
With `--ui-daemon`, bind your launcher key to `god-search-ui --ui` so each press re-activates the warm instance.

Control-plane commands (for resident/daemon mode):
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
Reference: `docs/architecture/WA1_CONTROL_PLANE_SPEC.md`

Control-plane quickstart:
```bash
god-search-ui --ui-daemon
god-search-ui --ctl ping
god-search-ui --ctl summon
god-search-ui --print-shell-health
```

Runtime config introspection (prints resolved surface mode + placement policy):
```bash
god-search-ui --print-config
```

Output discovery for monitor pinning:
```bash
god-search-ui --print-outputs
```
Shell module health snapshot:
```bash
god-search-ui --print-shell-health
```
If a daemon is running, this queries live module health over the control socket.
Placement smoke:
```bash
scripts/placement_smoke.sh
```

Optional advanced refresh mode:
```bash
GOD_SEARCH_ASYNC_REFRESH=1 god-search-ui --ui
```

Apps cache supports optional icon metadata:
- `category<TAB>name<TAB>exec` (legacy)
- `category<TAB>name<TAB>exec<TAB>icon` (preferred for GTK app icons)
- icon resolution order: metadata `icon` -> derived `exec` token -> glyph fallback

## Dev Loop Commands
```bash
scripts/dev.sh check
scripts/dev.sh fmt
scripts/dev.sh build
scripts/dev.sh test
scripts/dev_notif_start.sh start --mask-swaync
scripts/dev_notifications_takeover.sh takeover
scripts/dev_notifications_takeover.sh smoke
scripts/wm_event_refresh_smoke.sh
scripts/check_shell_health_contract.sh
scripts/control_plane_smoke.sh
```
`smoke` validates replace-id behavior, `body-markup` capability, persistent close (`reason=3`), and timeout close (`reason=1`).  
It also sends an action-capable notification; click its action button while running `dbus-monitor` to observe `ActionInvoked`.

Apps cache format compatibility checks:
```bash
scripts/check_apps_cache_format.sh
```
Icon theme environment preflight:
```bash
scripts/check_icon_theme_env.sh
```
Icon diagnostics JSON schema check:
```bash
scripts/check_icondiag_json.sh
```
Icon diagnostics threshold gate (fails when fallback ratio exceeds limit):
```bash
MAX_GLYPH_FALLBACK_PCT=5 scripts/check_icondiag_threshold.sh
```
Lua config schema validator:
```bash
scripts/validate_lua_config.sh
```
Lua validator canary checks:
```bash
scripts/check_lua_config_validator.sh
```

## Packaging
- Arch skeleton: `packaging/arch/PKGBUILD`
- systemd user unit template: `packaging/systemd/god-search-ui.service`
- desktop entry template: `packaging/desktop/god-search-ui.desktop`
- icon asset: `assets/icons/god-search-ui.svg`
- docs index and governance: `docs/INDEX.md`
- DE shell vision and architecture plan: `docs/architecture/DE_SHELL_VISION.md`
- WA-1 shell control-plane spec: `docs/architecture/WA1_CONTROL_PLANE_SPEC.md`
- local external implementation workspace: `reference_repo/README.md`
- workflow + status index: `docs/INDEX.md`

## Next
- Wire GTK4/libadwaita bindings via C interop.
- Implement provider contract (apps/windows/dirs/actions).
- Add ranked blended results model.
