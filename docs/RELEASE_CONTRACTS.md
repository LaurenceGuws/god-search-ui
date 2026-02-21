# Release Contracts

Release contracts are guard scripts that keep release automation CLI/docs behavior synchronized.

## Primary Entry Points

- Full contracts alias:
  - `scripts/check_release_contracts.sh`
- Docs-only contracts alias:
  - `scripts/check_release_contracts.sh --docs-only`

## Contract Layers

- Helper CLI contract:
  - `scripts/check_release_helpers.sh`
- Release matrix contract:
  - `scripts/check_release_matrix.sh`
- Release smoke contract:
  - `scripts/check_release_smoke_contract.sh`
- Release validate contract:
  - `scripts/check_release_validate_contract.sh`
- Release contracts alias contract:
  - `scripts/check_release_contracts_contract.sh`
- Meta docs contracts:
  - `scripts/check_release_docs_contracts.sh`

## When To Run Which Script

| Situation | Script |
|---|---|
| Quick docs/help/matrix contract check | `scripts/check_release_contracts.sh --docs-only` |
| Full local contract check (includes CI validate guard) | `scripts/check_release_contracts.sh` |
| Release preflight from clean worktree | `scripts/release_validate.sh --ci --require-clean` |
| Local iterative preflight before commit | `RELEASE_VALIDATE_ALLOW_DIRTY=1 scripts/release_validate.sh --ci --require-clean` |

## CI Guard

- CI non-interactive validate guard:
  - `scripts/check_release_validate_ci.sh`

This is included by default in `scripts/check_release_contracts.sh` (unless `--docs-only` is used).

## Operator Quick Order

1. `scripts/check_release_contracts.sh --docs-only`
2. `scripts/release_validate.sh --ci --require-clean`
3. `scripts/gen_release_notes.sh vX.Y.Z docs/release-notes-vX.Y.Z.md`
4. `scripts/cut_release_tag.sh --version vX.Y.Z --apply --commit-notes --push`
5. `scripts/publish_release_tag.sh --version vX.Y.Z --apply`

## Related References

- `docs/RELEASE_TAG_ROLLBACK_RUNBOOK.md`
- `docs/RELEASE_SMOKE_MODES.md`
- `docs/RELEASE_VALIDATE_MODES.md`

## Local Dirty-Worktree Quick Smoke

During active local iteration (before committing), use:

```bash
RELEASE_VALIDATE_ALLOW_DIRTY=1 scripts/check_release_contracts.sh
```

This preserves contract coverage while bypassing clean-worktree enforcement for local dev loops.

Warning:
- Do not use dirty-worktree override in CI or release cut/tag workflows.
- For release cutovers, run `scripts/release_validate.sh --ci --require-clean` from a clean worktree.
