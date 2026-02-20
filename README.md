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

## Dev Loop Commands
```bash
scripts/dev.sh check
scripts/dev.sh fmt
scripts/dev.sh build
scripts/dev.sh test
```

## Next
- Wire GTK4/libadwaita bindings via C interop.
- Implement provider contract (apps/windows/dirs/actions).
- Add ranked blended results model.
