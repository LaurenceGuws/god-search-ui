#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ok_cfg="$TMP_DIR/ok.lua"
bad_enum_cfg="$TMP_DIR/bad_enum.lua"
bad_type_cfg="$TMP_DIR/bad_type.lua"
bad_key_cfg="$TMP_DIR/bad_key.lua"
bad_notifications_type_cfg="$TMP_DIR/bad_notifications_type.lua"

scripts/init_lua_config.sh "$ok_cfg" >/dev/null
scripts/validate_lua_config.sh "$ok_cfg" >/dev/null

cat >"$bad_enum_cfg" <<'EOF'
return {
  surface_mode = "floating",
}
EOF
if scripts/validate_lua_config.sh "$bad_enum_cfg" >/dev/null 2>&1; then
  echo "expected enum validation failure but got success" >&2
  exit 1
fi

cat >"$bad_type_cfg" <<'EOF'
return {
  placement = {
    launcher = {
      margins = { top = "nope" },
    },
  },
}
EOF
if scripts/validate_lua_config.sh "$bad_type_cfg" >/dev/null 2>&1; then
  echo "expected type validation failure but got success" >&2
  exit 1
fi

cat >"$bad_key_cfg" <<'EOF'
return {
  placement = {
    launcher = {
      random_key = true,
    },
  },
}
EOF
if scripts/validate_lua_config.sh "$bad_key_cfg" >/dev/null 2>&1; then
  echo "expected unknown-key validation failure but got success" >&2
  exit 1
fi

cat >"$bad_notifications_type_cfg" <<'EOF'
return {
  notifications = {
    actions = {
      show_close_button = "yes",
    },
  },
}
EOF
if scripts/validate_lua_config.sh "$bad_notifications_type_cfg" >/dev/null 2>&1; then
  echo "expected notifications boolean type validation failure but got success" >&2
  exit 1
fi

echo "lua config validator checks passed"
