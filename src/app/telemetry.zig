const std = @import("std");

pub const TelemetrySink = struct {
    path: []const u8,

    pub fn init(path: []const u8) TelemetrySink {
        return .{ .path = path };
    }

    pub fn emitActionEvent(
        self: TelemetrySink,
        allocator: std.mem.Allocator,
        kind: []const u8,
        action: []const u8,
        status: []const u8,
        detail: []const u8,
    ) !void {
        const ts = std.time.timestamp();
        const line = try std.fmt.allocPrint(allocator, "ts={d} kind={s} action={s} status={s} detail={s}\n", .{ ts, kind, action, status, detail });
        defer allocator.free(line);

        if (std.fs.path.isAbsolute(self.path)) {
            try ensureParentDirAbsolute(self.path);
            const file = try std.fs.createFileAbsolute(self.path, .{ .truncate = false, .read = true });
            defer file.close();
            try file.seekFromEnd(0);
            try file.writeAll(line);
            return;
        }

        const file = try std.fs.cwd().createFile(self.path, .{ .truncate = false, .read = true });
        defer file.close();
        try file.seekFromEnd(0);
        try file.writeAll(line);
    }
};

fn ensureParentDirAbsolute(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    std.fs.makeDirAbsolute(parent) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
}

test "telemetry sink emits event line" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);
    const log_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/events.log", .{path});
    defer std.testing.allocator.free(log_path);

    const sink = TelemetrySink.init(log_path);
    try sink.emitActionEvent(std.testing.allocator, "action", "power", "ok", "wlogout");

    const file = try std.fs.openFileAbsolute(log_path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(std.testing.allocator, 1024);
    defer std.testing.allocator.free(data);
    try std.testing.expect(std.mem.indexOf(u8, data, "action=power") != null);
    try std.testing.expect(std.mem.indexOf(u8, data, "status=ok") != null);
}
