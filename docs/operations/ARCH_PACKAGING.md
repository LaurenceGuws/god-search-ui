# Arch Packaging Notes

## Skeleton Files
- `packaging/arch/PKGBUILD`
- `packaging/desktop/god-search-ui.desktop`
- `assets/icons/god-search-ui.svg`

## Build Locally
```bash
cd packaging/arch
makepkg -si
```

## GTK-enabled variant
The default `PKGBUILD` compiles without GTK for portability.
To produce a GTK-enabled package, edit `build()` and use:
```bash
zig build -Doptimize=ReleaseSafe -Denable_gtk=true
```

You may also need runtime deps such as:
- `gtk4`
- `libadwaita`

## Installed Binary
- `/usr/bin/god-search-ui`
- `/usr/share/applications/god-search-ui.desktop`
- `/usr/share/icons/hicolor/scalable/apps/god-search-ui.svg`

## Suggested post-install check
```bash
god-search-ui --ui
```

For full package-build/install/uninstall validation, run:
- `docs/PACKAGED_INSTALL_SMOKE.md`

## Release notes draft helper
Generate a notes draft from the release template + recent commits:
```bash
scripts/gen_release_notes.sh v0.1.0
```
