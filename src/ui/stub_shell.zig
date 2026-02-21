const std = @import("std");
const app = @import("../app/mod.zig");
const search = @import("../search/mod.zig");

pub const Shell = struct {
    pub fn run(allocator: std.mem.Allocator, service: *app.SearchService) !void {
        var stdin = std.fs.File.stdin().deprecatedReader();
        var stdout = std.fs.File.stdout().deprecatedWriter();

        try stdout.print("[ui] headless mode (GTK disabled). Type query, ':q' to quit.\n", .{});
        while (true) {
            try stdout.print("search> ", .{});
            const line_opt = try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 4096);
            defer if (line_opt) |line| allocator.free(line);
            const line = line_opt orelse break;
            const query = std.mem.trim(u8, line, " \t\r\n");
            if (std.mem.eql(u8, query, ":q")) break;

            const ranked = try service.searchQuery(allocator, query);
            defer allocator.free(ranked);
            try printTopResults(stdout, ranked, 5);

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
