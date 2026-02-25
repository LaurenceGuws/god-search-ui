#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! rg -n --fixed-strings -- "$pattern" "$file" >/dev/null; then
    echo "missing ${label}: ${pattern}" >&2
    echo "  file: ${file}" >&2
    exit 1
  fi
}

# Default config template parity (init script + lua bootstrap fallback)
require_pattern scripts/init_lua_config.sh 'surface_mode = "auto"' "init default surface mode"
require_pattern src/config/lua_config.zig 'surface_mode = "auto"' "lua bootstrap default surface mode"

for key in \
  'anchor = "center"' \
  'anchor = "top_right"' \
  'monitor_policy = "primary"' \
  'monitor_name = "DP-1"' \
  'width_percent = 48' \
  'height_percent = 56' \
  'width_percent = 26' \
  'height_percent = 46'
do
  require_pattern scripts/init_lua_config.sh "$key" "init template key"
  require_pattern src/config/lua_config.zig "$key" "lua bootstrap template key"
done

# Operator docs parity for diagnostics and smoke workflows.
require_pattern README.md 'god-search-ui --print-config' "README print-config command"
require_pattern README.md 'god-search-ui --print-outputs' "README print-outputs command"
require_pattern README.md 'scripts/placement_smoke.sh' "README placement smoke command"
require_pattern docs/operations/LUA_CONFIG.md 'god-search-ui --print-config' "LUA_CONFIG print-config command"
require_pattern docs/operations/LUA_CONFIG.md 'god-search-ui --print-outputs' "LUA_CONFIG print-outputs command"
require_pattern docs/operations/LUA_CONFIG.md 'scripts/placement_smoke.sh' "LUA_CONFIG smoke command"

echo "placement contract checks passed"
