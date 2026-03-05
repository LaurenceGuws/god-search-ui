const std = @import("std");
const search = @import("../search/mod.zig");

pub const AppsProvider = struct {
    cache_path: []const u8,
    owned_strings_current: std.ArrayListUnmanaged([]u8) = .{},
    owned_strings_previous: std.ArrayListUnmanaged([]u8) = .{},
    had_runtime_failure: bool = false,

    pub fn init(cache_path: []const u8) AppsProvider {
        return .{
            .cache_path = cache_path,
        };
    }

    pub fn deinit(self: *AppsProvider, allocator: std.mem.Allocator) void {
        self.freeOwnedStrings(allocator, &self.owned_strings_current);
        self.freeOwnedStrings(allocator, &self.owned_strings_previous);
        self.owned_strings_current.deinit(allocator);
        self.owned_strings_previous.deinit(allocator);
    }

    pub fn provider(self: *AppsProvider) search.Provider {
        return .{
            .name = "apps",
            .context = self,
            .vtable = &.{
                .collect = collect,
                .health = health,
            },
        };
    }

    fn collect(context: *anyopaque, allocator: std.mem.Allocator, out: *search.CandidateList) !void {
        const self: *AppsProvider = @ptrCast(@alignCast(context));
        self.rotateOwnedStringsForCollect(allocator);
        const data = std.fs.cwd().readFileAlloc(allocator, self.cache_path, 2 * 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => {
                const count = self.collectFromDesktopFiles(allocator, out) catch |scan_err| {
                    self.had_runtime_failure = true;
                    std.log.warn("apps provider desktop scan failed: {s}", .{@errorName(scan_err)});
                    return;
                };
                if (count == 0) {
                    self.had_runtime_failure = true;
                    return;
                }
                self.had_runtime_failure = false;
                return;
            },
            else => {
                self.had_runtime_failure = true;
                std.log.warn("apps provider cache read failed: {s}", .{@errorName(err)});
                return;
            },
        };
        defer allocator.free(data);

        var count: usize = 0;
        var lines = std.mem.splitScalar(u8, data, '\n');
        while (lines.next()) |line| {
            const normalized_line = std.mem.trimRight(u8, line, "\r");
            if (normalized_line.len == 0) continue;
            var fields = std.mem.splitScalar(u8, normalized_line, '\t');
            const category = std.mem.trimRight(u8, fields.next() orelse continue, " \t\r");
            const name = std.mem.trimRight(u8, fields.next() orelse continue, " \t\r");
            const exec_cmd = std.mem.trimRight(u8, fields.next() orelse continue, " \t\r");
            const icon_name = std.mem.trimRight(u8, fields.next() orelse "", " \t\r");

            const kept_name = try self.keepString(allocator, name);
            const kept_category = try self.keepString(allocator, category);
            const kept_exec = try self.keepString(allocator, exec_cmd);
            const kept_icon = try self.keepString(allocator, icon_name);
            try out.append(allocator, search.Candidate.initWithIcon(.app, kept_name, kept_category, kept_exec, kept_icon));
            count += 1;
        }

        if (count == 0) {
            self.had_runtime_failure = true;
            std.log.warn("apps provider cache contained no parsable rows path={s}", .{self.cache_path});
            return;
        }
        self.had_runtime_failure = false;
    }

    fn health(context: *anyopaque) search.ProviderHealth {
        const self: *AppsProvider = @ptrCast(@alignCast(context));
        std.fs.cwd().access(self.cache_path, .{}) catch return .degraded;
        if (self.had_runtime_failure) return .degraded;
        return .ready;
    }

    fn keepString(self: *AppsProvider, allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        const copy = try allocator.dupe(u8, value);
        try self.owned_strings_current.append(allocator, copy);
        return copy;
    }

    fn rotateOwnedStringsForCollect(self: *AppsProvider, allocator: std.mem.Allocator) void {
        self.freeOwnedStrings(allocator, &self.owned_strings_previous);
        std.mem.swap(
            std.ArrayListUnmanaged([]u8),
            &self.owned_strings_current,
            &self.owned_strings_previous,
        );
        self.owned_strings_current.clearRetainingCapacity();
    }

    fn freeOwnedStrings(self: *AppsProvider, allocator: std.mem.Allocator, strings: *std.ArrayListUnmanaged([]u8)) void {
        _ = self;
        for (strings.items) |item| allocator.free(item);
        strings.clearRetainingCapacity();
    }

    fn collectFromDesktopFiles(self: *AppsProvider, allocator: std.mem.Allocator, out: *search.CandidateList) !usize {
        const start_len = out.items.len;
        var scan = DesktopScanState{};
        defer scan.deinit(allocator);
        var roots = try desktopSearchRoots(allocator);
        defer {
            for (roots.items) |item| allocator.free(item);
            roots.deinit(allocator);
        }
        for (roots.items) |root| {
            self.collectFromDesktopRoot(allocator, out, &scan, root) catch |err| switch (err) {
                error.FileNotFound, error.NotDir, error.AccessDenied => continue,
                else => return err,
            };
        }
        const added = out.items.len - start_len;
        if (added > 0) {
            writeAppCacheFromCandidates(self.cache_path, out.items[start_len..]) catch |err| {
                std.log.warn("apps provider failed to rebuild cache '{s}': {s}", .{ self.cache_path, @errorName(err) });
            };
        }
        return added;
    }

    fn collectFromDesktopRoot(
        self: *AppsProvider,
        allocator: std.mem.Allocator,
        out: *search.CandidateList,
        scan: *DesktopScanState,
        root_path: []const u8,
    ) !void {
        var dir = try std.fs.openDirAbsolute(root_path, .{ .iterate = true });
        defer dir.close();

        var walker = try dir.walk(allocator);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.path, ".desktop")) continue;
            if (entry.path.len >= 512) continue;
            const data = entry.dir.readFileAlloc(allocator, entry.basename, 128 * 1024) catch continue;
            defer allocator.free(data);
            const parsed = parseDesktopEntry(data) orelse continue;
            if (parsed.hidden or parsed.no_display) continue;
            if (parsed.exec_cmd.len == 0 or parsed.name.len == 0) continue;

            const exec_norm = try normalizeDesktopExecAlloc(allocator, parsed.exec_cmd);
            defer allocator.free(exec_norm);
            if (exec_norm.len == 0) continue;

            const is_new = scan.seenExec(allocator, exec_norm) catch continue;
            if (!is_new) continue;

            const category = firstDesktopCategory(parsed.categories) orelse "Applications";
            const kept_name = try self.keepString(allocator, parsed.name);
            const kept_category = try self.keepString(allocator, category);
            const kept_exec = try self.keepString(allocator, exec_norm);
            const kept_icon = try self.keepString(allocator, parsed.icon);
            try out.append(allocator, search.Candidate.initWithIcon(.app, kept_name, kept_category, kept_exec, kept_icon));
        }
    }
};

