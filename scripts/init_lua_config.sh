#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-${HOME}/.config/god-search-ui/config.lua}"
DIR="$(dirname "${TARGET}")"

mkdir -p "${DIR}"

cat >"${TARGET}" <<'EOF'
return {
  surface_mode = "layer-shell", -- toplevel | layer-shell
  placement = {
    launcher = {
      anchor = "center",
      monitor_policy = "primary", -- primary | focused
      -- monitor_name = "DP-1",   -- optional: sets policy to by_name
      margins = { top = 12, right = 12, bottom = 12, left = 12 },
      width_percent = 48,
      height_percent = 56,
      min_width_percent = 32,
      min_height_percent = 36,
      min_width_px = 560,
      min_height_px = 360,
      max_width_px = 1100,
      max_height_px = 760,
    },
    notifications = {
      anchor = "top_right",
      monitor_policy = "primary", -- primary | focused
      -- monitor_name = "DP-1",   -- optional: sets policy to by_name
      margins = { top = 24, right = 24, bottom = 24, left = 24 },
      width_percent = 26,
      height_percent = 46,
      min_width_px = 300,
      min_height_px = 280,
      max_width_px = 460,
      max_height_px = 620,
    },
  },
}
EOF

echo "wrote ${TARGET}"
