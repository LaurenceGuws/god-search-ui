# Arch Packaging Notes

## Skeleton Files
- `packaging/arch/PKGBUILD`

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

## Suggested post-install check
```bash
god-search-ui --ui
```
