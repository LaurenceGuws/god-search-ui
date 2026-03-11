const std = @import("std");
const builtin = @import("builtin");
const search = @import("../search/mod.zig");
const web_bookmarks = @import("web_bookmarks.zig");
const web_favicons = @import("web_favicons.zig");
const web_support = @import("web_support.zig");

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
    query: []const u8,
};

pub const ParsedWebCommand = union(enum) {
    search: ParsedWebQuery,
    bookmark: ParsedBookmarkQuery,
};

const ScrapedWebRow = struct {
    title: []const u8,
    subtitle: []const u8,
    url: []const u8,
    icon: []const u8,
};
var web_scrape_mu: std.Thread.Mutex = .{};
var web_scrape_rows: std.ArrayListUnmanaged(ScrapedWebRow) = .{};
var web_scrape_owned: std.ArrayListUnmanaged([]u8) = .{};
const web_scrape_limit: usize = 10;
const web_favicon_probe_limit: usize = 5;
const bookmark_favicon_probe_limit: usize = 30;

pub fn invalidateCaches() void {
    web_bookmarks.invalidate();
    web_favicons.invalidate();

    web_scrape_mu.lock();
    clearScrapedWebLocked();
    web_scrape_mu.unlock();

    clearWebCacheFiles();

    std.log.info("web cache invalidated via refresh request", .{});
}

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
            if (!builtin.is_test and parsed_web.engine == .duckduckgo) {
                const scraped_count = appendScrapedWebResults(allocator, parsed_web.query, out) catch 0;
                std.log.info("web scrape query={s} rows={d}", .{ parsed_web.query, scraped_count });
                if (scraped_count > 0) {
                    try out.append(allocator, .{
                        .kind = .web,
                        .title = "Open Search in Browser",
                        .subtitle = parsed_web.query,
                        .action = trimmed_term,
                        .icon = "web-browser-symbolic",
                    });
                    return;
                }
            }
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
            appendBrowserBookmarkCandidates(allocator, parsed_web_query(parsed_cmd), out);
        },
    }
}

fn appendScrapedWebResults(
    allocator: std.mem.Allocator,
    query: []const u8,
    out: *search.CandidateList,
) !usize {
    _ = try scrapeDuckDuckGoHtmlRows(allocator, query);

    web_scrape_mu.lock();
    defer web_scrape_mu.unlock();
    for (web_scrape_rows.items) |row| {
        try out.append(allocator, .{
            .kind = .web,
            .title = row.title,
            .subtitle = row.subtitle,
            .action = row.url,
            .icon = row.icon,
        });
    }
    return web_scrape_rows.items.len;
}

fn scrapeBraveRows(allocator: std.mem.Allocator, query: []const u8) !usize {
    const encoded = try percentEncodeQuery(allocator, query);
    defer allocator.free(encoded);
    const url = try std.fmt.allocPrint(allocator, "https://search.brave.com/search?q={s}&source=web", .{encoded});
    defer allocator.free(url);

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "curl", "-fsSL", "--connect-timeout", "3", "--max-time", "8", "-A", "Mozilla/5.0", url },
        .max_output_bytes = 4 * 1024 * 1024,
    }) catch return 0;
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);
    if (result.term != .Exited or result.term.Exited != 0) return 0;

    const section = braveWebSection(result.stdout) orelse return 0;
    web_scrape_mu.lock();
    clearScrapedWebLocked();
    web_scrape_mu.unlock();

    var idx: usize = 0;
    var parsed: usize = 0;
    var favicon_probed: usize = 0;
    while (idx < section.len and parsed < web_scrape_limit) {
        const title_key = std.mem.indexOfPos(u8, section, idx, "title:\"") orelse break;
        const title_start = title_key + "title:\"".len;
        const title, const title_next = parseJsQuoted(allocator, section, title_start) orelse break;
        idx = title_next;

        const url_key = std.mem.indexOfPos(u8, section, idx, "url:\"") orelse {
            allocator.free(title);
            continue;
        };
        const url_start = url_key + "url:\"".len;
        const hit_url, const url_next = parseJsQuoted(allocator, section, url_start) orelse {
            allocator.free(title);
            continue;
        };
        idx = url_next;

        const desc_key = std.mem.indexOfPos(u8, section, idx, "description:\"") orelse {
            allocator.free(hit_url);
            allocator.free(title);
            continue;
        };
        const desc_start = desc_key + "description:\"".len;
        const description, const desc_next = parseJsQuoted(allocator, section, desc_start) orelse {
            allocator.free(hit_url);
            allocator.free(title);
            continue;
        };
        idx = desc_next;

        if (!web_support.looksLikeUrl(hit_url) or title.len == 0) {
            allocator.free(description);
            allocator.free(hit_url);
            allocator.free(title);
            continue;
        }

        const subtitle = std.fmt.allocPrint(allocator, "{s} | {s}", .{ urlHost(hit_url), clampText(description, 180) }) catch {
            allocator.free(description);
            allocator.free(hit_url);
            allocator.free(title);
            continue;
        };
        const icon_value = if (favicon_probed < bookmark_favicon_probe_limit) blk: {
            favicon_probed += 1;
            if (web_favicons.probePathWithReport(allocator, hit_url).path) |path| {
                break :blk path;
            }
            break :blk "web-browser-symbolic";
        } else "web-browser-symbolic";
        web_scrape_mu.lock();
        appendScrapedRowLocked(title, subtitle, hit_url, icon_value) catch {
            web_scrape_mu.unlock();
            allocator.free(subtitle);
            allocator.free(description);
            allocator.free(hit_url);
            allocator.free(title);
            continue;
        };
        web_scrape_mu.unlock();
        allocator.free(subtitle);
        allocator.free(description);
        allocator.free(hit_url);
        allocator.free(title);
        parsed += 1;
    }
    return parsed;
}

