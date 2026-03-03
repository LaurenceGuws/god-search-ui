const std = @import("std");

pub fn resolvePath(allocator: std.mem.Allocator) ![]u8 {
    const env = std.process.getEnvVarOwned(allocator, "GOD_SEARCH_CONFIG_LUA") catch null;
    if (env) |value| {
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        if (trimmed.len == 0) {
            allocator.free(value);
        } else {
            return value;
        }
    }

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return std.fmt.allocPrint(allocator, "{s}/.config/god-search-ui/config.lua", .{home});
}

pub fn ensureDefaultConfig(allocator: std.mem.Allocator) !bool {
    const path = try resolvePath(allocator);
    defer allocator.free(path);
    return ensureDefaultConfigAtPath(path);
}

pub fn ensureDefaultConfigAtPath(path: []const u8) !bool {
    std.fs.cwd().access(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            if (std.fs.path.dirname(path)) |dir_path| {
                try std.fs.cwd().makePath(dir_path);
            }
            var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
            defer file.close();
            try file.writeAll(template);
            return true;
        },
        else => return err,
    };
    return false;
}

pub const template =
    \\return {
    \\  surface_mode = "auto", -- auto | toplevel | layer-shell
    \\  placement = {
    \\    launcher = {
    \\      anchor = "center",
    \\      monitor_policy = "primary", -- primary | focused
    \\      -- monitor_name = "DP-1",   -- optional: sets policy to by_name
    \\      margins = { top = 12, right = 12, bottom = 12, left = 12 },
    \\      width_percent = 48,
    \\      height_percent = 56,
    \\      min_width_percent = 32,
    \\      min_height_percent = 36,
    \\      min_width_px = 560,
    \\      min_height_px = 360,
    \\      max_width_px = 1100,
    \\      max_height_px = 760,
    \\    },
    \\    notifications = {
    \\      anchor = "top_right",
    \\      monitor_policy = "primary", -- primary | focused
    \\      -- monitor_name = "DP-1",   -- optional: sets policy to by_name
    \\      margins = { top = 24, right = 24, bottom = 24, left = 24 },
    \\      width_percent = 26,
    \\      height_percent = 46,
    \\      min_width_px = 300,
    \\      min_height_px = 280,
    \\      max_width_px = 460,
    \\      max_height_px = 620,
    \\    },
    \\  },
    \\  notifications = {
    \\    actions = {
    \\      show_close_button = true,
    \\      show_dbus_actions = true,
    \\    },
    \\  },
    \\  ui = {
    \\    show_nerd_stats = true,
    \\  },
    \\}
    \\
;
