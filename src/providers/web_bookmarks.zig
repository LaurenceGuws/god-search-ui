const std = @import("std");
const search = @import("../search/mod.zig");
const web_support = @import("web_support.zig");

const BrowserBookmark = struct {
    title: []const u8,
    url: []const u8,
    subtitle: []const u8,
};

var browser_bookmarks_mu: std.Thread.Mutex = .{};
var browser_bookmarks_loaded: bool = false;
var browser_bookmarks: std.ArrayListUnmanaged(BrowserBookmark) = .{};
var browser_bookmarks_owned: std.ArrayListUnmanaged([]u8) = .{};
const browser_bookmark_limit: usize = 20_000;
const bookmark_cache_file_name = "bookmarks.tsv";

pub fn invalidate() void {
    browser_bookmarks_mu.lock();
    defer browser_bookmarks_mu.unlock();
    clearBrowserBookmarksLocked();
    browser_bookmarks_loaded = false;
}

pub fn resolveUrl(allocator: std.mem.Allocator, query: []const u8) !?[]u8 {
    const trimmed = std.mem.trim(u8, query, " \t\r\n");
    if (trimmed.len == 0) return null;

    ensureLoaded();
    browser_bookmarks_mu.lock();
    defer browser_bookmarks_mu.unlock();

    for (browser_bookmarks.items) |row| {
        if (std.ascii.eqlIgnoreCase(row.title, trimmed) or std.ascii.eqlIgnoreCase(row.url, trimmed)) {
            return try allocator.dupe(u8, row.url);
        }
    }
    return null;
}

pub fn appendCandidates(
    allocator: std.mem.Allocator,
    query: []const u8,
    out: *search.CandidateList,
    bookmark_favicon_probe_limit: usize,
    probe_icon: *const fn (std.mem.Allocator, []const u8) ?[]const u8,
) void {
    ensureLoaded();

    var matched = std.ArrayList(BrowserBookmark).empty;
    defer matched.deinit(allocator);

    browser_bookmarks_mu.lock();
    const needle = std.mem.trim(u8, query, " \t\r\n");
    for (browser_bookmarks.items) |row| {
        if (needle.len > 0 and
            !containsCaseInsensitive(row.title, needle) and
            !containsCaseInsensitive(row.url, needle) and
            !containsCaseInsensitive(row.subtitle, needle))
        {
            continue;
        }
        matched.append(allocator, row) catch {
            browser_bookmarks_mu.unlock();
            return;
        };
    }
    browser_bookmarks_mu.unlock();

    var favicon_probed: usize = 0;
    for (matched.items) |row| {
        const icon_value = if (favicon_probed < bookmark_favicon_probe_limit) blk: {
            favicon_probed += 1;
            if (probe_icon(allocator, row.url)) |path| break :blk path;
            break :blk "bookmark-new-symbolic";
        } else "bookmark-new-symbolic";
        out.append(allocator, .{
            .kind = .web,
            .title = row.title,
            .subtitle = row.subtitle,
            .action = row.url,
            .icon = icon_value,
        }) catch return;
    }
}

fn ensureLoaded() void {
    browser_bookmarks_mu.lock();
    defer browser_bookmarks_mu.unlock();
    if (browser_bookmarks_loaded) return;
    browser_bookmarks_loaded = true;
    loadPersistedLocked() catch |err| {
        std.log.debug("browser bookmarks persisted load skipped: {s}", .{@errorName(err)});
    };
    if (browser_bookmarks.items.len > 0) return;
    loadBrowserBookmarksLocked() catch |err| {
        std.log.warn("browser bookmarks load failed: {s}", .{@errorName(err)});
    };
}

fn clearBrowserBookmarksLocked() void {
    for (browser_bookmarks_owned.items) |item| std.heap.page_allocator.free(item);
    browser_bookmarks_owned.deinit(std.heap.page_allocator);
    browser_bookmarks.deinit(std.heap.page_allocator);
    browser_bookmarks_owned = .{};
    browser_bookmarks = .{};
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

fn loadBrowserBookmarksLocked() !void {
    const allocator = std.heap.page_allocator;
    const config_root = try web_support.configHomePath(allocator);
    defer allocator.free(config_root);
    const home_root = try web_support.homePath(allocator);
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
        const data = std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => {
                std.log.warn("web bookmarks read failed browser={s} path={s} err={s}", .{ source.browser, path, @errorName(err) });
                continue;
            },
        };
        defer allocator.free(data);
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch |err| {
            std.log.warn("web bookmarks parse failed browser={s} path={s} err={s}", .{ source.browser, path, @errorName(err) });
            continue;
        };
        defer parsed.deinit();
        try collectChromiumBookmarksLocked(source.browser, parsed.value);
    }

    try loadFirefoxFamilyBookmarksFromRootLocked("Firefox", web_support.tryJoin(allocator, &.{ home_root, ".mozilla/firefox" }));
    try loadFirefoxFamilyBookmarksFromRootLocked("Zen", web_support.tryJoin(allocator, &.{ home_root, ".zen" }));
    try loadFirefoxFamilyBookmarksFromRootLocked("Firefox", web_support.tryJoin(allocator, &.{ home_root, ".var/app/org.mozilla.firefox/.mozilla/firefox" }));
    try loadFirefoxFamilyBookmarksFromRootLocked("Zen", web_support.tryJoin(allocator, &.{ home_root, ".var/app/app.zen_browser.zen/.zen" }));
    if (browser_bookmarks.items.len > 0) {
        persistLocked() catch |err| std.log.warn("browser bookmarks persist failed: {s}", .{@errorName(err)});
    }
}

