#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MATRIX="docs/RELEASE_SCRIPT_MATRIX.md"
test -f "$MATRIX"

# Ensure all scripts referenced in the matrix exist and are executable.
scripts=(
  "scripts/release_smoke.sh"
  "scripts/release_validate.sh"
  "scripts/check_clean_worktree.sh"
  "scripts/check_release_validate_ci.sh"
  "scripts/check_release_validate_contract.sh"
  "scripts/gen_release_notes.sh"
  "scripts/cut_release_tag.sh"
  "scripts/publish_release_tag.sh"
  "scripts/arch_package_smoke.sh"
  "scripts/check_release_helpers.sh"
  "scripts/check_release_docs_contracts.sh"
  "scripts/check_release_contracts.sh"
  "scripts/check_release_contracts_contract.sh"
  "scripts/check_release_contracts_doc.sh"
  "scripts/check_release_smoke_contract.sh"
  "scripts/check_apps_cache_format.sh"
  "scripts/check_icon_theme_env.sh"
  "scripts/check_icondiag_json.sh"
  "scripts/check_icondiag_threshold.sh"
)

for s in "${scripts[@]}"; do
  rg -q --fixed-strings "$s" "$MATRIX"
  test -x "$s"
done

# Ensure recommended order section exists and includes tag/publish flow.
rg -q --fixed-strings "## Recommended Order" "$MATRIX"
rg -q --fixed-strings "scripts/release_smoke.sh --ci" "$MATRIX"
rg -q --fixed-strings "scripts/release_validate.sh --ci" "$MATRIX"
rg -q --fixed-strings "scripts/cut_release_tag.sh --version vX.Y.Z --apply --commit-notes --push" "$MATRIX"
rg -q --fixed-strings -- "--regen-notes" "$MATRIX"
rg -q --fixed-strings "scripts/publish_release_tag.sh --version vX.Y.Z --apply" "$MATRIX"

# Ensure related docs references exist.
rg -q --fixed-strings "## Related Docs" "$MATRIX"
rg -q --fixed-strings "docs/RELEASE_SMOKE_MODES.md" "$MATRIX"
rg -q --fixed-strings "docs/RELEASE_VALIDATE_MODES.md" "$MATRIX"
rg -q --fixed-strings "docs/ICON_DIAGNOSTICS.md" "$MATRIX"
rg -q --fixed-strings "docs/RELEASE_CONTRACTS.md" "$MATRIX"

echo "release matrix checks passed"
