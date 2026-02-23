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
        var line = std.ArrayList(u8).empty;
        defer line.deinit(allocator);
        const writer = line.writer(allocator);

        try writer.print("ts={d} kind=", .{ts});
        try writeEscapedTelemetryField(writer, kind);
        try writer.writeAll(" action=");
        try writeEscapedTelemetryField(writer, action);
        try writer.writeAll(" status=");
        try writeEscapedTelemetryField(writer, status);
        try writer.writeAll(" detail=");
        try writeEscapedTelemetryField(writer, detail);
        try writer.writeByte('\n');

        try ensureParentDir(self.path);

        if (std.fs.path.isAbsolute(self.path)) {
            const file = try std.fs.createFileAbsolute(self.path, .{ .truncate = false, .read = true });
            defer file.close();
            try file.seekFromEnd(0);
            try file.writeAll(line.items);
            try file.sync();
            return;
        }

        const file = try std.fs.cwd().createFile(self.path, .{ .truncate = false, .read = true });
        defer file.close();
        try file.seekFromEnd(0);
        try file.writeAll(line.items);
        try file.sync();
    }
};

fn ensureParentDir(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    try std.fs.cwd().makePath(parent);
}

fn writeEscapedTelemetryField(writer: anytype, value: []const u8) !void {
    for (value) |c| {
        switch (c) {
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\\' => try writer.writeAll("\\\\"),
            else => try writer.writeByte(c),
        }
    }
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

test "telemetry sink creates relative parent and escapes newlines" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    defer original_cwd.setAsCwd() catch unreachable;

    try tmp.dir.setAsCwd();

    const sink = TelemetrySink.init("nested/events.log");
    try sink.emitActionEvent(std.testing.allocator, "action\nkind", "power", "ok", "line1\nline2\r\\tail");

    const data = try tmp.dir.readFileAlloc(std.testing.allocator, "nested/events.log", 1024);
    defer std.testing.allocator.free(data);

    try std.testing.expect(std.mem.indexOf(u8, data, "kind=action\\nkind") != null);
    try std.testing.expect(std.mem.indexOf(u8, data, "detail=line1\\nline2\\r\\\\tail") != null);

    var newline_count: usize = 0;
    for (data) |c| {
        if (c == '\n') newline_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), newline_count);
}

test "telemetry sink creates absolute parent directories" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const base = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(base);
    const log_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/nested/events.log", .{base});
    defer std.testing.allocator.free(log_path);

    const sink = TelemetrySink.init(log_path);
    try sink.emitActionEvent(std.testing.allocator, "action", "power", "ok", "absolute");

    const file = try std.fs.openFileAbsolute(log_path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(std.testing.allocator, 1024);
    defer std.testing.allocator.free(data);
    try std.testing.expect(std.mem.indexOf(u8, data, "detail=absolute") != null);
}