fn scrapeDuckDuckGoHtmlRows(allocator: std.mem.Allocator, query: []const u8) !usize {
    const encoded = try percentEncodeQuery(allocator, query);
    defer allocator.free(encoded);
    const url = try std.fmt.allocPrint(allocator, "https://duckduckgo.com/html/?q={s}", .{encoded});
    defer allocator.free(url);

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "curl", "-fsSL", "--connect-timeout", "3", "--max-time", "8", "-A", "Mozilla/5.0", url },
        .max_output_bytes = 4 * 1024 * 1024,
    }) catch return 0;
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);
    if (result.term != .Exited or result.term.Exited != 0) {
        std.log.warn("web scrape ddg curl failed query={s} term={any}", .{ query, result.term });
        return 0;
    }

    web_scrape_mu.lock();
    clearScrapedWebLocked();
    web_scrape_mu.unlock();

    var cursor: usize = 0;
    var parsed: usize = 0;
    var favicon_probed: usize = 0;
    var marker_hits: usize = 0;
    var valid_urls: usize = 0;
    var titled_rows: usize = 0;
    const href_marker = "uddg=";
    while (parsed < web_scrape_limit and cursor < result.stdout.len) {
        const href_rel = std.mem.indexOfPos(u8, result.stdout, cursor, href_marker) orelse break;
        marker_hits += 1;
        const href_start = href_rel + href_marker.len;
        const href_end = std.mem.indexOfAnyPos(u8, result.stdout, href_start, "\"&") orelse break;
        cursor = href_end;

        const encoded_target = result.stdout[href_start..href_end];
        const decoded_target = urlDecodeAlloc(allocator, encoded_target) catch continue;
        defer allocator.free(decoded_target);
        if (!web_support.looksLikeUrl(decoded_target)) continue;
        valid_urls += 1;

        const title_open = std.mem.lastIndexOf(u8, result.stdout[0..href_rel], "<a") orelse continue;
        const gt_idx = std.mem.indexOfPos(u8, result.stdout, title_open, ">") orelse continue;
        const title_end = std.mem.indexOfPos(u8, result.stdout, gt_idx + 1, "</a>") orelse continue;
        const title_raw = result.stdout[gt_idx + 1 .. title_end];
        const title = stripHtmlTagsAlloc(allocator, title_raw) catch continue;
        defer allocator.free(title);
        if (title.len == 0) continue;
        titled_rows += 1;

        const snippet_start = std.mem.indexOfPos(u8, result.stdout, title_end, "result__snippet") orelse title_end;
        const snippet_gt = std.mem.indexOfPos(u8, result.stdout, snippet_start, ">") orelse title_end;
        const snippet_end = std.mem.indexOfPos(u8, result.stdout, snippet_gt + 1, "</a>") orelse
            std.mem.indexOfPos(u8, result.stdout, snippet_gt + 1, "</div>") orelse snippet_gt;
        const snippet_raw = if (snippet_gt < snippet_end) result.stdout[snippet_gt + 1 .. snippet_end] else "";
        const snippet_clean = stripHtmlTagsAlloc(allocator, snippet_raw) catch allocator.dupe(u8, "") catch continue;
        defer allocator.free(snippet_clean);

        const subtitle = std.fmt.allocPrint(allocator, "{s} | {s}", .{ urlHost(decoded_target), clampText(snippet_clean, 180) }) catch continue;
        defer allocator.free(subtitle);
        const icon_value = if (favicon_probed < web_favicon_probe_limit) blk: {
            favicon_probed += 1;
            if (web_favicons.probePathWithReport(allocator, decoded_target).path) |path| {
                break :blk path;
            }
            break :blk "web-browser-symbolic";
        } else "web-browser-symbolic";

        web_scrape_mu.lock();
        appendScrapedRowLocked(title, subtitle, decoded_target, icon_value) catch {
            web_scrape_mu.unlock();
            continue;
        };
        web_scrape_mu.unlock();
        parsed += 1;
    }

    web_scrape_mu.lock();
    const total = web_scrape_rows.items.len;
    web_scrape_mu.unlock();
    std.log.info(
        "web scrape ddg done query={s} bytes={d} markers={d} valid_urls={d} titled={d} accepted={d}",
        .{ query, result.stdout.len, marker_hits, valid_urls, titled_rows, total },
    );
    return total;
}

