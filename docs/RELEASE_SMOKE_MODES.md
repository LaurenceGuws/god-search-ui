# Release Smoke Modes

`scripts/release_smoke.sh` supports multiple execution modes.

| Mode | Command | Intended Use |
|---|---|---|
| Default | `scripts/release_smoke.sh` | Full local smoke including GTK build |
| CI preset | `scripts/release_smoke.sh --ci` | CI/minimal-host mode (skip GTK build + strict icon threshold) |
| Strict threshold | `scripts/release_smoke.sh --strict-icon-threshold --icon-threshold=5` | Enforce icon fallback quality gate locally |
| GTK runtime | `scripts/release_smoke.sh --with-gtk-runtime` | Optional launch-time GTK runtime sanity check |

## Notes

- `--ci` implies:
  - `--skip-gtk-build`
  - strict icon threshold mode with default `5%`
- `--icon-threshold=<N>` overrides the threshold in strict mode.
- Run `scripts/release_smoke.sh --help` for full CLI help.