const DesktopScanState = struct {
    seen_execs: std.StringHashMapUnmanaged(void) = .{},

    fn seenExec(self: *DesktopScanState, allocator: std.mem.Allocator, exec_cmd: []const u8) !bool {
        const gop = try self.seen_execs.getOrPut(allocator, exec_cmd);
        if (gop.found_existing) return false;
        gop.key_ptr.* = try allocator.dupe(u8, exec_cmd);
        return true;
    }

    fn deinit(self: *DesktopScanState, allocator: std.mem.Allocator) void {
        var it = self.seen_execs.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        self.seen_execs.deinit(allocator);
    }
};

const ParsedDesktopEntry = struct {
    name: []const u8 = "",
    exec_cmd: []const u8 = "",
    icon: []const u8 = "",
    categories: []const u8 = "",
    hidden: bool = false,
    no_display: bool = false,
};

fn parseDesktopEntry(data: []const u8) ?ParsedDesktopEntry {
    var in_entry = false;
    var parsed = ParsedDesktopEntry{};
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, std.mem.trimRight(u8, raw_line, "\r"), " \t");
        if (line.len == 0 or line[0] == '#') continue;
        if (line[0] == '[' and line[line.len - 1] == ']') {
            in_entry = std.mem.eql(u8, line, "[Desktop Entry]");
            continue;
        }
        if (!in_entry) continue;
        const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq_idx], " \t");
        const value = std.mem.trim(u8, line[eq_idx + 1 ..], " \t");
        if (std.mem.eql(u8, key, "Type")) {
            if (!std.ascii.eqlIgnoreCase(value, "Application")) return null;
        } else if (std.mem.eql(u8, key, "NoDisplay")) {
            parsed.no_display = parseDesktopBool(value);
        } else if (std.mem.eql(u8, key, "Hidden")) {
            parsed.hidden = parseDesktopBool(value);
        } else if (std.mem.eql(u8, key, "Name")) {
            if (parsed.name.len == 0) parsed.name = value;
        } else if (std.mem.eql(u8, key, "Exec")) {
            if (parsed.exec_cmd.len == 0) parsed.exec_cmd = value;
        } else if (std.mem.eql(u8, key, "Icon")) {
            if (parsed.icon.len == 0) parsed.icon = value;
        } else if (std.mem.eql(u8, key, "Categories")) {
            if (parsed.categories.len == 0) parsed.categories = value;
        }
    }
    if (parsed.name.len == 0 or parsed.exec_cmd.len == 0) return null;
    return parsed;
}

