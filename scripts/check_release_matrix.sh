#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MATRIX="docs/RELEASE_SCRIPT_MATRIX.md"
test -f "$MATRIX"

# Ensure all scripts referenced in the matrix exist and are executable.
scripts=(
  "scripts/release_smoke.sh"
  "scripts/gen_release_notes.sh"
  "scripts/cut_release_tag.sh"
  "scripts/publish_release_tag.sh"
  "scripts/arch_package_smoke.sh"
  "scripts/check_release_helpers.sh"
)

for s in "${scripts[@]}"; do
  rg -q --fixed-strings "$s" "$MATRIX"
  test -x "$s"
done

# Ensure recommended order section exists and includes tag/publish flow.
rg -q --fixed-strings "## Recommended Order" "$MATRIX"
rg -q --fixed-strings "scripts/cut_release_tag.sh --version vX.Y.Z --apply --commit-notes --reuse-notes" "$MATRIX"
rg -q --fixed-strings "scripts/publish_release_tag.sh --version vX.Y.Z --apply" "$MATRIX"

echo "release matrix checks passed"
