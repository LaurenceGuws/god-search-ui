const std = @import("std");
const app = @import("../../app/mod.zig");
const search = @import("../../search/mod.zig");

pub fn printQueryMeta(writer: anytype, service: *app.SearchService) !void {
    const ms = @as(f64, @floatFromInt(service.last_query_elapsed_ns)) / 1_000_000.0;
    try writer.print("  (query time: {d:.2} ms)\n", .{ms});
    if (service.last_query_used_stale_cache) {
        try writer.print("  (using stale snapshot; refresh scheduled)\n", .{});
    }
    if (service.last_query_refreshed_cache) {
        try writer.print("  (snapshot auto-refreshed)\n", .{});
    }
}

pub fn printTopResults(writer: anytype, ranked: []const search.ScoredCandidate, max_items: usize) !void {
    if (ranked.len == 0) {
        try writer.print("  (no results)\n", .{});
        return;
    }

    const limit = @min(ranked.len, max_items);
    for (ranked[0..limit], 0..) |row, idx| {
        try writer.print("  {d}. [{d}] {s} — {s}\n", .{ idx + 1, row.score, row.candidate.title, row.candidate.subtitle });
    }
}
