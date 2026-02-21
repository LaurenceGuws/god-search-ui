const std = @import("std");
const app = @import("../app/mod.zig");
const search = @import("../search/mod.zig");

pub const Shell = struct {
    pub fn run(allocator: std.mem.Allocator, service: *app.SearchService, _: *app.TelemetrySink) !void {
        var stdin = std.fs.File.stdin().deprecatedReader();
        var stdout = std.fs.File.stdout().deprecatedWriter();

        try stdout.print("[ui] headless mode (GTK disabled). Type query, ':q' to quit.\n", .{});
        try stdout.print("[ui] commands: :refresh, :icondiag\n", .{});
        while (true) {
            try stdout.print("search> ", .{});
            const line_opt = try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 4096);
            defer if (line_opt) |line| allocator.free(line);
            const line = line_opt orelse break;
            const query = std.mem.trim(u8, line, " \t\r\n");
            if (std.mem.eql(u8, query, ":q")) break;
            if (std.mem.eql(u8, query, ":refresh")) {
                service.invalidateSnapshot();
                try service.prewarmProviders(allocator);
                try stdout.print("  snapshot refreshed\n", .{});
                continue;
            }
            if (std.mem.eql(u8, query, ":icondiag")) {
                try printIconDiagnostics(allocator, stdout, service);
                continue;
            }

            const ranked = try service.searchQuery(allocator, query);
            defer allocator.free(ranked);
            const ms = @as(f64, @floatFromInt(service.last_query_elapsed_ns)) / 1_000_000.0;
            try stdout.print("  (query time: {d:.2} ms)\n", .{ms});
            if (service.last_query_used_stale_cache) {
                try stdout.print("  (using stale snapshot; refresh scheduled)\n", .{});
            }
            if (service.last_query_refreshed_cache) {
                try stdout.print("  (snapshot auto-refreshed)\n", .{});
            }
            try printTopResults(stdout, ranked, 5);
            _ = try service.drainScheduledRefresh(allocator);

            if (ranked.len > 0) {
                try service.recordSelection(allocator, ranked[0].candidate.action);
            }
        }
    }
};

fn printTopResults(writer: anytype, ranked: []const search.ScoredCandidate, max_items: usize) !void {
    if (ranked.len == 0) {
        try writer.print("  (no results)\n", .{});
        return;
    }

    const limit = @min(ranked.len, max_items);
    for (ranked[0..limit], 0..) |row, idx| {
        try writer.print("  {d}. [{d}] {s} — {s}\n", .{ idx + 1, row.score, row.candidate.title, row.candidate.subtitle });
    }
}

fn printIconDiagnostics(allocator: std.mem.Allocator, writer: anytype, service: *app.SearchService) !void {
    const ranked = try service.searchQuery(allocator, "");
    defer allocator.free(ranked);

    var app_count: usize = 0;
    var with_icon_metadata: usize = 0;
    var with_action_icon_token: usize = 0;
    var likely_glyph_fallback: usize = 0;

    for (ranked) |row| {
        if (row.candidate.kind != .app) continue;
        app_count += 1;

        const icon_trimmed = std.mem.trim(u8, row.candidate.icon, " \t\r\n");
        if (icon_trimmed.len > 0) {
            with_icon_metadata += 1;
            continue;
        }

        if (actionCommandToken(row.candidate.action).len > 0) {
            with_action_icon_token += 1;
        } else {
            likely_glyph_fallback += 1;
        }
    }

    try writer.print("  icon diagnostics:\n", .{});
    try writer.print("    apps total: {d}\n", .{app_count});
    try writer.print("    with icon metadata: {d}\n", .{with_icon_metadata});
    try writer.print("    with command-token icon fallback: {d}\n", .{with_action_icon_token});
    try writer.print("    likely glyph fallback: {d}\n", .{likely_glyph_fallback});
}

fn actionCommandToken(action: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, action, " \t\r\n");
    if (trimmed.len == 0) return "";

    const split_idx = std.mem.indexOfScalar(u8, trimmed, ' ') orelse trimmed.len;
    var token = trimmed[0..split_idx];
    token = std.mem.trim(u8, token, "\"'");
    if (token.len == 0) return "";

    if (std.mem.lastIndexOfScalar(u8, token, '/')) |slash_idx| {
        if (slash_idx + 1 < token.len) token = token[slash_idx + 1 ..];
    }
    return token;
}
