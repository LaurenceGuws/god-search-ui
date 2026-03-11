const std = @import("std");
const web_support = @import("web_support.zig");

const FaviconCacheEntry = struct {
    host: []const u8,
    path: []const u8,
};

pub const FetchStatus = enum {
    not_attempted,
    cache_hit,
    success,
    spawn_failed,
    curl_failed,
    empty_file,
    rename_failed,
};

pub const FaviconProbeReport = struct {
    path: ?[]const u8 = null,
    host: []const u8 = "",
    db: FetchStatus = .not_attempted,
    google: FetchStatus = .not_attempted,
    ico: FetchStatus = .not_attempted,
    apple: FetchStatus = .not_attempted,
};

var browser_favicon_url_mu: std.Thread.Mutex = .{};
var browser_favicon_url_cache: std.StringHashMapUnmanaged([]const u8) = .{};
var browser_favicon_url_owned: std.ArrayListUnmanaged([]u8) = .{};

var favicon_cache_mu: std.Thread.Mutex = .{};
var favicon_cache_entries: std.ArrayListUnmanaged(FaviconCacheEntry) = .{};
var favicon_cache_owned: std.ArrayListUnmanaged([]u8) = .{};

const favicon_url_cache_file_name = "favicon_urls.tsv";

pub fn invalidate() void {
    browser_favicon_url_mu.lock();
    clearBrowserFaviconUrlCacheLocked();
    browser_favicon_url_mu.unlock();

    favicon_cache_mu.lock();
    clearFaviconCacheLocked();
    favicon_cache_mu.unlock();
}

pub fn probePathWithReport(allocator: std.mem.Allocator, url: []const u8) FaviconProbeReport {
    var report = FaviconProbeReport{};
    const host = std.mem.trim(u8, urlHost(url), " \t\r\n");
    report.host = host;
    if (host.len == 0) return report;

    favicon_cache_mu.lock();
    if (faviconCacheGetLocked(host)) |cached| {
        favicon_cache_mu.unlock();
        report.path = cached;
        report.google = .cache_hit;
        return report;
    }
    favicon_cache_mu.unlock();

    const cache_dir = webFaviconCacheDir(allocator) catch return report;
    defer allocator.free(cache_dir);
    web_support.ensurePathExistsAbsolute(cache_dir) catch return report;

    const host_hash = std.hash.Wyhash.hash(0x7f11f9, host);
    const target = std.fmt.allocPrint(allocator, "{s}/{x}.png", .{ cache_dir, host_hash }) catch return report;
    defer allocator.free(target);

    if (web_support.fileExistsPath(target)) {
        favicon_cache_mu.lock();
        const cached = faviconCacheStoreLocked(host, target) catch null;
        favicon_cache_mu.unlock();
        if (cached) |path| {
            report.path = path;
            report.google = .cache_hit;
        }
        return report;
    }

    const tmp_target = std.fmt.allocPrint(allocator, "{s}.tmp", .{target}) catch return report;
    defer allocator.free(tmp_target);

    const google_url = std.fmt.allocPrint(allocator, "https://www.google.com/s2/favicons?domain={s}&sz=64", .{host}) catch return report;
    defer allocator.free(google_url);
    const ico_url = std.fmt.allocPrint(allocator, "https://{s}/favicon.ico", .{host}) catch return report;
    defer allocator.free(ico_url);
    const apple_url = std.fmt.allocPrint(allocator, "https://{s}/apple-touch-icon.png", .{host}) catch return report;
    defer allocator.free(apple_url);

    if (lookupBrowserStoredFaviconUrl(allocator, host)) |db_url| {
        defer allocator.free(db_url);
        report.db = fetchSmallFileToPath(allocator, db_url, tmp_target);
        if (report.db == .success) {
            const finalize = finalizeFetchedFavicon(tmp_target, target);
            if (finalize == .success) {
                report.path = storeFaviconCacheEntry(host, target);
                if (report.path != null) return report;
                report.db = .rename_failed;
            } else {
                report.db = finalize;
            }
        }
    }

    report.google = fetchSmallFileToPath(allocator, google_url, tmp_target);
    if (report.google == .success) {
        const finalize = finalizeFetchedFavicon(tmp_target, target);
        if (finalize == .success) {
            report.path = storeFaviconCacheEntry(host, target);
            if (report.path != null) return report;
            report.google = .rename_failed;
        } else {
            report.google = finalize;
        }
    }

    report.ico = fetchSmallFileToPath(allocator, ico_url, tmp_target);
    if (report.ico == .success) {
        const finalize = finalizeFetchedFavicon(tmp_target, target);
        if (finalize == .success) {
            report.path = storeFaviconCacheEntry(host, target);
            if (report.path != null) return report;
            report.ico = .rename_failed;
        } else {
            report.ico = finalize;
        }
    }

    report.apple = fetchSmallFileToPath(allocator, apple_url, tmp_target);
    if (report.apple == .success) {
        const finalize = finalizeFetchedFavicon(tmp_target, target);
        if (finalize == .success) {
            report.path = storeFaviconCacheEntry(host, target);
            if (report.path != null) return report;
            report.apple = .rename_failed;
        } else {
            report.apple = finalize;
        }
    }
    return report;
}

