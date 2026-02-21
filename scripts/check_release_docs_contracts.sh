#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

scripts/check_release_helpers.sh
scripts/check_release_matrix.sh
scripts/check_release_smoke_contract.sh
scripts/check_release_validate_contract.sh
scripts/check_release_contracts_contract.sh
scripts/check_release_contracts_doc.sh

echo "release docs contract checks passed"
