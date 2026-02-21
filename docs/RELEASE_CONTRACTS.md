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

## CI Guard

- CI non-interactive validate guard:
  - `scripts/check_release_validate_ci.sh`

This is included by default in `scripts/check_release_contracts.sh` (unless `--docs-only` is used).
