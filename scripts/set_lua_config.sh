#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage:
  scripts/set_lua_config.sh <key> <value>

Keys:
  surface_mode                  auto | toplevel | layer-shell
  launcher.anchor               center | top_left | top_center | top_right | bottom_left | bottom_center | bottom_right
  notifications.anchor          center | top_left | top_center | top_right | bottom_left | bottom_center | bottom_right
  launcher.monitor_name         output name (e.g. DP-1)
  notifications.monitor_name    output name (e.g. HDMI-A-1)
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
  *)
    echo "unknown key: $KEY" >&2
    usage
    exit 1
    ;;
esac

echo "updated ${KEY} in ${CFG}"
