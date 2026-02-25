# Release Validate Modes

`scripts/release_validate.sh` is an operator wrapper that runs:
- `scripts/release_smoke.sh`
- `scripts/check_release_docs_contracts.sh`

## Modes

| Mode | Command | Intended Use |
|---|---|---|
| Default | `scripts/release_validate.sh` | Full local validation wrapper |
| CI preset | `scripts/release_validate.sh --ci` | CI/minimal-host release validation |
| Clean preflight | `scripts/release_validate.sh --ci --require-clean` | Enforce clean worktree before validation |
| Local override | `scripts/release_validate.sh --ci --require-clean --allow-dirty` | Dev-only override during active local iteration |

## Options

- `--require-clean`: run `scripts/check_clean_worktree.sh` before validation.
- `--allow-dirty`: bypass clean-worktree requirement.
- `--help`: print option help.
- other args are forwarded to `scripts/release_smoke.sh`.

## Expected Success Markers

- `release smoke checks passed`
- `release docs contract checks passed`
- `release validation passed`