fn clearBrowserFaviconUrlCacheLocked() void {
    for (browser_favicon_url_owned.items) |item| std.heap.page_allocator.free(item);
    browser_favicon_url_owned.deinit(std.heap.page_allocator);
    browser_favicon_url_cache.deinit(std.heap.page_allocator);
    browser_favicon_url_owned = .{};
    browser_favicon_url_cache = .{};
}

fn clearFaviconCacheLocked() void {
    for (favicon_cache_owned.items) |item| std.heap.page_allocator.free(item);
    favicon_cache_entries.deinit(std.heap.page_allocator);
    favicon_cache_owned.deinit(std.heap.page_allocator);
    favicon_cache_entries = .{};
    favicon_cache_owned = .{};
}

fn lookupBrowserStoredFaviconUrl(allocator: std.mem.Allocator, host: []const u8) ?[]u8 {
    browser_favicon_url_mu.lock();
    if (browser_favicon_url_cache.get(host)) |cached| {
        browser_favicon_url_mu.unlock();
        if (cached.len == 0) return null;
        return allocator.dupe(u8, cached) catch null;
    }
    browser_favicon_url_mu.unlock();

    loadPersistedFaviconUrlCacheEntry(host);
    browser_favicon_url_mu.lock();
    if (browser_favicon_url_cache.get(host)) |cached| {
        browser_favicon_url_mu.unlock();
        if (cached.len == 0) return null;
        return allocator.dupe(u8, cached) catch null;
    }
    browser_favicon_url_mu.unlock();

    const found = resolveBrowserStoredFaviconUrlNoCache(allocator, host) catch null;

    browser_favicon_url_mu.lock();
    defer browser_favicon_url_mu.unlock();
    if (browser_favicon_url_cache.get(host)) |cached| {
        if (cached.len == 0) return null;
        return allocator.dupe(u8, cached) catch null;
    }
    const host_copy = std.heap.page_allocator.dupe(u8, host) catch return found;
    browser_favicon_url_owned.append(std.heap.page_allocator, host_copy) catch return found;

    if (found) |url| {
        const url_copy = std.heap.page_allocator.dupe(u8, url) catch {
            _ = browser_favicon_url_cache.put(std.heap.page_allocator, host_copy, "") catch {};
            return found;
        };
        browser_favicon_url_owned.append(std.heap.page_allocator, url_copy) catch {};
        _ = browser_favicon_url_cache.put(std.heap.page_allocator, host_copy, url_copy) catch {};
    } else {
        _ = browser_favicon_url_cache.put(std.heap.page_allocator, host_copy, "") catch {};
    }
    persistFaviconUrlCacheEntry(host, found) catch |err| {
        std.log.debug("web favicon url cache persist failed host={s} err={s}", .{ host, @errorName(err) });
    };
    return found;
}

