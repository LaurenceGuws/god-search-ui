const std = @import("std");
const config = @import("mod.zig");
const default_lua = @import("default_lua.zig");
const SurfaceMode = @import("../ui/surfaces/mod.zig").SurfaceMode;
const placement = @import("../ui/placement/mod.zig");
const wm_adapter = @import("../wm/adapter.zig");

const c = @cImport({
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
});

const log = std.log.scoped(.config);

pub fn load(allocator: std.mem.Allocator) config.Settings {
    const path = default_lua.resolvePath(allocator) catch return .{};
    defer allocator.free(path);

    std.fs.cwd().access(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            _ = default_lua.ensureDefaultConfigAtPath(path) catch |write_err| {
                log.warn("lua config missing and default bootstrap failed ({s}): {s}", .{ path, @errorName(write_err) });
                return .{};
            };
            log.info("created default lua config: {s}", .{path});
        },
        else => return .{},
    };

    const path_z = allocator.dupeZ(u8, path) catch return .{};
    defer allocator.free(path_z);

    const lua = c.luaL_newstate() orelse return .{};
    defer c.lua_close(lua);
    c.luaL_openlibs(lua);

    const filename: [*c]const u8 = @ptrCast(path_z.ptr);
    if (c.luaL_loadfilex(lua, filename, null) != c.LUA_OK or
        c.lua_pcallk(lua, 0, c.LUA_MULTRET, 0, @as(c.lua_KContext, 0), null) != c.LUA_OK)
    {
        if (readLuaString(lua, -1)) |msg| {
            log.warn("lua config load failed ({s}): {s}", .{ path, msg });
        }
        return .{};
    }

    var settings = config.Settings{};
    errdefer settings.deinit(allocator);
    if (c.lua_gettop(lua) > 0 and c.lua_istable(lua, -1)) {
        settings = parseSettingsFromTop(lua, allocator, settings);
        settings.applyPlacementOverrides();
        c.lua_settop(lua, 0);
        return settings;
    }

    _ = c.lua_getglobal(lua, "god_search_ui");
    if (c.lua_istable(lua, -1)) {
        settings = parseSettingsFromTop(lua, allocator, settings);
    }
    settings.applyPlacementOverrides();
    c.lua_settop(lua, 0);
    return settings;
}

fn parseSettingsFromTop(lua: *c.lua_State, allocator: std.mem.Allocator, initial: config.Settings) config.Settings {
    var out = initial;

    _ = c.lua_getfield(lua, -1, "surface_mode");
    if (c.lua_type(lua, -1) == c.LUA_TSTRING) {
        if (readLuaString(lua, -1)) |raw| {
            if (SurfaceMode.parse(raw)) |mode| {
                out.surface_mode = mode;
            } else {
                log.warn("ignoring invalid lua surface_mode: {s}", .{raw});
            }
        }
    }
    c.lua_pop(lua, 1);

    _ = c.lua_getfield(lua, -1, "placement");
    if (c.lua_istable(lua, -1)) {
        out.placement_policy = parsePlacementTable(lua, allocator, -1, out.placement_policy, &out.launcher_monitor_name, &out.notifications_monitor_name);
    }
    c.lua_pop(lua, 1);

    _ = c.lua_getfield(lua, -1, "notifications");
    if (c.lua_istable(lua, -1)) {
        out.notification_actions = parseNotificationsTable(lua, -1, out.notification_actions);
    }
    c.lua_pop(lua, 1);

    _ = c.lua_getfield(lua, -1, "ui");
    if (c.lua_istable(lua, -1)) {
        out.ui = parseUiTable(lua, -1, out.ui);
    }
    c.lua_pop(lua, 1);

    _ = c.lua_getfield(lua, -1, "tools");
    if (c.lua_istable(lua, -1)) {
        out.tools = parseToolsTable(lua, -1, out.tools);
    }
    c.lua_pop(lua, 1);

    return out;
}

fn parseNotificationsTable(
    lua: *c.lua_State,
    idx: c_int,
    initial: config.Settings.NotificationActionsPolicy,
) config.Settings.NotificationActionsPolicy {
    var out = initial;
    _ = c.lua_getfield(lua, idx, "actions");
    if (c.lua_istable(lua, -1)) {
        maybeBoolField(lua, -1, "show_close_button", &out.show_close_button);
        maybeBoolField(lua, -1, "show_dbus_actions", &out.show_dbus_actions);
    }
    c.lua_pop(lua, 1);
    return out;
}