fn parseDesktopBool(value: []const u8) bool {
    return std.ascii.eqlIgnoreCase(std.mem.trim(u8, value, " \t"), "true") or std.mem.eql(u8, std.mem.trim(u8, value, " \t"), "1");
}

fn firstDesktopCategory(categories: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, categories, ';');
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t");
        if (trimmed.len > 0) return trimmed;
    }
    return null;
}

fn normalizeDesktopExecAlloc(allocator: std.mem.Allocator, exec_cmd: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var i: usize = 0;
    var in_single = false;
    var in_double = false;
    while (i < exec_cmd.len) : (i += 1) {
        const ch = exec_cmd[i];
        if (!in_double and ch == '\'') {
            in_single = !in_single;
            try out.append(allocator, ch);
            continue;
        }
        if (!in_single and ch == '"') {
            in_double = !in_double;
            try out.append(allocator, ch);
            continue;
        }
        if (ch == '%' and i + 1 < exec_cmd.len) {
            const code = exec_cmd[i + 1];
            if (std.ascii.isAlphabetic(code) or code == '%') {
                i += 1;
                while (out.items.len > 0 and out.items[out.items.len - 1] == ' ') _ = out.pop();
                continue;
            }
        }
        try out.append(allocator, ch);
    }

    const trimmed = std.mem.trim(u8, out.items, " \t");
    return allocator.dupe(u8, trimmed);
}

fn desktopSearchRoots(allocator: std.mem.Allocator) !std.ArrayList([]u8) {
    var roots = std.ArrayList([]u8).empty;
    errdefer {
        for (roots.items) |item| allocator.free(item);
        roots.deinit(allocator);
    }

    const home = std.process.getEnvVarOwned(allocator, "HOME") catch null;
    defer if (home) |h| allocator.free(h);
    const xdg_data_home = std.process.getEnvVarOwned(allocator, "XDG_DATA_HOME") catch null;
    defer if (xdg_data_home) |x| allocator.free(x);
    const xdg_data_dirs = std.process.getEnvVarOwned(allocator, "XDG_DATA_DIRS") catch null;
    defer if (xdg_data_dirs) |x| allocator.free(x);

    if (xdg_data_home) |x| {
        try roots.append(allocator, try std.fmt.allocPrint(allocator, "{s}/applications", .{x}));
    } else if (home) |h| {
        try roots.append(allocator, try std.fmt.allocPrint(allocator, "{s}/.local/share/applications", .{h}));
    }

    if (xdg_data_dirs) |dirs| {
        var it = std.mem.splitScalar(u8, dirs, ':');
        while (it.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (trimmed.len == 0) continue;
            try roots.append(allocator, try std.fmt.allocPrint(allocator, "{s}/applications", .{trimmed}));
        }
    } else {
        try roots.append(allocator, try allocator.dupe(u8, "/usr/local/share/applications"));
        try roots.append(allocator, try allocator.dupe(u8, "/usr/share/applications"));
    }

    return roots;
}

