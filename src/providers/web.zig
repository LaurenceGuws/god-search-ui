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

pub const ParsedBookmarkQuery = struct {
    alias: []const u8,
};

pub const ParsedWebCommand = union(enum) {
    search: ParsedWebQuery,
    bookmark: ParsedBookmarkQuery,
};

pub fn appendRouteCandidates(
    allocator: std.mem.Allocator,
    parsed: search.Query,
    out: *search.CandidateList,
) !void {
    if (parsed.route != .web) return;
    const trimmed_term = std.mem.trim(u8, parsed.term, " \t\r\n");
    const parsed_cmd = parseWebCommand(parsed.term) orelse return;
    switch (parsed_cmd) {
        .search => |parsed_web| {
            const title = switch (parsed_web.engine) {
                .duckduckgo => "Search Web",
                .google => "Search Google",
                .wikipedia => "Search Wikipedia",
            };

            try out.append(allocator, .{
                .kind = .web,
                .title = title,
                .subtitle = parsed_web.query,
                .action = trimmed_term,
                .icon = "web-browser-symbolic",
            });
        },
        .bookmark => |_| {
            try out.append(allocator, .{
                .kind = .web,
                .title = "Open Bookmark",
                .subtitle = trimmed_term,
                .action = trimmed_term,
                .icon = "bookmark-new-symbolic",
            });
        },
    }
}

pub fn parseWebQuery(term_raw: []const u8) ?ParsedWebQuery {
    const term = std.mem.trim(u8, term_raw, " \t\r\n");
    if (term.len == 0) return null;

    const first_end = std.mem.indexOfAny(u8, term, " \t") orelse term.len;
    const first = term[0..first_end];

    if (std.ascii.eqlIgnoreCase(first, "g")) {
        const query = std.mem.trim(u8, term[first.len..], " \t");
        if (query.len == 0) return null;
        return .{ .engine = .google, .query = query };
    }
    if (std.ascii.eqlIgnoreCase(first, "ddg")) {
        const query = std.mem.trim(u8, term[first.len..], " \t");
        if (query.len == 0) return null;
        return .{ .engine = .duckduckgo, .query = query };
    }
    if (std.ascii.eqlIgnoreCase(first, "w")) {
        const query = std.mem.trim(u8, term[first.len..], " \t");
        if (query.len == 0) return null;
        return .{ .engine = .wikipedia, .query = query };
    }

    return .{ .engine = .duckduckgo, .query = term };
}

pub fn parseWebCommand(term_raw: []const u8) ?ParsedWebCommand {
    const term = std.mem.trim(u8, term_raw, " \t\r\n");
    if (term.len == 0) return null;

    const first_end = std.mem.indexOfAny(u8, term, " \t") orelse term.len;
    const first = term[0..first_end];
    if (std.ascii.eqlIgnoreCase(first, "b")) {
        const alias = std.mem.trim(u8, term[first.len..], " \t");
        if (alias.len == 0) return null;
        return .{ .bookmark = .{ .alias = alias } };
    }
    return .{ .search = parseWebQuery(term) orelse return null };
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

pub fn resolveBookmarkUrl(allocator: std.mem.Allocator, alias: []const u8) !?[]u8 {
    const path = try bookmarksPath(allocator);
    defer allocator.free(path);
    const data = readFileAnyPath(allocator, path, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(data);
    return lookupBookmarkUrlFromTsv(allocator, data, alias);
}

pub fn engineLabel(engine: WebEngine) []const u8 {
    return switch (engine) {
        .duckduckgo => "DuckDuckGo",
        .google => "Google",
        .wikipedia => "Wikipedia",
    };
}

fn bookmarksPath(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |xdg| {
        defer allocator.free(xdg);
        return std.fmt.allocPrint(allocator, "{s}/god-search-ui/web-bookmarks.tsv", .{xdg});
    } else |_| {}
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return std.fmt.allocPrint(allocator, "{s}/.config/god-search-ui/web-bookmarks.tsv", .{home});
}

fn readFileAnyPath(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        return file.readToEndAlloc(allocator, max_bytes);
    }
    return std.fs.cwd().readFileAlloc(allocator, path, max_bytes);
}

fn lookupBookmarkUrlFromTsv(allocator: std.mem.Allocator, data: []const u8, alias_query: []const u8) !?[]u8 {
    const alias_trimmed = std.mem.trim(u8, alias_query, " \t\r\n");
    if (alias_trimmed.len == 0) return null;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const row = std.mem.trimRight(u8, line, "\r");
        if (row.len == 0) continue;
        if (row[0] == '#') continue;

        var fields = std.mem.splitScalar(u8, row, '\t');
        const alias = std.mem.trim(u8, fields.next() orelse continue, " \t");
        if (alias.len == 0) continue;
        if (!std.ascii.eqlIgnoreCase(alias, alias_trimmed)) continue;

        const second = std.mem.trim(u8, fields.next() orelse continue, " \t");
        const third = std.mem.trim(u8, fields.next() orelse "", " \t");
        const url = if (third.len > 0) third else second;
        if (!looksLikeUrl(url)) continue;
        const dup = try allocator.dupe(u8, url);
        return dup;
    }
    return null;
}

