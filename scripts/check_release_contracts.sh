#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

scripts/check_release_docs_contracts.sh
scripts/check_release_validate_ci.sh

echo "release contract checks passed"
