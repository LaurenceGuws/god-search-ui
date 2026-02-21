# Packaged Install Smoke (Arch)

Validate package install and launcher integration end-to-end.

## Fast Path
Automated helper:
```bash
scripts/arch_package_smoke.sh
```

With install/uninstall checks:
```bash
scripts/arch_package_smoke.sh --install --uninstall
```

## Prerequisites
- Arch-based system with `makepkg`
- Build deps installed (`zig`, `git`)

## 1. Build Package
```bash
cd packaging/arch
makepkg -f
```

## 2. Install Package
```bash
sudo pacman -U ./god-search-ui-git-*.pkg.tar.*
```

## 3. Validate Installed Artifacts
```bash
command -v god-search-ui
test -f /usr/share/applications/god-search-ui.desktop
test -f /usr/share/icons/hicolor/scalable/apps/god-search-ui.svg
```

## 4. Desktop Entry Validation
```bash
desktop-file-validate /usr/share/applications/god-search-ui.desktop
grep -E '^Exec=god-search-ui --ui$' /usr/share/applications/god-search-ui.desktop
grep -E '^Icon=god-search-ui$' /usr/share/applications/god-search-ui.desktop
```

## 5. Runtime Smoke
```bash
god-search-ui --ui
```

In headless mode:
- run `:refresh`
- search `kitty`
- run `:q`

## 6. Uninstall Smoke
```bash
sudo pacman -R god-search-ui-git
```

Confirm cleanup:
```bash
! command -v god-search-ui
```