fn parseUiTable(
    lua: *c.lua_State,
    idx: c_int,
    initial: config.Settings.UiPolicy,
) config.Settings.UiPolicy {
    var out = initial;
    maybeBoolField(lua, idx, "show_nerd_stats", &out.show_nerd_stats);
    return out;
}

fn parseToolsTable(
    lua: *c.lua_State,
    idx: c_int,
    initial: config.Settings.ToolsPolicy,
) config.Settings.ToolsPolicy {
    var out = initial;
    _ = c.lua_getfield(lua, idx, "package_manager");
    if (c.lua_type(lua, -1) == c.LUA_TSTRING) {
        if (readLuaString(lua, -1)) |raw| {
            if (parsePackageManager(raw)) |value| {
                out.package_manager = value;
            } else {
                log.warn("ignoring invalid lua tools.package_manager: {s}", .{raw});
            }
        }
    }
    c.lua_pop(lua, 1);

    _ = c.lua_getfield(lua, idx, "terminal");
    if (c.lua_type(lua, -1) == c.LUA_TSTRING) {
        if (readLuaString(lua, -1)) |raw| {
            if (parseTerminalTool(raw)) |value| {
                out.terminal = value;
            } else {
                log.warn("ignoring invalid lua tools.terminal: {s}", .{raw});
            }
        }
    }
    c.lua_pop(lua, 1);

    maybeBoolField(lua, idx, "grep_include_hidden", &out.grep_include_hidden);

    _ = c.lua_getfield(lua, idx, "clipboard_tool");
    if (c.lua_type(lua, -1) == c.LUA_TSTRING) {
        if (readLuaString(lua, -1)) |raw| {
            if (parseClipboardTool(raw)) |value| {
                out.clipboard_tool = value;
            } else {
                log.warn("ignoring invalid lua tools.clipboard_tool: {s}", .{raw});
            }
        }
    }
    c.lua_pop(lua, 1);

    _ = c.lua_getfield(lua, idx, "editor_tool");
    if (c.lua_type(lua, -1) == c.LUA_TSTRING) {
        if (readLuaString(lua, -1)) |raw| {
            if (parseEditorTool(raw)) |value| {
                out.editor_tool = value;
            } else {
                log.warn("ignoring invalid lua tools.editor_tool: {s}", .{raw});
            }
        }
    }
    c.lua_pop(lua, 1);

    return out;
}

fn parsePlacementTable(
    lua: *c.lua_State,
    allocator: std.mem.Allocator,
    idx: c_int,
    initial: placement.RuntimePolicy,
    launcher_monitor_name: *?[]u8,
    notifications_monitor_name: *?[]u8,
) placement.RuntimePolicy {
    var out = initial;

    _ = c.lua_getfield(lua, idx, "launcher");
    if (c.lua_istable(lua, -1)) {
        out.launcher = parseLauncherPolicy(lua, allocator, -1, out.launcher, launcher_monitor_name);
    }
    c.lua_pop(lua, 1);

    _ = c.lua_getfield(lua, idx, "notifications");
    if (c.lua_istable(lua, -1)) {
        out.notifications = parseNotificationPolicy(lua, allocator, -1, out.notifications, notifications_monitor_name);
    }
    c.lua_pop(lua, 1);

    return out;
}

fn parseLauncherPolicy(
    lua: *c.lua_State,
    allocator: std.mem.Allocator,
    idx: c_int,
    initial: placement.LauncherPolicy,
    monitor_name_out: *?[]u8,
) placement.LauncherPolicy {
    var out = initial;
    parseWindowPolicy(lua, allocator, idx, &out.window, monitor_name_out);
    maybeIntField(lua, idx, "width_percent", &out.width_percent);
    maybeIntField(lua, idx, "height_percent", &out.height_percent);
    maybeIntField(lua, idx, "min_width_percent", &out.min_width_percent);
    maybeIntField(lua, idx, "min_height_percent", &out.min_height_percent);
    maybeIntField(lua, idx, "max_width_px", &out.max_width_px);
    maybeIntField(lua, idx, "max_height_px", &out.max_height_px);
    maybeIntField(lua, idx, "min_width_px", &out.min_width_px);
    maybeIntField(lua, idx, "min_height_px", &out.min_height_px);
    return out;
}

