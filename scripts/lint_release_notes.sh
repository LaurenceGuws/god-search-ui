#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

NOTES_FILE="${1:-docs/release-notes-v0.1.1.md}"

if [[ ! -f "$NOTES_FILE" ]]; then
  echo "error: file not found: $NOTES_FILE" >&2
  exit 1
fi

fail=0

# Placeholder bullets and unresolved pass/fail markers.
if rg -n '^- $' "$NOTES_FILE" >/dev/null; then
  echo "error: blank bullet placeholder found in $NOTES_FILE" >&2
  fail=1
fi

if rg -n 'pass/fail' "$NOTES_FILE" >/dev/null; then
  echo "error: unresolved pass/fail marker found in $NOTES_FILE" >&2
  fail=1
fi

if rg -n '^## Known Issues$' -A2 "$NOTES_FILE" | rg -q '^- $'; then
  echo "error: known issues section still has blank placeholder" >&2
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  exit 1
fi

echo "release notes lint passed: $NOTES_FILE"
