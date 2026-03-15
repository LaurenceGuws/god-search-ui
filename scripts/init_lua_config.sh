#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-${HOME}/.config/wayspot/config.lua}"
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
  notifications = {
    actions = {
      show_close_button = true,
      show_dbus_actions = true,
    },
  },
  ui = {
    show_nerd_stats = true,
  },
  tools = {
    package_manager = "yay", -- yay | pacman
    terminal = "kitty", -- kitty | zide-terminal | alacritty | footclient | foot | wezterm | gnome-terminal | konsole | xfce4-terminal | tilix | xterm
    grep_include_hidden = false, -- true includes hidden files/dirs for & route
    clipboard_tool = "wl-copy", -- wl-copy | xclip
    editor_tool = "xdg-open", -- nvim | vim | vi | helix | hx | kak | nano | code | codium | code-insiders | subl | xdg-open
  },
}
EOF

echo "wrote ${TARGET}"