fn writeAppCacheFromCandidates(cache_path: []const u8, rows: []const search.Candidate) !void {
    if (rows.len == 0) return;
    const parent = std.fs.path.dirname(cache_path) orelse return;
    if (std.fs.path.isAbsolute(parent)) {
        try std.fs.makeDirAbsolute(parent);
    } else {
        try std.fs.cwd().makePath(parent);
    }

    var file = if (std.fs.path.isAbsolute(cache_path))
        try std.fs.createFileAbsolute(cache_path, .{ .truncate = true })
    else
        try std.fs.cwd().createFile(cache_path, .{ .truncate = true });
    defer file.close();

    var writer = file.writer(&.{});
    for (rows) |row| {
        if (row.kind != .app) continue;
        try writer.interface.print("{s}\t{s}\t{s}\t{s}\n", .{ row.subtitle, row.title, row.action, row.icon });
    }
    try file.sync();
}

test "apps provider collects rows from cache file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "apps.tsv",
        .data =
        \\Utilities\tKitty\tkitty\tkitty
        \\Internet\tFirefox\tfirefox\tfirefox
        \\
        ,
    });

    const cache_path = try tmp.dir.realpathAlloc(std.testing.allocator, "apps.tsv");
    defer std.testing.allocator.free(cache_path);

    var apps = AppsProvider.init(cache_path);
    defer apps.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = apps.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(search.ProviderHealth.ready, provider.health());
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqualStrings("Kitty", list.items[0].title);
    try std.testing.expectEqualStrings("Utilities", list.items[0].subtitle);
    try std.testing.expectEqualStrings("kitty", list.items[0].action);
    try std.testing.expectEqualStrings("kitty", list.items[0].icon);
}

test "apps provider accepts legacy three-column rows with empty icon metadata" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "apps.tsv",
        .data =
        \\Utilities\tKitty\tkitty
        \\Internet\tFirefox\tfirefox\tfirefox
        \\
        ,
    });

    const cache_path = try tmp.dir.realpathAlloc(std.testing.allocator, "apps.tsv");
    defer std.testing.allocator.free(cache_path);

    var apps = AppsProvider.init(cache_path);
    defer apps.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = apps.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqualStrings("Kitty", list.items[0].title);
    try std.testing.expectEqualStrings("", list.items[0].icon);
    try std.testing.expectEqualStrings("firefox", list.items[1].icon);
}

test "apps provider falls back when cache is missing" {
    var apps = AppsProvider.init("/tmp/non-existent-app-cache.tsv");
    defer apps.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = apps.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(search.ProviderHealth.degraded, provider.health());
    try std.testing.expectEqual(@as(usize, 0), list.items.len);
}

test "apps provider degrades when cache exists but no valid rows are parsed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "apps.tsv",
        .data =
        \\bad row
        \\still bad
        \\
        ,
    });

    const cache_path = try tmp.dir.realpathAlloc(std.testing.allocator, "apps.tsv");
    defer std.testing.allocator.free(cache_path);

    var apps = AppsProvider.init(cache_path);
    defer apps.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = apps.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(@as(usize, 0), list.items.len);
    try std.testing.expectEqual(search.ProviderHealth.degraded, provider.health());
}

