const std = @import("std");

pub const Route = enum {
    blended,
    apps,
    windows,
    dirs,
    run,
    calc,
    web,
};

pub const Query = struct {
    raw: []const u8,
    route: Route,
    term: []const u8,
};

pub fn parse(raw_query: []const u8) Query {
    const raw = std.mem.trim(u8, raw_query, " \t\r\n");
    if (raw.len == 0) {
        return .{
            .raw = "",
            .route = .blended,
            .term = "",
        };
    }

    const prefix = raw[0];
    const rest = std.mem.trim(u8, raw[1..], " \t");
    return switch (prefix) {
        '@' => .{ .raw = raw, .route = .apps, .term = rest },
        '#' => .{ .raw = raw, .route = .windows, .term = rest },
        '~' => .{ .raw = raw, .route = .dirs, .term = rest },
        '>' => .{ .raw = raw, .route = .run, .term = rest },
        '=' => .{ .raw = raw, .route = .calc, .term = rest },
        '?' => .{ .raw = raw, .route = .web, .term = rest },
        else => .{ .raw = raw, .route = .blended, .term = raw },
    };
}

test "parse empty query uses blended route" {
    const q = parse("   ");
    try std.testing.expectEqual(Route.blended, q.route);
    try std.testing.expectEqualStrings("", q.term);
}

test "parse prefixed query routes correctly" {
    const q = parse("@ kitty");
    try std.testing.expectEqual(Route.apps, q.route);
    try std.testing.expectEqualStrings("kitty", q.term);
}

test "parse non-prefixed query stays blended" {
    const q = parse("firefox");
    try std.testing.expectEqual(Route.blended, q.route);
    try std.testing.expectEqualStrings("firefox", q.term);
}
