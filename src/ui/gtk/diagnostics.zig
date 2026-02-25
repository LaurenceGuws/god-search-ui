const std = @import("std");
const gtk_types = @import("types.zig");
const gdk_adapter = @import("gdk_adapter.zig");
const shell_mod = @import("../../shell/mod.zig");

const c = gtk_types.c;

pub const Diagnostics = struct {
    pub fn printOutputs(allocator: std.mem.Allocator) !void {
        var stdout_buffer: [2048]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const out = &stdout_writer.interface;

        c.gtk_init();
        const display = c.gdk_display_get_default();
        if (display == null) {
            try out.print("no display\n", .{});
            try out.flush();
            return;
        }

        var adapter_ctx = gdk_adapter.GdkAdapter{ .display = display.? };
        const adapter = adapter_ctx.adapter();
        const outputs = try adapter.listOutputs(allocator);
        defer adapter.freeOutputs(allocator, outputs);

        if (outputs.len == 0) {
            try out.print("[]\n", .{});
            try out.flush();
            return;
        }

        try out.print("[\n", .{});
        for (outputs, 0..) |entry, idx| {
            const comma = if (idx + 1 < outputs.len) "," else "";
            try out.print(
                "  {{\"name\":\"{s}\",\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d},\"scale_milli\":{d}}}{s}\n",
                .{ entry.name, entry.x, entry.y, entry.width, entry.height, entry.scale_milli, comma },
            );
        }
        try out.print("]\n", .{});
        try out.flush();
    }

    pub fn printShellHealth(allocator: std.mem.Allocator) !void {
        var stdout_buffer: [2048]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const out = &stdout_writer.interface;

        const entries = [_]shell_mod.module.ModuleHealthEntry{
            .{ .name = "launcher", .health = .{ .status = .unknown, .detail = "diagnostic snapshot (offline)" } },
            .{ .name = "notifications", .health = .{ .status = .unknown, .detail = "diagnostic snapshot (offline)" } },
        };

        for (entries) |entry| {
            const line = try shell_mod.health.formatEntry(allocator, entry);
            defer allocator.free(line);
            try out.print("{s}\n", .{line});
        }
        try out.flush();
    }
};