fn loadPersistedLocked() !void {
    const allocator = std.heap.page_allocator;
    const path = try web_support.webCacheFilePath(allocator, bookmark_cache_file_name);
    defer allocator.free(path);
    const data = web_support.readFileAbsoluteAllocCompat(allocator, path, 16 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer allocator.free(data);
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line_raw| {
        if (browser_bookmarks.items.len >= browser_bookmark_limit) return;
        const line = std.mem.trimRight(u8, line_raw, "\r");
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        const title = fields.next() orelse continue;
        const url = fields.next() orelse continue;
        const subtitle = fields.next() orelse continue;
        try appendPersistedLocked(title, url, subtitle);
    }
}

fn appendPersistedLocked(title: []const u8, url: []const u8, subtitle: []const u8) !void {
    if (!web_support.looksLikeUrl(url)) return;
    const kept_title = try keepStringLocked(title);
    const kept_url = try keepStringLocked(url);
    const kept_subtitle = try keepStringLocked(subtitle);
    try browser_bookmarks.append(std.heap.page_allocator, .{ .title = kept_title, .url = kept_url, .subtitle = kept_subtitle });
}

fn persistLocked() !void {
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(std.heap.page_allocator);
    for (browser_bookmarks.items) |row| {
        try buf.writer(std.heap.page_allocator).print("{s}\t{s}\t{s}\n", .{ row.title, row.url, row.subtitle });
    }
    const path = try web_support.webCacheFilePath(std.heap.page_allocator, bookmark_cache_file_name);
    defer std.heap.page_allocator.free(path);
    try web_support.writeFileAtomicAbsolute(path, buf.items);
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
    if (value.object.get("children")) |children_val| if (children_val == .array) {
        for (children_val.array.items) |child| {
            try collectChromiumBookmarksLocked(browser_label, child);
            if (browser_bookmarks.items.len >= browser_bookmark_limit) return;
        }
    };
    if (value.object.get("roots")) |roots_val| if (roots_val == .object) {
        var it = roots_val.object.iterator();
        while (it.next()) |entry| {
            try collectChromiumBookmarksLocked(browser_label, entry.value_ptr.*);
            if (browser_bookmarks.items.len >= browser_bookmark_limit) return;
        }
    };
}

fn appendBrowserBookmarkLocked(browser_label: []const u8, title: []const u8, url: []const u8) !void {
    if (!web_support.looksLikeUrl(url) or browser_bookmarks.items.len >= browser_bookmark_limit) return;
    const kept_title = try keepStringLocked(title);
    const kept_url = try keepStringLocked(url);
    const subtitle = try std.fmt.allocPrint(std.heap.page_allocator, "{s} | {s}", .{ browser_label, url });
    const kept_subtitle = try keepStringLocked(subtitle);
    std.heap.page_allocator.free(subtitle);
    try browser_bookmarks.append(std.heap.page_allocator, .{ .title = kept_title, .url = kept_url, .subtitle = kept_subtitle });
}

fn keepStringLocked(value: []const u8) ![]const u8 {
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
        if (!web_support.fileExistsPath(db_path) or !web_support.sqliteHeaderLooksValid(db_path)) continue;
        loadFirefoxPlacesSqliteLocked(browser_label, db_path) catch |err| {
            std.log.warn("web bookmarks sqlite load failed browser={s} path={s} err={s}", .{ browser_label, db_path, @errorName(err) });
        };
    }
}

fn loadFirefoxPlacesSqliteLocked(browser_label: []const u8, db_path: []const u8) !void {
    if (!web_support.sqlite3Available()) return;
    const db_uri = std.fmt.allocPrint(std.heap.page_allocator, "file:{s}?immutable=1", .{db_path}) catch return;
    defer std.heap.page_allocator.free(db_uri);
    const sql =
        "SELECT COALESCE(NULLIF(moz_bookmarks.title,''), moz_places.url), moz_places.url " ++
        "FROM moz_bookmarks JOIN moz_places ON moz_bookmarks.fk = moz_places.id " ++
        "WHERE moz_bookmarks.type = 1 AND moz_places.url LIKE 'http%' LIMIT 10000;";
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "sqlite3", "-readonly", "-separator", "\t", db_uri, sql },
        .max_output_bytes = 8 * 1024 * 1024,
    }) catch |err| {
        std.log.warn("web bookmarks sqlite spawn failed path={s} err={s}", .{ db_path, @errorName(err) });
        return;
    };
    defer {
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
    }
    if (result.term != .Exited or result.term.Exited != 0) return;
    try parseSqliteBookmarkRowsLocked(browser_label, result.stdout);
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
