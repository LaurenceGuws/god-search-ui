#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT="$(printf ':icondiag --json\n:q\n' | zig build run -- --ui)"
JSON_LINE="$(printf '%s\n' "$OUT" | grep -E '"apps_total":' | tail -n 1 || true)"
if [[ -n "$JSON_LINE" ]]; then
  JSON_LINE="${JSON_LINE#*\{}"
  JSON_LINE="{${JSON_LINE}"
fi

if [[ -z "$JSON_LINE" ]]; then
  echo "icondiag json check failed: no JSON diagnostics line found"
  exit 1
fi

for key in \
  '"apps_total"' \
  '"with_icon_metadata"' \
  '"with_command_token_icon"' \
  '"likely_glyph_fallback"' \
  '"metadata_coverage_pct"' \
  '"glyph_fallback_pct"' \
  '"glyph_fallback_samples"'
do
  if ! printf '%s\n' "$JSON_LINE" | grep -q "$key"; then
    echo "icondiag json check failed: missing key $key"
    exit 1
  fi
done

echo "icondiag json schema checks passed"
