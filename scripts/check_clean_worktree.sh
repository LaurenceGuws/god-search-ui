#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "clean worktree check failed: working tree has uncommitted changes"
  git status --short
  exit 1
fi

echo "clean worktree check passed"