fn parseNotificationPolicy(
    lua: *c.lua_State,
    allocator: std.mem.Allocator,
    idx: c_int,
    initial: placement.NotificationPolicy,
    monitor_name_out: *?[]u8,
) placement.NotificationPolicy {
    var out = initial;
    parseWindowPolicy(lua, allocator, idx, &out.window, monitor_name_out);
    maybeIntField(lua, idx, "width_percent", &out.width_percent);
    maybeIntField(lua, idx, "height_percent", &out.height_percent);
    maybeIntField(lua, idx, "min_width_px", &out.min_width_px);
    maybeIntField(lua, idx, "min_height_px", &out.min_height_px);
    maybeIntField(lua, idx, "max_width_px", &out.max_width_px);
    maybeIntField(lua, idx, "max_height_px", &out.max_height_px);
    return out;
}

fn parseWindowPolicy(
    lua: *c.lua_State,
    allocator: std.mem.Allocator,
    idx: c_int,
    out: *placement.WindowPolicy,
    monitor_name_out: *?[]u8,
) void {
    _ = c.lua_getfield(lua, idx, "anchor");
    if (c.lua_type(lua, -1) == c.LUA_TSTRING) {
        if (readLuaString(lua, -1)) |raw| {
            if (parseAnchor(raw)) |anchor| {
                out.anchor = anchor;
            } else {
                log.warn("ignoring invalid lua anchor: {s}", .{raw});
            }
        }
    }
    c.lua_pop(lua, 1);

    _ = c.lua_getfield(lua, idx, "monitor_policy");
    if (c.lua_type(lua, -1) == c.LUA_TSTRING) {
        if (readLuaString(lua, -1)) |raw| {
            if (parseMonitorPolicy(raw)) |policy| {
                out.monitor.policy = policy;
            } else {
                log.warn("ignoring invalid lua monitor_policy: {s}", .{raw});
            }
        }
    }
    c.lua_pop(lua, 1);

    _ = c.lua_getfield(lua, idx, "monitor_name");
    if (c.lua_type(lua, -1) == c.LUA_TSTRING) {
        if (readLuaString(lua, -1)) |raw| {
            const trimmed = std.mem.trim(u8, raw, " \t\r\n");
            if (trimmed.len > 0) {
                if (monitor_name_out.*) |old| allocator.free(old);
                monitor_name_out.* = allocator.dupe(u8, trimmed) catch null;
            }
        }
    }
    c.lua_pop(lua, 1);

    _ = c.lua_getfield(lua, idx, "margins");
    if (c.lua_istable(lua, -1)) {
        maybeIntField(lua, -1, "left", &out.margins.left);
        maybeIntField(lua, -1, "right", &out.margins.right);
        maybeIntField(lua, -1, "top", &out.margins.top);
        maybeIntField(lua, -1, "bottom", &out.margins.bottom);
    }
    c.lua_pop(lua, 1);
}

fn maybeIntField(lua: *c.lua_State, idx: c_int, field: [*:0]const u8, out: *i32) void {
    _ = c.lua_getfield(lua, idx, field);
    defer c.lua_settop(lua, -2);
    if (c.lua_type(lua, -1) != c.LUA_TNUMBER) return;
    const v = c.lua_tointegerx(lua, -1, null);
    const int_v: i64 = @intCast(v);
    out.* = std.math.cast(i32, int_v) orelse out.*;
}

fn maybeBoolField(lua: *c.lua_State, idx: c_int, field: [*:0]const u8, out: *bool) void {
    _ = c.lua_getfield(lua, idx, field);
    defer c.lua_settop(lua, -2);
    if (c.lua_type(lua, -1) != c.LUA_TBOOLEAN) return;
    out.* = c.lua_toboolean(lua, -1) != 0;
}