fn resolveBrowserStoredFaviconUrlNoCache(allocator: std.mem.Allocator, host: []const u8) !?[]u8 {
    const home_root = try web_support.homePath(allocator);
    defer allocator.free(home_root);
    const roots = [_]?[]u8{
        web_support.tryJoin(allocator, &.{ home_root, ".mozilla/firefox" }),
        web_support.tryJoin(allocator, &.{ home_root, ".zen" }),
        web_support.tryJoin(allocator, &.{ home_root, ".var/app/org.mozilla.firefox/.mozilla/firefox" }),
        web_support.tryJoin(allocator, &.{ home_root, ".var/app/app.zen_browser.zen/.zen" }),
    };
    defer {
        for (roots) |root| if (root) |path| std.heap.page_allocator.free(path);
    }

    for (roots) |root_opt| {
        const root_path = root_opt orelse continue;
        const url = try queryFaviconsSqliteRootForHost(allocator, root_path, host);
        if (url) |resolved| return resolved;
    }
    return null;
}

fn queryFaviconsSqliteRootForHost(allocator: std.mem.Allocator, root_path: []const u8, host: []const u8) !?[]u8 {
    var root_dir = std.fs.openDirAbsolute(root_path, .{ .iterate = true }) catch return null;
    defer root_dir.close();

    var it = root_dir.iterate();
    while (it.next() catch null) |entry| {
        if (entry.kind != .directory) continue;
        const db_path = std.fs.path.join(allocator, &.{ root_path, entry.name, "favicons.sqlite" }) catch continue;
        defer allocator.free(db_path);
        if (!web_support.fileExistsPath(db_path)) continue;
        if (!web_support.sqliteHeaderLooksValid(db_path)) continue;

        const escaped_host = sqlLiteralEscape(allocator, host) catch continue;
        defer allocator.free(escaped_host);
        const sql = std.fmt.allocPrint(
            allocator,
            "SELECT i.icon_url FROM moz_pages_w_icons p JOIN moz_icons_to_pages ip ON ip.page_id = p.id JOIN moz_icons i ON i.id = ip.icon_id WHERE p.page_url LIKE '%{s}%' AND i.icon_url LIKE 'http%' LIMIT 1;",
            .{escaped_host},
        ) catch continue;
        defer allocator.free(sql);

        const db_uri = std.fmt.allocPrint(allocator, "file:{s}?immutable=1", .{db_path}) catch continue;
        defer allocator.free(db_uri);

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "sqlite3", "-readonly", db_uri, sql },
            .max_output_bytes = 16 * 1024,
        }) catch continue;
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        if (result.term != .Exited or result.term.Exited != 0) continue;
        const line = std.mem.trim(u8, result.stdout, " \t\r\n");
        if (line.len == 0) continue;
        return allocator.dupe(u8, line) catch null;
    }
    return null;
}

fn sqlLiteralEscape(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    for (value) |ch| {
        try out.append(allocator, ch);
        if (ch == '\'') try out.append(allocator, '\'');
    }
    return out.toOwnedSlice(allocator);
}

fn storeFaviconCacheEntry(host: []const u8, target: []const u8) ?[]const u8 {
    favicon_cache_mu.lock();
    const cached = faviconCacheStoreLocked(host, target) catch null;
    favicon_cache_mu.unlock();
    return cached;
}

fn finalizeFetchedFavicon(tmp_target: []const u8, target: []const u8) FetchStatus {
    const file = std.fs.openFileAbsolute(tmp_target, .{}) catch return .rename_failed;
    defer file.close();
    const stat = file.stat() catch return .rename_failed;
    if (stat.size == 0) {
        std.fs.deleteFileAbsolute(tmp_target) catch |err| {
            std.log.debug("web favicon cleanup failed path={s} err={s}", .{ tmp_target, @errorName(err) });
        };
        return .empty_file;
    }
    std.fs.renameAbsolute(tmp_target, target) catch {
        std.fs.deleteFileAbsolute(tmp_target) catch |err| {
            std.log.debug("web favicon cleanup failed path={s} err={s}", .{ tmp_target, @errorName(err) });
        };
        return .rename_failed;
    };
    return .success;
}

fn fetchSmallFileToPath(allocator: std.mem.Allocator, fetch_url: []const u8, target_path: []const u8) FetchStatus {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{
            "curl",
            "-fsSL",
            "--connect-timeout",
            "2",
            "--max-time",
            "3",
            "-A",
            "Mozilla/5.0",
            "-o",
            target_path,
            fetch_url,
        },
        .max_output_bytes = 256 * 1024,
    }) catch return .spawn_failed;
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);
    if (result.term != .Exited or result.term.Exited != 0) {
        if (web_support.fileExistsPath(target_path)) {
            std.fs.deleteFileAbsolute(target_path) catch |err| {
                std.log.debug("web favicon fetch cleanup failed path={s} err={s}", .{ target_path, @errorName(err) });
            };
        }
        return .curl_failed;
    }
    return .success;
}

