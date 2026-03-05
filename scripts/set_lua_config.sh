#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage:
  scripts/set_lua_config.sh <key> <value>

Keys:
  surface_mode                  toplevel | layer-shell
  launcher.anchor               center | top_left | top_center | top_right | bottom_left | bottom_center | bottom_right
  notifications.anchor          center | top_left | top_center | top_right | bottom_left | bottom_center | bottom_right
  launcher.monitor_name         output name (e.g. DP-1)
  notifications.monitor_name    output name (e.g. HDMI-A-1)
  tools.package_manager         yay | pacman
  tools.terminal                kitty | alacritty | footclient | foot | wezterm | gnome-terminal | konsole | xfce4-terminal | tilix | xterm
  tools.grep_include_hidden     true | false
  tools.clipboard_tool          wl-copy | xclip
  tools.editor_tool             nvim | vim | vi | helix | hx | kak | nano | code | codium | code-insiders | subl | xdg-open
  notifications.actions.show_close_button  true | false
  notifications.actions.show_dbus_actions  true | false
EOF
}

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

KEY="$1"
VALUE="$2"
CFG="${GOD_SEARCH_CONFIG_LUA:-$HOME/.config/god-search-ui/config.lua}"

if [[ ! -f "$CFG" ]]; then
  scripts/init_lua_config.sh "$CFG" >/dev/null
fi

escape_perl() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

V_ESC="$(escape_perl "$VALUE")"

require_bool() {
  if [[ "$VALUE" != "true" && "$VALUE" != "false" ]]; then
    echo "value for $KEY must be true or false" >&2
    exit 1
  fi
}

ensure_notifications_actions_block() {
  if rg -q '^[[:space:]]{2}notifications\s*=\s*\{' "$CFG"; then
    return
  fi
  perl -0777 -i -pe 's/\n\},?\s*$/\n  notifications = {\n    actions = {\n      show_close_button = true,\n      show_dbus_actions = true,\n    },\n  },\n}\n/s' "$CFG"
}

case "$KEY" in
  surface_mode)
    perl -0777 -i -pe "s/surface_mode\\s*=\\s*\"[^\"]*\"/surface_mode = \"${V_ESC}\"/g" "$CFG"
    ;;
  launcher.anchor)
    perl -0777 -i -pe "s/(launcher\\s*=\\s*\\{.*?\\n\\s*)anchor\\s*=\\s*\"[^\"]*\"/\${1}anchor = \"${V_ESC}\"/s" "$CFG"
    ;;
  notifications.anchor)
    perl -0777 -i -pe "s/(notifications\\s*=\\s*\\{.*?\\n\\s*)anchor\\s*=\\s*\"[^\"]*\"/\${1}anchor = \"${V_ESC}\"/s" "$CFG"
    ;;
  launcher.monitor_name)
    perl -0777 -i -pe "s/(launcher\\s*=\\s*\\{.*?\\n\\s*)(?:--\\s*)?monitor_name\\s*=\\s*\"[^\"]*\",[^\\n]*\\n/\${1}monitor_name = \"${V_ESC}\",\\n/s" "$CFG"
    ;;
  notifications.monitor_name)
    perl -0777 -i -pe "s/(notifications\\s*=\\s*\\{.*?\\n\\s*)(?:--\\s*)?monitor_name\\s*=\\s*\"[^\"]*\",[^\\n]*\\n/\${1}monitor_name = \"${V_ESC}\",\\n/s" "$CFG"
    ;;
  tools.package_manager)
    if ! [[ "$VALUE" =~ ^(yay|pacman)$ ]]; then
      echo "value for $KEY must be yay or pacman" >&2
      exit 1
    fi
    perl -0777 -i -pe "s/(tools\\s*=\\s*\\{.*?\\n\\s*)package_manager\\s*=\\s*\"[^\"]*\"/\${1}package_manager = \"${V_ESC}\"/s" "$CFG"
    ;;
  tools.terminal)
    if ! [[ "$VALUE" =~ ^(kitty|alacritty|footclient|foot|wezterm|gnome-terminal|konsole|xfce4-terminal|tilix|xterm)$ ]]; then
      echo "value for $KEY is not a supported terminal" >&2
      exit 1
    fi
    perl -0777 -i -pe "s/(tools\\s*=\\s*\\{.*?\\n\\s*)terminal\\s*=\\s*\"[^\"]*\"/\${1}terminal = \"${V_ESC}\"/s" "$CFG"
    ;;
  tools.grep_include_hidden)
    require_bool
    perl -0777 -i -pe "s/(tools\\s*=\\s*\\{.*?\\n\\s*)grep_include_hidden\\s*=\\s*(?:true|false)/\${1}grep_include_hidden = ${V_ESC}/s" "$CFG"
    ;;
  tools.clipboard_tool)
    if ! [[ "$VALUE" =~ ^(wl-copy|xclip)$ ]]; then
      echo "value for $KEY must be wl-copy or xclip" >&2
      exit 1
    fi
    perl -0777 -i -pe "s/(tools\\s*=\\s*\\{.*?\\n\\s*)clipboard_tool\\s*=\\s*\"[^\"]*\"/\${1}clipboard_tool = \"${V_ESC}\"/s" "$CFG"
    ;;
  tools.editor_tool)
    if ! [[ "$VALUE" =~ ^(nvim|vim|vi|helix|hx|kak|nano|code|codium|code-insiders|subl|xdg-open)$ ]]; then
      echo "value for $KEY is not a supported editor tool" >&2
      exit 1
    fi
    perl -0777 -i -pe "s/(tools\\s*=\\s*\\{.*?\\n\\s*)editor_tool\\s*=\\s*\"[^\"]*\"/\${1}editor_tool = \"${V_ESC}\"/s" "$CFG"
    ;;
  notifications.actions.show_close_button)
    require_bool
    ensure_notifications_actions_block
    perl -0777 -i -pe "s/(actions\\s*=\\s*\\{.*?\\n\\s*)show_close_button\\s*=\\s*(?:true|false)/\${1}show_close_button = ${V_ESC}/s" "$CFG"
    rg -q "show_close_button = ${VALUE}" "$CFG" || { echo "failed to update notifications.actions.show_close_button" >&2; exit 1; }
    ;;
  notifications.actions.show_dbus_actions)
    require_bool
    ensure_notifications_actions_block
    perl -0777 -i -pe "s/(actions\\s*=\\s*\\{.*?\\n\\s*)show_dbus_actions\\s*=\\s*(?:true|false)/\${1}show_dbus_actions = ${V_ESC}/s" "$CFG"
    rg -q "show_dbus_actions = ${VALUE}" "$CFG" || { echo "failed to update notifications.actions.show_dbus_actions" >&2; exit 1; }
    ;;
  *)
    echo "unknown key: $KEY" >&2
    usage
    exit 1
    ;;
esac

echo "updated ${KEY} in ${CFG}"
