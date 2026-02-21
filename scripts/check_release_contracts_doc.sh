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
rg -q --fixed-strings "## Operator Quick Order" "$DOC"
rg -q --fixed-strings "## Local Dirty-Worktree Quick Smoke" "$DOC"

rg -q --fixed-strings "scripts/check_release_contracts.sh" "$DOC"
rg -q --fixed-strings "scripts/check_release_docs_contracts.sh" "$DOC"
rg -q --fixed-strings "scripts/check_release_validate_ci.sh" "$DOC"
rg -q --fixed-strings "scripts/check_release_contracts_contract.sh" "$DOC"
rg -q --fixed-strings "scripts/release_validate.sh --ci --require-clean" "$DOC"
rg -q --fixed-strings "scripts/cut_release_tag.sh --version vX.Y.Z --apply --commit-notes --push" "$DOC"
rg -q --fixed-strings "scripts/publish_release_tag.sh --version vX.Y.Z --apply" "$DOC"
rg -q --fixed-strings "RELEASE_VALIDATE_ALLOW_DIRTY=1 scripts/check_release_contracts.sh" "$DOC"
rg -q --fixed-strings "Do not use dirty-worktree override in CI or release cut/tag workflows." "$DOC"
rg -q --fixed-strings "scripts/release_validate.sh --ci --require-clean" "$DOC"

echo "release contracts doc checks passed"