fn braveWebSection(html: []const u8) ?[]const u8 {
    const marker = "web:{type:\"search\",results:[";
    const start = std.mem.indexOf(u8, html, marker) orelse return null;
    const from = html[start + marker.len ..];
    const end_rel = std.mem.indexOf(u8, from, "],summarizer:") orelse
        std.mem.indexOf(u8, from, "],locations:") orelse
        std.mem.indexOf(u8, from, "],news:") orelse
        return null;
    return from[0..end_rel];
}

fn parseJsQuoted(allocator: std.mem.Allocator, input: []const u8, start: usize) ?struct { []u8, usize } {
    if (start >= input.len) return null;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var i = start;
    while (i < input.len) : (i += 1) {
        const ch = input[i];
        if (ch == '"') {
            return .{ out.toOwnedSlice(allocator) catch return null, i + 1 };
        }
        if (ch != '\\') {
            out.append(allocator, ch) catch return null;
            continue;
        }
        i += 1;
        if (i >= input.len) return null;
        const esc = input[i];
        switch (esc) {
            '"', '\\', '/' => out.append(allocator, esc) catch return null,
            'b' => out.append(allocator, 0x08) catch return null,
            'f' => out.append(allocator, 0x0c) catch return null,
            'n' => out.append(allocator, '\n') catch return null,
            'r' => out.append(allocator, '\r') catch return null,
            't' => out.append(allocator, '\t') catch return null,
            'u' => {
                if (i + 4 >= input.len) return null;
                const hex = input[i + 1 .. i + 5];
                const cp = std.fmt.parseUnsigned(u21, hex, 16) catch return null;
                var buf: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(cp, &buf) catch return null;
                out.appendSlice(allocator, buf[0..n]) catch return null;
                i += 4;
            },
            else => out.append(allocator, esc) catch return null,
        }
    }
    return null;
}

fn urlHost(url: []const u8) []const u8 {
    const stripped = if (std.mem.startsWith(u8, url, "https://"))
        url["https://".len..]
    else if (std.mem.startsWith(u8, url, "http://"))
        url["http://".len..]
    else
        url;
    const slash = std.mem.indexOfScalar(u8, stripped, '/') orelse stripped.len;
    return stripped[0..slash];
}

fn clampText(text: []const u8, max_len: usize) []const u8 {
    if (text.len <= max_len) return text;
    return text[0..max_len];
}

fn keepScrapedStringLocked(value: []const u8) ![]const u8 {
    const copy = try std.heap.page_allocator.dupe(u8, value);
    try web_scrape_owned.append(std.heap.page_allocator, copy);
    return copy;
}

fn appendScrapedRowLocked(title: []const u8, subtitle: []const u8, url: []const u8, icon: []const u8) !void {
    const owned_len_before = web_scrape_owned.items.len;
    errdefer {
        while (web_scrape_owned.items.len > owned_len_before) {
            const item = web_scrape_owned.pop() orelse break;
            std.heap.page_allocator.free(item);
        }
    }
    const kept_title = try keepScrapedStringLocked(title);
    const kept_subtitle = try keepScrapedStringLocked(subtitle);
    const kept_url = try keepScrapedStringLocked(url);
    const kept_icon = try keepScrapedStringLocked(icon);
    try web_scrape_rows.append(std.heap.page_allocator, .{
        .title = kept_title,
        .subtitle = kept_subtitle,
        .url = kept_url,
        .icon = kept_icon,
    });
}

fn clearScrapedWebLocked() void {
    for (web_scrape_owned.items) |item| std.heap.page_allocator.free(item);
    web_scrape_owned.clearRetainingCapacity();
    web_scrape_rows.clearRetainingCapacity();
}

