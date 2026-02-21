#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DOC="docs/RELEASE_CONTRACTS.md"
test -f "$DOC"

rg -q --fixed-strings "# Release Contracts" "$DOC"
rg -q --fixed-strings "## Primary Entry Points" "$DOC"
rg -q --fixed-strings "## Contract Layers" "$DOC"
rg -q --fixed-strings "## CI Guard" "$DOC"

rg -q --fixed-strings "scripts/check_release_contracts.sh" "$DOC"
rg -q --fixed-strings "scripts/check_release_docs_contracts.sh" "$DOC"
rg -q --fixed-strings "scripts/check_release_validate_ci.sh" "$DOC"
rg -q --fixed-strings "scripts/check_release_contracts_contract.sh" "$DOC"

echo "release contracts doc checks passed"