fn faviconCacheGetLocked(host: []const u8) ?[]const u8 {
    for (favicon_cache_entries.items) |entry| {
        if (std.mem.eql(u8, entry.host, host)) return entry.path;
    }
    return null;
}

fn faviconCacheStoreLocked(host: []const u8, path: []const u8) ![]const u8 {
    if (faviconCacheGetLocked(host)) |existing| return existing;
    const host_copy = try std.heap.page_allocator.dupe(u8, host);
    errdefer std.heap.page_allocator.free(host_copy);
    const path_copy = try std.heap.page_allocator.dupe(u8, path);
    errdefer std.heap.page_allocator.free(path_copy);
    try favicon_cache_owned.append(std.heap.page_allocator, host_copy);
    errdefer _ = favicon_cache_owned.pop();
    try favicon_cache_owned.append(std.heap.page_allocator, path_copy);
    errdefer _ = favicon_cache_owned.pop();
    try favicon_cache_entries.append(std.heap.page_allocator, .{
        .host = host_copy,
        .path = path_copy,
    });
    return path_copy;
}

fn webFaviconCacheDir(allocator: std.mem.Allocator) ![]u8 {
    const dir = try web_support.webCacheDir(allocator);
    defer allocator.free(dir);
    return std.fs.path.join(allocator, &.{ dir, "favicons" });
}

fn loadPersistedFaviconUrlCacheEntry(host: []const u8) void {
    const allocator = std.heap.page_allocator;
    const path = web_support.webCacheFilePath(allocator, favicon_url_cache_file_name) catch return;
    defer allocator.free(path);
    const data = web_support.readFileAbsoluteAllocCompat(allocator, path, 2 * 1024 * 1024) catch return;
    defer allocator.free(data);
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trimRight(u8, line_raw, "\r");
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        const entry_host = fields.next() orelse continue;
        const entry_url = fields.next() orelse "";
        if (!std.mem.eql(u8, entry_host, host)) continue;
        browser_favicon_url_mu.lock();
        defer browser_favicon_url_mu.unlock();
        if (browser_favicon_url_cache.get(host) != null) return;
        const host_copy = std.heap.page_allocator.dupe(u8, entry_host) catch return;
        browser_favicon_url_owned.append(std.heap.page_allocator, host_copy) catch return;
        const url_copy = std.heap.page_allocator.dupe(u8, entry_url) catch {
            _ = browser_favicon_url_cache.put(std.heap.page_allocator, host_copy, "") catch {};
            return;
        };
        browser_favicon_url_owned.append(std.heap.page_allocator, url_copy) catch {};
        _ = browser_favicon_url_cache.put(std.heap.page_allocator, host_copy, url_copy) catch {};
        return;
    }
}

fn persistFaviconUrlCacheEntry(host: []const u8, found: ?[]u8) !void {
    const allocator = std.heap.page_allocator;
    const path = try web_support.webCacheFilePath(allocator, favicon_url_cache_file_name);
    defer allocator.free(path);
    const existing = web_support.readFileAbsoluteAllocCompat(allocator, path, 2 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => try allocator.dupe(u8, ""),
        else => return err,
    };
    defer allocator.free(existing);
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);
    var lines = std.mem.splitScalar(u8, existing, '\n');
    var replaced = false;
    while (lines.next()) |line_raw| {
        const line = std.mem.trimRight(u8, line_raw, "\r");
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        const entry_host = fields.next() orelse continue;
        if (std.mem.eql(u8, entry_host, host)) {
            try buf.writer(allocator).print("{s}\t{s}\n", .{ host, found orelse "" });
            replaced = true;
        } else {
            try buf.writer(allocator).print("{s}\n", .{line});
        }
    }
    if (!replaced) {
        try buf.writer(allocator).print("{s}\t{s}\n", .{ host, found orelse "" });
    }
    try web_support.writeFileAtomicAbsolute(path, buf.items);
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