fn stripHtmlTagsAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var inside_tag = false;
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const ch = input[i];
        if (ch == '<') {
            inside_tag = true;
            continue;
        }
        if (ch == '>') {
            inside_tag = false;
            continue;
        }
        if (inside_tag) continue;
        try out.append(allocator, ch);
    }
    const compact = std.mem.trim(u8, out.items, " \t\r\n");
    const decoded = try htmlDecodeAlloc(allocator, compact);
    return decoded;
}

fn htmlDecodeAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        if (input[i] != '&') {
            try out.append(allocator, input[i]);
            continue;
        }
        if (std.mem.startsWith(u8, input[i..], "&amp;")) {
            try out.append(allocator, '&');
            i += "&amp;".len - 1;
            continue;
        }
        if (std.mem.startsWith(u8, input[i..], "&quot;")) {
            try out.append(allocator, '"');
            i += "&quot;".len - 1;
            continue;
        }
        if (std.mem.startsWith(u8, input[i..], "&#x27;")) {
            try out.append(allocator, '\'');
            i += "&#x27;".len - 1;
            continue;
        }
        if (std.mem.startsWith(u8, input[i..], "&#39;")) {
            try out.append(allocator, '\'');
            i += "&#39;".len - 1;
            continue;
        }
        if (std.mem.startsWith(u8, input[i..], "&lt;")) {
            try out.append(allocator, '<');
            i += "&lt;".len - 1;
            continue;
        }
        if (std.mem.startsWith(u8, input[i..], "&gt;")) {
            try out.append(allocator, '>');
            i += "&gt;".len - 1;
            continue;
        }
        try out.append(allocator, '&');
    }
    return out.toOwnedSlice(allocator);
}

fn urlDecodeAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const ch = input[i];
        if (ch == '+') {
            try out.append(allocator, ' ');
            continue;
        }
        if (ch == '%' and i + 2 < input.len) {
            const hi = std.fmt.charToDigit(input[i + 1], 16) catch {
                try out.append(allocator, ch);
                continue;
            };
            const lo = std.fmt.charToDigit(input[i + 2], 16) catch {
                try out.append(allocator, ch);
                continue;
            };
            const byte: u8 = @intCast((hi << 4) | lo);
            try out.append(allocator, byte);
            i += 2;
            continue;
        }
        try out.append(allocator, ch);
    }
    return out.toOwnedSlice(allocator);
}

fn parsed_web_query(cmd: ParsedWebCommand) []const u8 {
    return switch (cmd) {
        .bookmark => |b| b.query,
        .search => |s| s.query,
    };
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
        const query = std.mem.trim(u8, term[first.len..], " \t");
        return .{ .bookmark = .{ .query = query } };
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
    return web_bookmarks.resolveUrl(allocator, alias);
}

pub fn resolveBrowserBookmarkUrl(allocator: std.mem.Allocator, query: []const u8) !?[]u8 {
    return web_bookmarks.resolveUrl(allocator, query);
}

pub fn engineLabel(engine: WebEngine) []const u8 {
    return switch (engine) {
        .duckduckgo => "DuckDuckGo",
        .google => "Google",
        .wikipedia => "Wikipedia",
    };
}

fn appendBrowserBookmarkCandidates(allocator: std.mem.Allocator, query: []const u8, out: *search.CandidateList) void {
    web_bookmarks.appendCandidates(allocator, query, out, bookmark_favicon_probe_limit, bookmarkFaviconPath);
}

fn bookmarkFaviconPath(allocator: std.mem.Allocator, url: []const u8) ?[]const u8 {
    const probe = web_favicons.probePathWithReport(allocator, url);
    if (probe.path) |path| return path;
    return null;
}

fn clearWebCacheFiles() void {
    const allocator = std.heap.page_allocator;
    const web_dir = web_support.webCacheDir(allocator) catch return;
    defer allocator.free(web_dir);
    deleteTreeIfExists(web_dir);
}

fn deleteTreeIfExists(path: []const u8) void {
    std.fs.accessAbsolute(path, .{}) catch return;
    var parent = std.fs.openDirAbsolute("/", .{}) catch return;
    defer parent.close();
    parent.deleteTree(path[1..]) catch |err| {
        std.log.debug("web cache deleteTree failed path={s} err={s}", .{ path, @errorName(err) });
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
        .bookmark => |b| try std.testing.expectEqualStrings("docs", b.query),
        else => return std.testing.expect(false),
    }

    const bookmark_empty = parseWebCommand("b") orelse unreachable;
    switch (bookmark_empty) {
        .bookmark => |b| try std.testing.expectEqualStrings("", b.query),
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

    const bookmark_space = parseWebCommand("b   ") orelse unreachable;
    switch (bookmark_space) {
        .bookmark => |b| try std.testing.expectEqualStrings("", b.query),
        else => return std.testing.expect(false),
    }
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
