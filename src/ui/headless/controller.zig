const std = @import("std");
const app = @import("../../app/mod.zig");
const common_commands = @import("../common/commands.zig");
const render = @import("render.zig");
const icon_diag = @import("icon_diag.zig");

pub fn run(allocator: std.mem.Allocator, service: *app.SearchService) !void {
    var stdin = std.fs.File.stdin().deprecatedReader();
    var stdout = std.fs.File.stdout().deprecatedWriter();

    try stdout.print("[ui] headless mode (GTK disabled). Type query, ':q' to quit.\n", .{});
    try stdout.print("[ui] commands: :refresh, :icondiag, :icondiag --json\n", .{});
    while (true) {
        try stdout.print("search> ", .{});
        const line_opt = stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 4096) catch |err| switch (err) {
            error.StreamTooLong => {
                try drainUntilNewline(&stdin);
                try stdout.print("  input too long (max 4096 bytes); line discarded\n", .{});
                continue;
            },
            else => return err,
        };
        defer if (line_opt) |line| allocator.free(line);
        const line = line_opt orelse break;
        const query = std.mem.trim(u8, line, " \t\r\n");
        switch (common_commands.parse(query)) {
            .quit => break,
            .refresh => {
                service.invalidateSnapshot();
                try service.prewarmProviders(allocator);
                try stdout.print("  snapshot refreshed\n", .{});
                continue;
            },
            .icon_diag => |json| {
                try icon_diag.printIconDiagnostics(allocator, stdout, service, json);
                continue;
            },
            .none => {},
        }

        const ranked = try service.searchQuery(allocator, query);
        defer allocator.free(ranked);
        try render.printQueryMeta(stdout, service);
        try render.printTopResults(stdout, ranked, 5);
        _ = try service.drainScheduledRefresh(allocator);
    }
}

fn drainUntilNewline(reader: anytype) !void {
    while (true) {
        const byte = reader.readByte() catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        if (byte == '\n') return;
    }
}
