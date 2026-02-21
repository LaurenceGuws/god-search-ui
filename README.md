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

Optional advanced refresh mode:
```bash
GOD_SEARCH_ASYNC_REFRESH=1 god-search-ui --ui
```

## Dev Loop Commands
```bash
scripts/dev.sh check
scripts/dev.sh fmt
scripts/dev.sh build
scripts/dev.sh test
```

Draft release notes from latest commits:
```bash
scripts/gen_release_notes.sh v0.1.0
```

Release smoke checks:
```bash
scripts/release_smoke.sh
```
Optional GTK runtime launch smoke:
```bash
scripts/release_smoke.sh --with-gtk-runtime
```
Release-helper CLI contract checks:
```bash
scripts/check_release_helpers.sh
```
Release script-matrix checks:
```bash
scripts/check_release_matrix.sh
```
v0.1.1 pre-cut readiness gate:
```bash
scripts/precut_v0_1_1.sh
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
- Notes: `docs/ARCH_PACKAGING.md`
- Arch packaged install smoke: `docs/PACKAGED_INSTALL_SMOKE.md`
- Hypr/Waybar integration: `docs/HYPR_WAYBAR_INTEGRATION.md`
- GTK rollout checklist: `docs/GTK_ROLLOUT_CHECKLIST.md`
- Troubleshooting runbook: `docs/TROUBLESHOOTING_RUNBOOK.md`
- Release notes template: `docs/RELEASE_NOTES_TEMPLATE.md`
- Release tagging/rollback runbook: `docs/RELEASE_TAG_ROLLBACK_RUNBOOK.md`
- Release script matrix: `docs/RELEASE_SCRIPT_MATRIX.md`
- v0.1.1 patch plan: `docs/V0_1_1_PATCH_PLAN.md`
- Post-release triage template: `docs/POST_RELEASE_TRIAGE_TEMPLATE.md`
- Triage log: `docs/TRIAGE_LOG.md`

## Next
- Wire GTK4/libadwaita bindings via C interop.
- Implement provider contract (apps/windows/dirs/actions).
- Add ranked blended results model.