test "apps provider rotates owned strings across collects with bounded growth" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "apps.tsv",
        .data =
        \\Utilities\tKitty\tkitty\tkitty
        \\Internet\tFirefox\tfirefox\tfirefox
        \\
        ,
    });

    const cache_path = try tmp.dir.realpathAlloc(std.testing.allocator, "apps.tsv");
    defer std.testing.allocator.free(cache_path);

    var apps = AppsProvider.init(cache_path);
    defer apps.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = apps.provider();
    try provider.collect(std.testing.allocator, &list);
    const first_total = apps.owned_strings_current.items.len + apps.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 8), first_total);

    list.clearRetainingCapacity();
    try provider.collect(std.testing.allocator, &list);
    const second_total = apps.owned_strings_current.items.len + apps.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 16), second_total);

    list.clearRetainingCapacity();
    try provider.collect(std.testing.allocator, &list);
    const third_total = apps.owned_strings_current.items.len + apps.owned_strings_previous.items.len;
    try std.testing.expectEqual(@as(usize, 16), third_total);
}

test "apps provider trims crlf and trailing whitespace from stored fields" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "apps.tsv",
        .data =
        \\Utilities  \tKitty\tkitty  \tkitty  \r
        \\Internet\tFirefox\tfirefox\r
        \\
        ,
    });

    const cache_path = try tmp.dir.realpathAlloc(std.testing.allocator, "apps.tsv");
    defer std.testing.allocator.free(cache_path);

    var apps = AppsProvider.init(cache_path);
    defer apps.deinit(std.testing.allocator);

    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);

    const provider = apps.provider();
    try provider.collect(std.testing.allocator, &list);

    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    try std.testing.expectEqualStrings("Utilities", list.items[0].subtitle);
    try std.testing.expectEqualStrings("kitty", list.items[0].action);
    try std.testing.expectEqualStrings("kitty", list.items[0].icon);
    try std.testing.expectEqualStrings("firefox", list.items[1].action);
}

test "desktop entry parser extracts app metadata and strips exec field codes" {
    const data =
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Zen Browser
        \\Exec=/usr/bin/zen-browser --new-window %U
        \\Icon=zen-browser
        \\Categories=Network;WebBrowser;
        \\
    ;
    const parsed = parseDesktopEntry(data) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("Zen Browser", parsed.name);
    try std.testing.expectEqualStrings("/usr/bin/zen-browser --new-window %U", parsed.exec_cmd);
    try std.testing.expectEqualStrings("zen-browser", parsed.icon);
    try std.testing.expectEqualStrings("Network", firstDesktopCategory(parsed.categories).?);

    const normalized = try normalizeDesktopExecAlloc(std.testing.allocator, parsed.exec_cmd);
    defer std.testing.allocator.free(normalized);
    try std.testing.expectEqualStrings("/usr/bin/zen-browser --new-window", normalized);
}

test "apps provider can scan desktop root and rebuild cache rows" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("apps/sub");
    try tmp.dir.writeFile(.{
        .sub_path = "apps/sub/test.desktop",
        .data =
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Test App
        \\Exec=test-app %F
        \\Icon=test-icon
        \\Categories=Utility;
        \\
        ,
    });

    const root_path = try tmp.dir.realpathAlloc(std.testing.allocator, "apps");
    defer std.testing.allocator.free(root_path);
    const cache_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(cache_path);
    const cache_file = try std.fmt.allocPrint(std.testing.allocator, "{s}/wofi-app-launcher.tsv", .{cache_path});
    defer std.testing.allocator.free(cache_file);

    var apps = AppsProvider.init(cache_file);
    defer apps.deinit(std.testing.allocator);
    var list = search.CandidateList.empty;
    defer list.deinit(std.testing.allocator);
    var scan = DesktopScanState{};
    defer scan.deinit(std.testing.allocator);

    try apps.collectFromDesktopRoot(std.testing.allocator, &list, &scan, root_path);
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    try std.testing.expectEqualStrings("Test App", list.items[0].title);
    try std.testing.expectEqualStrings("Utility", list.items[0].subtitle);
    try std.testing.expectEqualStrings("test-app", list.items[0].action);

    try writeAppCacheFromCandidates(cache_file, list.items);
    const written = try std.fs.cwd().readFileAlloc(std.testing.allocator, cache_file, 4096);
    defer std.testing.allocator.free(written);
    try std.testing.expect(std.mem.indexOf(u8, written, "Utility\tTest App\ttest-app\ttest-icon\n") != null);
}
