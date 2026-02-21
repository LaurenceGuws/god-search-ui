#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-UNRELEASED}"
OUT="${2:-docs/release-notes-${VERSION}.md}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: run inside git repository" >&2
  exit 1
fi

if [[ ! -f docs/RELEASE_NOTES_TEMPLATE.md ]]; then
  echo "error: docs/RELEASE_NOTES_TEMPLATE.md not found" >&2
  exit 1
fi

DATE_UTC="$(date -u +%F)"
COMMITS="$(git log --oneline -20)"

cp docs/RELEASE_NOTES_TEMPLATE.md "$OUT"

# Fill top metadata fields in-place.
sed -i "s/^\- Version:.*/- Version: ${VERSION}/" "$OUT"
sed -i "s/^\- Date:.*/- Date: ${DATE_UTC}/" "$OUT"

{
  echo
  echo "## Draft Commit Digest"
  echo
  echo '```text'
  echo "$COMMITS"
  echo '```'
} >> "$OUT"

echo "generated: $OUT"
