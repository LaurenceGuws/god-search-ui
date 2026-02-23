const std = @import("std");
const search = @import("../search/mod.zig");

pub const WebEngine = enum {
    duckduckgo,
    google,
    wikipedia,
};

pub const ParsedWebQuery = struct {
    engine: WebEngine,
    query: []const u8,
};

pub fn appendRouteCandidates(
    allocator: std.mem.Allocator,
    parsed: search.Query,
    out: *search.CandidateList,
) !void {
    if (parsed.route != .web) return;
    const parsed_web = parseWebQuery(parsed.term) orelse return;
    const trimmed_term = std.mem.trim(u8, parsed.term, " \t\r\n");
    const title = switch (parsed_web.engine) {
        .duckduckgo => "Search Web",
        .google => "Search Google",
        .wikipedia => "Search Wikipedia",
    };

    try out.append(allocator, .{
        .kind = .web,
        .title = title,
        .subtitle = trimmed_term,
        .action = trimmed_term,
        .icon = "web-browser-symbolic",
    });
}

pub fn parseWebQuery(term_raw: []const u8) ?ParsedWebQuery {
    const term = std.mem.trim(u8, term_raw, " \t\r\n");
    if (term.len == 0) return null;

    const first_end = std.mem.indexOfAny(u8, term, " \t") orelse term.len;
    const first = term[0..first_end];

    if (std.mem.eql(u8, first, "g")) {
        const query = std.mem.trim(u8, term[first.len..], " \t");
        if (query.len == 0) return null;
        return .{ .engine = .google, .query = query };
    }
    if (std.mem.eql(u8, first, "ddg")) {
        const query = std.mem.trim(u8, term[first.len..], " \t");
        if (query.len == 0) return null;
        return .{ .engine = .duckduckgo, .query = query };
    }
    if (std.mem.eql(u8, first, "w")) {
        const query = std.mem.trim(u8, term[first.len..], " \t");
        if (query.len == 0) return null;
        return .{ .engine = .wikipedia, .query = query };
    }

    return .{ .engine = .duckduckgo, .query = term };
}

pub fn buildSearchUrl(allocator: std.mem.Allocator, parsed: ParsedWebQuery) ![]u8 {
    const encoded = try percentEncodeQuery(allocator, parsed.query);
    defer allocator.free(encoded);
    return switch (parsed.engine) {
        .duckduckgo => std.fmt.allocPrint(allocator, "https://duckduckgo.com/?q={s}", .{encoded}),
        .google => std.fmt.allocPrint(allocator, "https://www.google.com/search?q={s}", .{encoded}),
        .wikipedia => std.fmt.allocPrint(allocator, "https://en.wikipedia.org/w/index.php?search={s}", .{encoded}),
    };
}

pub fn engineLabel(engine: WebEngine) []const u8 {
    return switch (engine) {
        .duckduckgo => "DuckDuckGo",
        .google => "Google",
        .wikipedia => "Wikipedia",
    };
}

test "appendRouteCandidates adds one web result for non-empty ? query" {
    var out = search.CandidateList.empty;
    defer out.deinit(std.testing.allocator);

    try appendRouteCandidates(std.testing.allocator, search.parseQuery("? dota 2"), &out);
    try std.testing.expectEqual(@as(usize, 1), out.items.len);
    try std.testing.expectEqual(search.CandidateKind.web, out.items[0].kind);
    try std.testing.expectEqualStrings("Search Web", out.items[0].title);
    try std.testing.expectEqualStrings("dota 2", out.items[0].subtitle);
    try std.testing.expectEqualStrings("dota 2", out.items[0].action);
}

test "appendRouteCandidates ignores non-web and empty web terms" {
    var out = search.CandidateList.empty;
    defer out.deinit(std.testing.allocator);

    try appendRouteCandidates(std.testing.allocator, search.parseQuery("@ kitty"), &out);
    try appendRouteCandidates(std.testing.allocator, search.parseQuery("?   "), &out);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "parseWebQuery supports engine selectors and defaults" {
    const google = parseWebQuery("g dota 2") orelse unreachable;
    try std.testing.expectEqual(WebEngine.google, google.engine);
    try std.testing.expectEqualStrings("dota 2", google.query);

    const ddg = parseWebQuery("ddg  arch linux") orelse unreachable;
    try std.testing.expectEqual(WebEngine.duckduckgo, ddg.engine);
    try std.testing.expectEqualStrings("arch linux", ddg.query);

    const wiki = parseWebQuery("w zig language") orelse unreachable;
    try std.testing.expectEqual(WebEngine.wikipedia, wiki.engine);
    try std.testing.expectEqualStrings("zig language", wiki.query);

    const default_engine = parseWebQuery("best dota builds") orelse unreachable;
    try std.testing.expectEqual(WebEngine.duckduckgo, default_engine.engine);
    try std.testing.expectEqualStrings("best dota builds", default_engine.query);

    try std.testing.expect(parseWebQuery("g   ") == null);
}

test "buildSearchUrl uses selected engine" {
    const google = try buildSearchUrl(
        std.testing.allocator,
        .{ .engine = .google, .query = "dota 2" },
    );
    defer std.testing.allocator.free(google);
    try std.testing.expectEqualStrings("https://www.google.com/search?q=dota%202", google);

    const wiki = try buildSearchUrl(
        std.testing.allocator,
        .{ .engine = .wikipedia, .query = "zig language" },
    );
    defer std.testing.allocator.free(wiki);
    try std.testing.expectEqualStrings("https://en.wikipedia.org/w/index.php?search=zig%20language", wiki);
}

fn percentEncodeQuery(allocator: std.mem.Allocator, term: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    for (term) |ch| {
        if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '.' or ch == '_' or ch == '~') {
            try out.append(allocator, ch);
            continue;
        }
        const hex = [_]u8{
            '%',
            toUpperHex(ch >> 4),
            toUpperHex(ch & 0x0f),
        };
        try out.appendSlice(allocator, &hex);
    }
    return out.toOwnedSlice(allocator);
}

fn toUpperHex(nibble: u8) u8 {
    return if (nibble < 10) ('0' + nibble) else ('A' + (nibble - 10));
}
