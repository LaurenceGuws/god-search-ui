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

GTK4 shell (requires GTK4 dev libraries):
```bash
zig build -Denable_gtk=true run -- --ui
```
In GTK mode, use `Ctrl+R` to refresh provider snapshot cache.

## Dev Loop Commands
```bash
scripts/dev.sh check
scripts/dev.sh fmt
scripts/dev.sh build
scripts/dev.sh test
```

## Packaging
- Arch skeleton: `packaging/arch/PKGBUILD`
- systemd user unit template: `packaging/systemd/god-search-ui.service`
- Notes: `docs/ARCH_PACKAGING.md`
- Hypr/Waybar integration: `docs/HYPR_WAYBAR_INTEGRATION.md`
- GTK rollout checklist: `docs/GTK_ROLLOUT_CHECKLIST.md`
- Troubleshooting runbook: `docs/TROUBLESHOOTING_RUNBOOK.md`

## Next
- Wire GTK4/libadwaita bindings via C interop.
- Implement provider contract (apps/windows/dirs/actions).
- Add ranked blended results model.
