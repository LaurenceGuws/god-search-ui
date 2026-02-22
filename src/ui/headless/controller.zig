const std = @import("std");
const app = @import("../../app/mod.zig");
const render = @import("render.zig");
const icon_diag = @import("icon_diag.zig");

pub fn run(allocator: std.mem.Allocator, service: *app.SearchService) !void {
    var stdin = std.fs.File.stdin().deprecatedReader();
    var stdout = std.fs.File.stdout().deprecatedWriter();

    try stdout.print("[ui] headless mode (GTK disabled). Type query, ':q' to quit.\n", .{});
    try stdout.print("[ui] commands: :refresh, :icondiag, :icondiag --json\n", .{});
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
        if (std.mem.startsWith(u8, query, ":icondiag")) {
            const json = std.mem.eql(u8, query, ":icondiag --json");
            try icon_diag.printIconDiagnostics(allocator, stdout, service, json);
            continue;
        }

        const ranked = try service.searchQuery(allocator, query);
        defer allocator.free(ranked);
        try render.printQueryMeta(stdout, service);
        try render.printTopResults(stdout, ranked, 5);
        _ = try service.drainScheduledRefresh(allocator);

        if (ranked.len > 0) {
            try service.recordSelection(allocator, ranked[0].candidate.action);
        }
    }
}