fn looksLikeUrl(value: []const u8) bool {
    return std.mem.startsWith(u8, value, "http://") or std.mem.startsWith(u8, value, "https://");
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

test "appendRouteCandidates preserves executable selector payload but renders parsed query" {
    var out = search.CandidateList.empty;
    defer out.deinit(std.testing.allocator);

    try appendRouteCandidates(std.testing.allocator, search.parseQuery("?G  dota 2"), &out);
    try std.testing.expectEqual(@as(usize, 1), out.items.len);
    try std.testing.expectEqual(search.CandidateKind.web, out.items[0].kind);
    try std.testing.expectEqualStrings("Search Google", out.items[0].title);
    try std.testing.expectEqualStrings("dota 2", out.items[0].subtitle);
    try std.testing.expectEqualStrings("G  dota 2", out.items[0].action);
}

test "appendRouteCandidates supports bookmark subcommand" {
    var out = search.CandidateList.empty;
    defer out.deinit(std.testing.allocator);

    try appendRouteCandidates(std.testing.allocator, search.parseQuery("?b docs"), &out);
    try std.testing.expectEqual(@as(usize, 1), out.items.len);
    try std.testing.expectEqual(search.CandidateKind.web, out.items[0].kind);
    try std.testing.expectEqualStrings("Open Bookmark", out.items[0].title);
    try std.testing.expectEqualStrings("b docs", out.items[0].subtitle);
    try std.testing.expectEqualStrings("b docs", out.items[0].action);
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

    const google_upper = parseWebQuery("G dota 2") orelse unreachable;
    try std.testing.expectEqual(WebEngine.google, google_upper.engine);
    try std.testing.expectEqualStrings("dota 2", google_upper.query);

    const ddg_upper = parseWebQuery("DDG arch linux") orelse unreachable;
    try std.testing.expectEqual(WebEngine.duckduckgo, ddg_upper.engine);
    try std.testing.expectEqualStrings("arch linux", ddg_upper.query);

    const wiki_upper = parseWebQuery("W zig language") orelse unreachable;
    try std.testing.expectEqual(WebEngine.wikipedia, wiki_upper.engine);
    try std.testing.expectEqualStrings("zig language", wiki_upper.query);

    const default_engine = parseWebQuery("best dota builds") orelse unreachable;
    try std.testing.expectEqual(WebEngine.duckduckgo, default_engine.engine);
    try std.testing.expectEqualStrings("best dota builds", default_engine.query);

    try std.testing.expect(parseWebQuery("g   ") == null);
}

test "parseWebCommand routes bookmark subcommand and search commands" {
    const bookmark = parseWebCommand("b docs") orelse unreachable;
    switch (bookmark) {
        .bookmark => |b| try std.testing.expectEqualStrings("docs", b.alias),
        else => return std.testing.expect(false),
    }

    const search_cmd = parseWebCommand("g zig") orelse unreachable;
    switch (search_cmd) {
        .search => |q| {
            try std.testing.expectEqual(WebEngine.google, q.engine);
            try std.testing.expectEqualStrings("zig", q.query);
        },
        else => return std.testing.expect(false),
    }

    try std.testing.expect(parseWebCommand("b   ") == null);
}

test "lookupBookmarkUrlFromTsv supports two and three column rows" {
    const data =
        "# alias<TAB>url or alias<TAB>title<TAB>url\n" ++
        "gh\thttps://github.com\n" ++
        "docs\tProject Docs\thttps://example.com/docs\n" ++
        "bad\tftp://example.com\n";

    const gh = try lookupBookmarkUrlFromTsv(std.testing.allocator, data, "GH");
    defer if (gh) |v| std.testing.allocator.free(v);
    try std.testing.expect(gh != null);
    try std.testing.expectEqualStrings("https://github.com", gh.?);

    const docs = try lookupBookmarkUrlFromTsv(std.testing.allocator, data, "docs");
    defer if (docs) |v| std.testing.allocator.free(v);
    try std.testing.expect(docs != null);
    try std.testing.expectEqualStrings("https://example.com/docs", docs.?);

    const missing = try lookupBookmarkUrlFromTsv(std.testing.allocator, data, "missing");
    try std.testing.expect(missing == null);
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
