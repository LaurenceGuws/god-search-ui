#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BIN="${BIN:-./zig-out/bin/god_search_ui}"
if [[ ! -x "$BIN" ]]; then
  echo "missing binary: $BIN" >&2
  echo "build first, e.g.:" >&2
  echo "  zig build -Doptimize=ReleaseFast -Denable_gtk=true -Denable_layer_shell=true -Denable_lua_config=true" >&2
  exit 1
fi

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT
CFG="$TMP_HOME/.config/god-search-ui/config.lua"
mkdir -p "$(dirname "$CFG")"

cat >"$CFG" <<'EOF'
return {
  surface_mode = "toplevel",
  placement = {
    launcher = {
      anchor = "bottom_left",
    },
  },
}
EOF

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if ! grep -F "$needle" <<<"$haystack" >/dev/null; then
    echo "failed: $label" >&2
    echo "missing: $needle" >&2
    exit 1
  fi
}

base_out="$(HOME="$TMP_HOME" "$BIN" --print-config)"
assert_contains "$base_out" '"surface_mode": "toplevel"' "lua baseline surface mode"
assert_contains "$base_out" '"anchor": "bottom_left"' "lua baseline launcher anchor"

env_out="$(HOME="$TMP_HOME" GOD_SEARCH_SURFACE_MODE=layer-shell GOD_SEARCH_LAUNCHER_ANCHOR=top_center "$BIN" --print-config)"
assert_contains "$env_out" '"surface_mode": "layer_shell"' "env overrides lua surface mode"
assert_contains "$env_out" '"anchor": "top_center"' "env overrides lua launcher anchor"

cli_out="$(HOME="$TMP_HOME" GOD_SEARCH_SURFACE_MODE=layer-shell "$BIN" --print-config --surface-mode auto)"
assert_contains "$cli_out" '"surface_mode": "auto"' "cli overrides env surface mode"

echo "placement precedence checks passed"
