#!/usr/bin/env bash
set -euo pipefail

BIN="${BIN:-./zig-out/bin/god_search_ui}"
EXPECT_OUTPUT="${1:-}"

echo "[placement-smoke] outputs:"
OUTS="$("${BIN}" --print-outputs)"
echo "${OUTS}"

echo "[placement-smoke] resolved config:"
CFG="$("${BIN}" --print-config)"
echo "${CFG}"

if [[ -n "${EXPECT_OUTPUT}" ]]; then
  if ! grep -F "\"name\":\"${EXPECT_OUTPUT}\"" <<<"${OUTS}" >/dev/null; then
    echo "[placement-smoke] expected output not found: ${EXPECT_OUTPUT}" >&2
    exit 2
  fi
  echo "[placement-smoke] confirmed output present: ${EXPECT_OUTPUT}"
fi

echo "[placement-smoke] ok"
