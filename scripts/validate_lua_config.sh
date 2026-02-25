#!/usr/bin/env bash
set -euo pipefail

CFG="${1:-${GOD_SEARCH_CONFIG_LUA:-$HOME/.config/god-search-ui/config.lua}}"

if ! command -v lua >/dev/null 2>&1; then
  echo "lua interpreter not found in PATH" >&2
  exit 2
fi

if [[ ! -f "$CFG" ]]; then
  echo "config file not found: $CFG" >&2
  exit 1
fi

lua - "$CFG" <<'LUA'
local cfg_path = arg[1]
local ok, conf = pcall(dofile, cfg_path)
if not ok then
  io.stderr:write("invalid lua config (parse/load error): " .. tostring(conf) .. "\n")
  os.exit(1)
end

local errors = {}
local function err(msg)
  table.insert(errors, msg)
end

local function expect_table(path, v)
  if type(v) ~= "table" then
    err(path .. " must be a table")
    return false
  end
  return true
end

local function check_unknown(path, t, allowed)
  for k, _ in pairs(t) do
    if not allowed[k] then
      err(path .. "." .. tostring(k) .. " is not allowed")
    end
  end
end

local function check_enum(path, v, allowed)
  if v == nil then return end
  if type(v) ~= "string" then
    err(path .. " must be a string")
    return
  end
  if not allowed[v] then
    err(path .. " has invalid value: " .. v)
  end
end

local function check_int(path, v)
  if v == nil then return end
  if type(v) ~= "number" or math.floor(v) ~= v then
    err(path .. " must be an integer number")
  end
end

if not expect_table("root", conf) then
  for _, e in ipairs(errors) do io.stderr:write(e .. "\n") end
  os.exit(1)
end

check_unknown("root", conf, {
  surface_mode = true,
  placement = true,
})

check_enum("surface_mode", conf.surface_mode, {
  ["auto"] = true,
  ["toplevel"] = true,
  ["layer-shell"] = true,
})

if conf.placement ~= nil then
  if expect_table("placement", conf.placement) then
    check_unknown("placement", conf.placement, {
      launcher = true,
      notifications = true,
    })
  end
end

local function validate_window_policy(path, t, has_launcher_sizes)
  if not expect_table(path, t) then return end
  local allowed = {
    anchor = true,
    monitor_policy = true,
    monitor_name = true,
    margins = true,
    width_percent = true,
    height_percent = true,
    min_width_px = true,
    min_height_px = true,
    max_width_px = true,
    max_height_px = true,
  }
  if has_launcher_sizes then
    allowed.min_width_percent = true
    allowed.min_height_percent = true
  end
  check_unknown(path, t, allowed)

  check_enum(path .. ".anchor", t.anchor, {
    ["center"] = true,
    ["top_left"] = true,
    ["top_center"] = true,
    ["top_right"] = true,
    ["bottom_left"] = true,
    ["bottom_center"] = true,
    ["bottom_right"] = true,
  })
  check_enum(path .. ".monitor_policy", t.monitor_policy, {
    ["primary"] = true,
    ["focused"] = true,
  })

  if t.monitor_name ~= nil and type(t.monitor_name) ~= "string" then
    err(path .. ".monitor_name must be a string")
  end

  if t.margins ~= nil then
    if expect_table(path .. ".margins", t.margins) then
      check_unknown(path .. ".margins", t.margins, {
        top = true,
        right = true,
        bottom = true,
        left = true,
      })
      check_int(path .. ".margins.top", t.margins.top)
      check_int(path .. ".margins.right", t.margins.right)
      check_int(path .. ".margins.bottom", t.margins.bottom)
      check_int(path .. ".margins.left", t.margins.left)
    end
  end

  check_int(path .. ".width_percent", t.width_percent)
  check_int(path .. ".height_percent", t.height_percent)
  check_int(path .. ".min_width_px", t.min_width_px)
  check_int(path .. ".min_height_px", t.min_height_px)
  check_int(path .. ".max_width_px", t.max_width_px)
  check_int(path .. ".max_height_px", t.max_height_px)
  if has_launcher_sizes then
    check_int(path .. ".min_width_percent", t.min_width_percent)
    check_int(path .. ".min_height_percent", t.min_height_percent)
  end
end

if conf.placement and type(conf.placement) == "table" then
  if conf.placement.launcher ~= nil then
    validate_window_policy("placement.launcher", conf.placement.launcher, true)
  end
  if conf.placement.notifications ~= nil then
    validate_window_policy("placement.notifications", conf.placement.notifications, false)
  end
end

if #errors > 0 then
  for _, e in ipairs(errors) do io.stderr:write(e .. "\n") end
  os.exit(1)
end

print("lua config schema validation passed")
LUA
