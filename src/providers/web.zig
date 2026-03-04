const std = @import("std");
const builtin = @import("builtin");
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
    query: []const u8,
};

pub const ParsedWebCommand = union(enum) {
    search: ParsedWebQuery,
    bookmark: ParsedBookmarkQuery,
};

const BrowserBookmark = struct {
    title: []const u8,
    url: []const u8,
    subtitle: []const u8,
};
const ScrapedWebRow = struct {
    title: []const u8,
    subtitle: []const u8,
    url: []const u8,
};

var browser_bookmarks_mu: std.Thread.Mutex = .{};
var browser_bookmarks_loaded: bool = false;
var browser_bookmarks: std.ArrayListUnmanaged(BrowserBookmark) = .{};
var browser_bookmarks_owned: std.ArrayListUnmanaged([]u8) = .{};
const browser_bookmark_limit: usize = 20_000;
var web_scrape_mu: std.Thread.Mutex = .{};
var web_scrape_rows: std.ArrayListUnmanaged(ScrapedWebRow) = .{};
var web_scrape_owned: std.ArrayListUnmanaged([]u8) = .{};
const web_scrape_limit: usize = 10;

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
                const scraped_count = appendBraveScrapedResults(allocator, parsed_web.query, out) catch 0;
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

fn appendBraveScrapedResults(
    allocator: std.mem.Allocator,
    query: []const u8,
    out: *search.CandidateList,
) !usize {
    const brave_rows = try scrapeBraveRows(allocator, query);
    if (brave_rows == 0) {
        _ = scrapeDuckDuckGoHtmlRows(allocator, query) catch 0;
    }

    web_scrape_mu.lock();
    defer web_scrape_mu.unlock();
    for (web_scrape_rows.items) |row| {
        try out.append(allocator, .{
            .kind = .web,
            .title = row.title,
            .subtitle = row.subtitle,
            .action = row.url,
            .icon = "web-browser-symbolic",
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

        if (!looksLikeUrl(hit_url) or title.len == 0) {
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
        web_scrape_mu.lock();
        appendScrapedRowLocked(title, subtitle, hit_url) catch {
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
    if (result.term != .Exited or result.term.Exited != 0) return 0;

    web_scrape_mu.lock();
    clearScrapedWebLocked();
    web_scrape_mu.unlock();

    var cursor: usize = 0;
    var parsed: usize = 0;
    const href_marker = "uddg=";
    while (parsed < web_scrape_limit and cursor < result.stdout.len) {
        const href_rel = std.mem.indexOfPos(u8, result.stdout, cursor, href_marker) orelse break;
        const href_start = href_rel + href_marker.len;
        const href_end = std.mem.indexOfAnyPos(u8, result.stdout, href_start, "\"&") orelse break;
        cursor = href_end;

        const encoded_target = result.stdout[href_start..href_end];
        const decoded_target = urlDecodeAlloc(allocator, encoded_target) catch continue;
        defer allocator.free(decoded_target);
        if (!looksLikeUrl(decoded_target)) continue;

        const title_open = std.mem.lastIndexOf(u8, result.stdout[0..href_rel], "<a") orelse continue;
        const gt_idx = std.mem.indexOfPos(u8, result.stdout, title_open, ">") orelse continue;
        const title_end = std.mem.indexOfPos(u8, result.stdout, gt_idx + 1, "</a>") orelse continue;
        const title_raw = result.stdout[gt_idx + 1 .. title_end];
        const title = stripHtmlTagsAlloc(allocator, title_raw) catch continue;
        defer allocator.free(title);
        if (title.len == 0) continue;

        const snippet_start = std.mem.indexOfPos(u8, result.stdout, title_end, "result__snippet") orelse title_end;
        const snippet_gt = std.mem.indexOfPos(u8, result.stdout, snippet_start, ">") orelse title_end;
        const snippet_end = std.mem.indexOfPos(u8, result.stdout, snippet_gt + 1, "</a>") orelse
            std.mem.indexOfPos(u8, result.stdout, snippet_gt + 1, "</div>") orelse snippet_gt;
        const snippet_raw = if (snippet_gt < snippet_end) result.stdout[snippet_gt + 1 .. snippet_end] else "";
        const snippet_clean = stripHtmlTagsAlloc(allocator, snippet_raw) catch allocator.dupe(u8, "") catch continue;
        defer allocator.free(snippet_clean);

        const subtitle = std.fmt.allocPrint(allocator, "{s} | {s}", .{ urlHost(decoded_target), clampText(snippet_clean, 180) }) catch continue;
        defer allocator.free(subtitle);

        web_scrape_mu.lock();
        appendScrapedRowLocked(title, subtitle, decoded_target) catch {
            web_scrape_mu.unlock();
            continue;
        };
        web_scrape_mu.unlock();
        parsed += 1;
    }

    web_scrape_mu.lock();
    const total = web_scrape_rows.items.len;
    web_scrape_mu.unlock();
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

fn appendScrapedRowLocked(title: []const u8, subtitle: []const u8, url: []const u8) !void {
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
    try web_scrape_rows.append(std.heap.page_allocator, .{
        .title = kept_title,
        .subtitle = kept_subtitle,
        .url = kept_url,
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
    const direct = try resolveBrowserBookmarkUrl(allocator, alias);
    if (direct != null) return direct;

    const path = try bookmarksPath(allocator);
    defer allocator.free(path);
    const data = readFileAnyPath(allocator, path, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(data);
    return lookupBookmarkUrlFromTsv(allocator, data, alias);
}

pub fn resolveBrowserBookmarkUrl(allocator: std.mem.Allocator, query: []const u8) !?[]u8 {
    const trimmed = std.mem.trim(u8, query, " \t\r\n");
    if (trimmed.len == 0) return null;

    ensureBrowserBookmarksLoaded();
    browser_bookmarks_mu.lock();
    defer browser_bookmarks_mu.unlock();

    for (browser_bookmarks.items) |row| {
        if (std.ascii.eqlIgnoreCase(row.title, trimmed)) {
            const dup = try allocator.dupe(u8, row.url);
            return dup;
        }
        if (std.ascii.eqlIgnoreCase(row.url, trimmed)) {
            const dup = try allocator.dupe(u8, row.url);
            return dup;
        }
    }
    return null;
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

fn appendBrowserBookmarkCandidates(allocator: std.mem.Allocator, query: []const u8, out: *search.CandidateList) void {
    ensureBrowserBookmarksLoaded();

    browser_bookmarks_mu.lock();
    defer browser_bookmarks_mu.unlock();

    const needle = std.mem.trim(u8, query, " \t\r\n");
    for (browser_bookmarks.items) |row| {
        if (needle.len > 0 and
            !containsCaseInsensitive(row.title, needle) and
            !containsCaseInsensitive(row.url, needle) and
            !containsCaseInsensitive(row.subtitle, needle))
        {
            continue;
        }
        out.append(allocator, .{
            .kind = .web,
            .title = row.title,
            .subtitle = row.subtitle,
            .action = row.url,
            .icon = "bookmark-new-symbolic",
        }) catch return;
    }
}

fn containsCaseInsensitive(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn ensureBrowserBookmarksLoaded() void {
    browser_bookmarks_mu.lock();
    defer browser_bookmarks_mu.unlock();
    if (browser_bookmarks_loaded) return;
    browser_bookmarks_loaded = true;
    loadBrowserBookmarksLocked() catch |err| {
        std.log.warn("browser bookmarks load failed: {s}", .{@errorName(err)});
    };
}

fn loadBrowserBookmarksLocked() !void {
    const allocator = std.heap.page_allocator;
    const config_root = try configHomePath(allocator);
    defer allocator.free(config_root);
    const home_root = try homePath(allocator);
    defer allocator.free(home_root);

    const sources = [_]struct { browser: []const u8, rel: []const u8 }{
        .{ .browser = "Chromium", .rel = "chromium/Default/Bookmarks" },
        .{ .browser = "Chrome", .rel = "google-chrome/Default/Bookmarks" },
        .{ .browser = "Brave", .rel = "BraveSoftware/Brave-Browser/Default/Bookmarks" },
        .{ .browser = "Edge", .rel = "microsoft-edge/Default/Bookmarks" },
        .{ .browser = "Vivaldi", .rel = "vivaldi/Default/Bookmarks" },
    };

    for (sources) |source| {
        if (browser_bookmarks.items.len >= browser_bookmark_limit) break;
        const path = try std.fs.path.join(allocator, &.{ config_root, source.rel });
        defer allocator.free(path);

        const data = std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024 * 1024) catch continue;
        defer allocator.free(data);

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch continue;
        defer parsed.deinit();
        try collectChromiumBookmarksLocked(source.browser, parsed.value);
    }

    try loadFirefoxFamilyBookmarksFromRootLocked("Firefox", tryJoin(allocator, &.{ home_root, ".mozilla/firefox" }));
    try loadFirefoxFamilyBookmarksFromRootLocked("Zen", tryJoin(allocator, &.{ home_root, ".zen" }));
    try loadFirefoxFamilyBookmarksFromRootLocked("Firefox", tryJoin(allocator, &.{ home_root, ".var/app/org.mozilla.firefox/.mozilla/firefox" }));
    try loadFirefoxFamilyBookmarksFromRootLocked("Zen", tryJoin(allocator, &.{ home_root, ".var/app/app.zen_browser.zen/.zen" }));
}

fn configHomePath(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |xdg| {
        return xdg;
    } else |_| {}
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return std.fmt.allocPrint(allocator, "{s}/.config", .{home});
}

fn homePath(allocator: std.mem.Allocator) ![]u8 {
    return std.process.getEnvVarOwned(allocator, "HOME");
}

fn tryJoin(allocator: std.mem.Allocator, parts: []const []const u8) ?[]u8 {
    return std.fs.path.join(allocator, parts) catch null;
}

fn collectChromiumBookmarksLocked(browser_label: []const u8, value: std.json.Value) !void {
    if (browser_bookmarks.items.len >= browser_bookmark_limit) return;
    if (value != .object) return;

    if (value.object.get("type")) |type_val| {
        if (type_val == .string and std.mem.eql(u8, type_val.string, "url")) {
            const name_val = value.object.get("name") orelse return;
            const url_val = value.object.get("url") orelse return;
            if (name_val != .string or url_val != .string) return;
            const raw_title = std.mem.trim(u8, name_val.string, " \t\r\n");
            const title = if (raw_title.len > 0) raw_title else url_val.string;
            try appendBrowserBookmarkLocked(browser_label, title, url_val.string);
            return;
        }
    }

    if (value.object.get("children")) |children_val| {
        if (children_val == .array) {
            for (children_val.array.items) |child| {
                try collectChromiumBookmarksLocked(browser_label, child);
                if (browser_bookmarks.items.len >= browser_bookmark_limit) return;
            }
        }
    }

    if (value.object.get("roots")) |roots_val| {
        if (roots_val == .object) {
            var it = roots_val.object.iterator();
            while (it.next()) |entry| {
                try collectChromiumBookmarksLocked(browser_label, entry.value_ptr.*);
                if (browser_bookmarks.items.len >= browser_bookmark_limit) return;
            }
        }
    }
}

fn appendBrowserBookmarkLocked(browser_label: []const u8, title: []const u8, url: []const u8) !void {
    if (!looksLikeUrl(url)) return;
    if (browser_bookmarks.items.len >= browser_bookmark_limit) return;

    const kept_title = try keepBrowserBookmarkStringLocked(title);
    const kept_url = try keepBrowserBookmarkStringLocked(url);
    const subtitle = try std.fmt.allocPrint(std.heap.page_allocator, "{s} | {s}", .{ browser_label, url });
    const kept_subtitle = try keepBrowserBookmarkStringLocked(subtitle);
    std.heap.page_allocator.free(subtitle);

    try browser_bookmarks.append(std.heap.page_allocator, .{
        .title = kept_title,
        .url = kept_url,
        .subtitle = kept_subtitle,
    });
}

fn keepBrowserBookmarkStringLocked(value: []const u8) ![]const u8 {
    const copy = try std.heap.page_allocator.dupe(u8, value);
    try browser_bookmarks_owned.append(std.heap.page_allocator, copy);
    return copy;
}

fn loadFirefoxFamilyBookmarksFromRootLocked(browser_label: []const u8, maybe_root_path: ?[]u8) !void {
    const root_path = maybe_root_path orelse return;
    defer std.heap.page_allocator.free(root_path);
    if (browser_bookmarks.items.len >= browser_bookmark_limit) return;

    var root_dir = std.fs.openDirAbsolute(root_path, .{ .iterate = true }) catch return;
    defer root_dir.close();

    var it = root_dir.iterate();
    while (it.next() catch null) |entry| {
        if (browser_bookmarks.items.len >= browser_bookmark_limit) return;
        if (entry.kind != .directory) continue;

        const db_path = std.fs.path.join(std.heap.page_allocator, &.{ root_path, entry.name, "places.sqlite" }) catch continue;
        defer std.heap.page_allocator.free(db_path);
        loadFirefoxPlacesSqliteLocked(browser_label, db_path) catch {};
    }
}

fn loadFirefoxPlacesSqliteLocked(browser_label: []const u8, db_path: []const u8) !void {
    if (!sqlite3Available()) return;

    const sql =
        "SELECT COALESCE(NULLIF(moz_bookmarks.title,''), moz_places.url), moz_places.url " ++
        "FROM moz_bookmarks JOIN moz_places ON moz_bookmarks.fk = moz_places.id " ++
        "WHERE moz_bookmarks.type = 1 AND moz_places.url LIKE 'http%' LIMIT 10000;";
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "sqlite3", "-readonly", "-separator", "\t", db_path, sql },
        .max_output_bytes = 8 * 1024 * 1024,
    }) catch return;
    defer {
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
    }
    if (result.term != .Exited or result.term.Exited != 0) return;
    try parseSqliteBookmarkRowsLocked(browser_label, result.stdout);
}

fn sqlite3Available() bool {
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "sqlite3", "--version" },
        .max_output_bytes = 256,
    }) catch return false;
    defer {
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
    }
    return result.term == .Exited and result.term.Exited == 0;
}

fn parseSqliteBookmarkRowsLocked(browser_label: []const u8, rows: []const u8) !void {
    var lines = std.mem.splitScalar(u8, rows, '\n');
    while (lines.next()) |line| {
        if (browser_bookmarks.items.len >= browser_bookmark_limit) return;
        const row = std.mem.trimRight(u8, line, "\r");
        if (row.len == 0) continue;
        var fields = std.mem.splitScalar(u8, row, '\t');
        const title = std.mem.trim(u8, fields.next() orelse continue, " \t");
        const url = std.mem.trim(u8, fields.next() orelse continue, " \t");
        if (title.len == 0 or url.len == 0) continue;
        try appendBrowserBookmarkLocked(browser_label, title, url);
    }
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
