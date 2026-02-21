#!/usr/bin/env bash
set -euo pipefail

if [[ -d "/usr/share/icons" ]]; then
  if find /usr/share/icons -maxdepth 2 -type d \( -name hicolor -o -name Adwaita -o -name Papirus \) | grep -q .; then
    echo "icon theme environment looks available"
    exit 0
  fi
fi

echo "warning: no common icon theme directories detected under /usr/share/icons"
echo "app icon lookup may fall back to glyph icons"
exit 0