fn parseAnchor(raw: []const u8) ?placement.Anchor {
    if (std.ascii.eqlIgnoreCase(raw, "center")) return .center;
    if (std.ascii.eqlIgnoreCase(raw, "top_left") or std.ascii.eqlIgnoreCase(raw, "top-left")) return .top_left;
    if (std.ascii.eqlIgnoreCase(raw, "top_center") or std.ascii.eqlIgnoreCase(raw, "top-center")) return .top_center;
    if (std.ascii.eqlIgnoreCase(raw, "top_right") or std.ascii.eqlIgnoreCase(raw, "top-right")) return .top_right;
    if (std.ascii.eqlIgnoreCase(raw, "bottom_left") or std.ascii.eqlIgnoreCase(raw, "bottom-left")) return .bottom_left;
    if (std.ascii.eqlIgnoreCase(raw, "bottom_center") or std.ascii.eqlIgnoreCase(raw, "bottom-center")) return .bottom_center;
    if (std.ascii.eqlIgnoreCase(raw, "bottom_right") or std.ascii.eqlIgnoreCase(raw, "bottom-right")) return .bottom_right;
    return null;
}

fn parseMonitorPolicy(raw: []const u8) ?wm_adapter.MonitorPolicy {
    if (std.ascii.eqlIgnoreCase(raw, "focused")) return .focused;
    if (std.ascii.eqlIgnoreCase(raw, "primary")) return .primary;
    return null;
}

fn parsePackageManager(raw: []const u8) ?config.PackageManager {
    if (std.ascii.eqlIgnoreCase(raw, "yay")) return .yay;
    if (std.ascii.eqlIgnoreCase(raw, "pacman")) return .pacman;
    return null;
}

fn parseTerminalTool(raw: []const u8) ?config.TerminalTool {
    if (std.ascii.eqlIgnoreCase(raw, "kitty")) return .kitty;
    if (std.ascii.eqlIgnoreCase(raw, "alacritty")) return .alacritty;
    if (std.ascii.eqlIgnoreCase(raw, "footclient")) return .footclient;
    if (std.ascii.eqlIgnoreCase(raw, "foot")) return .foot;
    if (std.ascii.eqlIgnoreCase(raw, "wezterm")) return .wezterm;
    if (std.ascii.eqlIgnoreCase(raw, "gnome-terminal") or std.ascii.eqlIgnoreCase(raw, "gnome_terminal")) return .gnome_terminal;
    if (std.ascii.eqlIgnoreCase(raw, "konsole")) return .konsole;
    if (std.ascii.eqlIgnoreCase(raw, "xfce4-terminal") or std.ascii.eqlIgnoreCase(raw, "xfce4_terminal")) return .xfce4_terminal;
    if (std.ascii.eqlIgnoreCase(raw, "tilix")) return .tilix;
    if (std.ascii.eqlIgnoreCase(raw, "xterm")) return .xterm;
    return null;
}

fn parseClipboardTool(raw: []const u8) ?config.ClipboardTool {
    if (std.ascii.eqlIgnoreCase(raw, "wl-copy") or std.ascii.eqlIgnoreCase(raw, "wl_copy")) return .wl_copy;
    if (std.ascii.eqlIgnoreCase(raw, "xclip")) return .xclip;
    return null;
}

fn parseEditorTool(raw: []const u8) ?config.EditorTool {
    if (std.ascii.eqlIgnoreCase(raw, "nvim")) return .nvim;
    if (std.ascii.eqlIgnoreCase(raw, "vim")) return .vim;
    if (std.ascii.eqlIgnoreCase(raw, "vi")) return .vi;
    if (std.ascii.eqlIgnoreCase(raw, "helix")) return .helix;
    if (std.ascii.eqlIgnoreCase(raw, "hx")) return .hx;
    if (std.ascii.eqlIgnoreCase(raw, "kak")) return .kak;
    if (std.ascii.eqlIgnoreCase(raw, "nano")) return .nano;
    if (std.ascii.eqlIgnoreCase(raw, "code")) return .code;
    if (std.ascii.eqlIgnoreCase(raw, "codium")) return .codium;
    if (std.ascii.eqlIgnoreCase(raw, "code-insiders") or std.ascii.eqlIgnoreCase(raw, "code_insiders")) return .code_insiders;
    if (std.ascii.eqlIgnoreCase(raw, "subl")) return .subl;
    if (std.ascii.eqlIgnoreCase(raw, "xdg-open") or std.ascii.eqlIgnoreCase(raw, "xdg_open")) return .xdg_open;
    return null;
}

fn readLuaString(lua: *c.lua_State, idx: c_int) ?[]const u8 {
    var len: usize = 0;
    const ptr = c.lua_tolstring(lua, idx, &len) orelse return null;
    return ptr[0..@intCast(len)];
}
