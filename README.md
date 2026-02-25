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

Lua config (optional):
```bash
zig build -Denable_gtk=true -Denable_lua_config=true
```
Config file path defaults to `~/.config/god-search-ui/config.lua` (override with `GOD_SEARCH_CONFIG_LUA`).
When missing, a default config file is auto-created at startup (Lua-config-enabled build).
Generate default config:
```bash
scripts/init_lua_config.sh
```
Patch common Lua config keys quickly:
```bash
scripts/set_lua_config.sh surface_mode layer-shell
scripts/set_lua_config.sh launcher.monitor_name DP-1
```
Placement docs:
- canonical operator flow: `docs/operations/PLACEMENT_OPERATOR_FLOW.md`
- full Lua contract + env matrix: `docs/operations/LUA_CONFIG.md`

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
```
Reference: `docs/operations/CONTROL_PLANE.md`

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
scripts/dev_notifications_takeover.sh takeover
scripts/dev_notifications_takeover.sh smoke
scripts/check_shell_health_contract.sh
```
`smoke` also sends an action-capable notification; click its action button while running `dbus-monitor` to observe `ActionInvoked`.

Draft release notes from latest commits:
```bash
scripts/gen_release_notes.sh v0.1.0
```

Release smoke checks:
```bash
scripts/release_smoke.sh
```
Headless smoke now includes `:icondiag` to validate icon metadata/fallback diagnostics path.
Strict icon-threshold mode (CI-oriented):
```bash
scripts/release_smoke.sh --strict-icon-threshold --icon-threshold=5
```
CI/minimal-host mode without GTK dev packages:
```bash
scripts/release_smoke.sh --ci
```
One-pass operator validation wrapper:
```bash
scripts/release_validate.sh --ci
```
Enforce clean worktree during validation:
```bash
scripts/release_validate.sh --ci --require-clean
```
CI non-interactive guard:
```bash
scripts/check_release_validate_ci.sh
```
Release smoke mode reference:
- `docs/operations/RELEASE_SMOKE_MODES.md`
Release validate mode reference:
- `docs/operations/RELEASE_VALIDATE_MODES.md`
Release contracts reference:
- `docs/operations/RELEASE_CONTRACTS.md`

Release contracts quick cheat sheet:
```bash
scripts/check_release_contracts.sh --docs-only
scripts/release_validate.sh --ci --require-clean
scripts/check_release_validate_ci.sh
```
Optional GTK runtime launch smoke:
```bash
scripts/release_smoke.sh --with-gtk-runtime
```
This optional mode uses a temporary `HOME` with a 4-column apps cache fixture to exercise app icon render paths.
Release-helper CLI contract checks:
```bash
scripts/check_release_helpers.sh
```
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
Release smoke help/docs contract check:
```bash
scripts/check_release_smoke_contract.sh
```
Meta guard for all release docs contracts:
```bash
scripts/check_release_docs_contracts.sh
```
One-command alias for all release contract checks:
```bash
scripts/check_release_contracts.sh
```
Fast docs-only variant:
```bash
scripts/check_release_contracts.sh --docs-only
```
Release-contracts alias help/docs contract check:
```bash
scripts/check_release_contracts_contract.sh
```
Release-contracts doc consistency check:
```bash
scripts/check_release_contracts_doc.sh
```
Placement config/template/docs contract check:
```bash
scripts/check_placement_contracts.sh
```
Placement precedence regression check:
```bash
scripts/check_placement_precedence.sh
```
Lua config schema validator:
```bash
scripts/validate_lua_config.sh
```
Lua validator canary checks:
```bash
scripts/check_lua_config_validator.sh
```
Release-validate help/docs contract check:
```bash
scripts/check_release_validate_contract.sh
```
Release script-matrix checks:
```bash
scripts/check_release_matrix.sh
```
Default-safe cut dry-run checks:
```bash
scripts/check_cut_dryrun_default_safe.sh
```
v0.1.1 pre-cut readiness gate:
```bash
scripts/precut_v0_1_1.sh
```
Release notes lint:
```bash
scripts/lint_release_notes.sh docs/release-notes-v0.1.1.md
```

Arch package smoke helper:
```bash
scripts/arch_package_smoke.sh
```

Release tag flow helper (dry-run by default):
```bash
scripts/cut_release_tag.sh --version v0.1.0
```
To include release notes in the tagged commit:
```bash
scripts/cut_release_tag.sh --version v0.1.0 --apply --commit-notes
```
To preserve already-edited release notes during apply:
```bash
scripts/cut_release_tag.sh --version v0.1.1 --apply --commit-notes --reuse-notes
```
To force regeneration (override default-safe reuse):
```bash
scripts/cut_release_tag.sh --version v0.1.2 --apply --commit-notes --regen-notes
```

Publish existing local tag helper (dry-run by default):
```bash
scripts/publish_release_tag.sh --version v0.1.0-rc2
```
With custom remote:
```bash
scripts/publish_release_tag.sh --version v0.1.0-rc2 --remote upstream
```

## Packaging
- Arch skeleton: `packaging/arch/PKGBUILD`
- systemd user unit template: `packaging/systemd/god-search-ui.service`
- desktop entry template: `packaging/desktop/god-search-ui.desktop`
- icon asset: `assets/icons/god-search-ui.svg`
- docs index and governance: `docs/README.md`
- Notes: `docs/operations/ARCH_PACKAGING.md`
- Arch packaged install smoke: `docs/operations/PACKAGED_INSTALL_SMOKE.md`
- Hypr/Waybar integration: `docs/operations/HYPR_WAYBAR_INTEGRATION.md`
- DE shell vision and architecture plan: `docs/architecture/DE_SHELL_VISION.md`
- DE weak-areas execution roadmap: `docs/roadmaps/DE_WEAK_AREAS_ROADMAP.md`
- WA-1 shell control-plane spec: `docs/architecture/WA1_CONTROL_PLANE_SPEC.md`
- notifications protocol lock (from vendor artifacts): `docs/architecture/NOTIFICATIONS_PROTOCOL_LOCK.md`
- vendor references index: `docs/vendor/README.md`
- local external implementation workspace: `reference_repo/README.md`
- GTK rollout checklist: `docs/operations/GTK_ROLLOUT_CHECKLIST.md`
- Troubleshooting runbook: `docs/operations/TROUBLESHOOTING_RUNBOOK.md`
- Release notes template: `docs/releases/RELEASE_NOTES_TEMPLATE.md`
- Release notes curation checklist: `docs/releases/RELEASE_NOTES_CURATION_CHECKLIST.md`
- Release tagging/rollback runbook: `docs/operations/RELEASE_TAG_ROLLBACK_RUNBOOK.md`
- Release script matrix: `docs/operations/RELEASE_SCRIPT_MATRIX.md`
- Release contracts reference: `docs/operations/RELEASE_CONTRACTS.md`
- v0.1.1 patch plan (archived): `docs/archive/2026/V0_1_1_PATCH_PLAN.md`
- Post-release triage template: `docs/project/POST_RELEASE_TRIAGE_TEMPLATE.md`
- Triage log: `docs/project/TRIAGE_LOG.md`
- Icon diagnostics reference: `docs/operations/ICON_DIAGNOSTICS.md`

## Next
- Wire GTK4/libadwaita bindings via C interop.
- Implement provider contract (apps/windows/dirs/actions).
- For release operations, start with `scripts/check_release_contracts.sh --docs-only` then `scripts/release_validate.sh --ci --require-clean`.
- Add ranked blended results model.
