const std = @import("std");
const history_store = @import("history_store.zig");

pub fn recordLocked(
    history: *std.ArrayListUnmanaged([]u8),
    max_history: usize,
    allocator: std.mem.Allocator,
    action: []const u8,
) !void {
    try history_store.recordSelection(history, max_history, allocator, action);
}

pub fn loadLocked(
    history: *std.ArrayListUnmanaged([]u8),
    max_history: usize,
    history_path: ?[]const u8,
    allocator: std.mem.Allocator,
) !void {
    try history_store.loadHistory(history, max_history, history_path, allocator);
}

pub fn saveLocked(
    history: []const []u8,
    history_path: ?[]const u8,
    allocator: std.mem.Allocator,
) !void {
    try history_store.saveHistory(history, history_path, allocator);
}

pub fn snapshotNewestFirstOwnedLocked(
    history: []const []u8,
    allocator: std.mem.Allocator,
) ![]const []const u8 {
    return history_store.historySnapshotNewestFirstOwned(history, allocator);
}

pub fn freeSnapshot(allocator: std.mem.Allocator, history_snapshot: []const []const u8) void {
    history_store.freeOwnedHistorySnapshot(allocator, history_snapshot);
}

pub fn deinitHistory(
    history: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
) void {
    for (history.items) |item| allocator.free(item);
    history.deinit(allocator);
}
