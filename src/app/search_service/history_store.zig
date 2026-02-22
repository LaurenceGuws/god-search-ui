const std = @import("std");

pub fn recordSelection(
    history: *std.ArrayListUnmanaged([]u8),
    max_history: usize,
    allocator: std.mem.Allocator,
    action: []const u8,
) !void {
    if (action.len == 0) return;
    const copy = try allocator.dupe(u8, action);
    try history.append(allocator, copy);

    if (history.items.len > max_history) {
        const oldest = history.orderedRemove(0);
        allocator.free(oldest);
    }
}

pub fn loadHistory(
    history: *std.ArrayListUnmanaged([]u8),
    max_history: usize,
    history_path: ?[]const u8,
    allocator: std.mem.Allocator,
) !void {
    const path = history_path orelse return;
    const data = readFileAnyPath(allocator, path, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer allocator.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        try recordSelection(history, max_history, allocator, trimmed);
    }
}

pub fn saveHistory(history: []const []u8, history_path: ?[]const u8, allocator: std.mem.Allocator) !void {
    const path = history_path orelse return;

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    for (history) |entry| {
        try writer.print("{s}\\n", .{entry});
    }
    try writeFileAnyPath(path, out.items);
}

pub fn historyViewNewestFirst(history: []const []u8, allocator: std.mem.Allocator) ![]const []const u8 {
    var out = std.ArrayList([]const u8).empty;
    defer out.deinit(allocator);

    var idx = history.len;
    while (idx > 0) : (idx -= 1) {
        try out.append(allocator, history[idx - 1]);
    }
    return out.toOwnedSlice(allocator);
}

fn readFileAnyPath(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        return file.readToEndAlloc(allocator, max_bytes);
    }
    return std.fs.cwd().readFileAlloc(allocator, path, max_bytes);
}

fn writeFileAnyPath(path: []const u8, data: []const u8) !void {
    if (std.fs.path.isAbsolute(path)) {
        try ensureParentDirAbsolute(path);
        const file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(data);
        return;
    }
    try std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data = data,
    });
}

fn ensureParentDirAbsolute(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    try std.fs.makeDirAbsolute(parent);
}
