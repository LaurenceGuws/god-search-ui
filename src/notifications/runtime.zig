const std = @import("std");
const search = @import("../search/mod.zig");

const max_entries: usize = 256;

const Entry = struct {
    id: u32,
    app_name: []u8,
    app_icon: []u8,
    summary: []u8,
    body: []u8,
    urgency: u8,
    transient: bool,
    active: bool,
    closed_reason: u32,
    created_ns: i128,
    updated_ns: i128,
};

pub const Snapshot = struct {
    id: u32,
    app_name: []u8,
    app_icon: []u8,
    summary: []u8,
    body: []u8,
    urgency: u8,
    transient: bool,
    active: bool,
    closed_reason: u32,
    created_ns: i128,
    updated_ns: i128,
};

const Runtime = struct {
    mu: std.Thread.Mutex = .{},
    entries: std.ArrayListUnmanaged(Entry) = .{},
    close_ctx: ?*anyopaque = null,
    close_fn: ?*const fn (*anyopaque, u32) bool = null,
};

var runtime: Runtime = .{};

pub fn registerCloser(ctx: *anyopaque, close_fn: *const fn (*anyopaque, u32) bool) void {
    runtime.mu.lock();
    defer runtime.mu.unlock();
    runtime.close_ctx = ctx;
    runtime.close_fn = close_fn;
}

pub fn clearCloser(ctx: *anyopaque) void {
    runtime.mu.lock();
    defer runtime.mu.unlock();
    if (runtime.close_ctx == ctx) {
        runtime.close_ctx = null;
        runtime.close_fn = null;
    }
}

pub fn resetForTest(allocator: std.mem.Allocator) void {
    runtime.mu.lock();
    defer runtime.mu.unlock();
    for (runtime.entries.items) |row| {
        freeEntry(allocator, row);
    }
    runtime.entries.clearRetainingCapacity();
    runtime.close_ctx = null;
    runtime.close_fn = null;
}

pub fn recordNotify(
    allocator: std.mem.Allocator,
    id: u32,
    app_name: []const u8,
    app_icon: []const u8,
    summary: []const u8,
    body: []const u8,
    urgency: u8,
    transient: bool,
) !void {
    runtime.mu.lock();
    defer runtime.mu.unlock();

    const now = std.time.nanoTimestamp();
    if (findIndexLocked(id)) |idx| {
        var row = &runtime.entries.items[idx];
        allocator.free(row.app_name);
        allocator.free(row.app_icon);
        allocator.free(row.summary);
        allocator.free(row.body);
        row.app_name = try allocator.dupe(u8, app_name);
        row.app_icon = try allocator.dupe(u8, app_icon);
        row.summary = try allocator.dupe(u8, summary);
        row.body = try allocator.dupe(u8, body);
        row.urgency = urgency;
        row.transient = transient;
        row.active = true;
        row.closed_reason = 0;
        row.updated_ns = now;
        return;
    }

    try runtime.entries.append(allocator, .{
        .id = id,
        .app_name = try allocator.dupe(u8, app_name),
        .app_icon = try allocator.dupe(u8, app_icon),
        .summary = try allocator.dupe(u8, summary),
        .body = try allocator.dupe(u8, body),
        .urgency = urgency,
        .transient = transient,
        .active = true,
        .closed_reason = 0,
        .created_ns = now,
        .updated_ns = now,
    });

    while (runtime.entries.items.len > max_entries) {
        const removed = runtime.entries.orderedRemove(0);
        freeEntry(allocator, removed);
    }
}

pub fn recordClosed(id: u32, reason: u32) void {
    runtime.mu.lock();
    defer runtime.mu.unlock();
    const idx = findIndexLocked(id) orelse return;
    runtime.entries.items[idx].active = false;
    runtime.entries.items[idx].closed_reason = reason;
    runtime.entries.items[idx].updated_ns = std.time.nanoTimestamp();
}

pub fn closeById(id: u32) bool {
    runtime.mu.lock();
    defer runtime.mu.unlock();
    const close_fn = runtime.close_fn orelse return false;
    const close_ctx = runtime.close_ctx orelse return false;
    return close_fn(close_ctx, id);
}

pub fn closeAllActive() usize {
    runtime.mu.lock();
    const close_fn = runtime.close_fn;
    const close_ctx = runtime.close_ctx;
    var ids = std.ArrayList(u32).empty;
    defer ids.deinit(std.heap.page_allocator);
    if (close_fn != null and close_ctx != null) {
        for (runtime.entries.items) |entry| {
            if (!entry.active) continue;
            ids.append(std.heap.page_allocator, entry.id) catch |err| {
                std.log.warn("notifications close-all id buffer append failed: {s}", .{@errorName(err)});
                break;
            };
        }
    }
    runtime.mu.unlock();

    if (close_fn == null or close_ctx == null) return 0;
    var closed: usize = 0;
    for (ids.items) |id| {
        if (close_fn.?(close_ctx.?, id)) closed += 1;
    }
    return closed;
}

pub fn snapshot(allocator: std.mem.Allocator) ![]Snapshot {
    runtime.mu.lock();
    defer runtime.mu.unlock();

    var out = try allocator.alloc(Snapshot, runtime.entries.items.len);
    errdefer {
        for (out) |row| freeSnapshotRow(allocator, row);
        allocator.free(out);
    }

    for (runtime.entries.items, 0..) |entry, idx| {
        out[idx] = .{
            .id = entry.id,
            .app_name = try allocator.dupe(u8, entry.app_name),
            .app_icon = try allocator.dupe(u8, entry.app_icon),
            .summary = try allocator.dupe(u8, entry.summary),
            .body = try allocator.dupe(u8, entry.body),
            .urgency = entry.urgency,
            .transient = entry.transient,
            .active = entry.active,
            .closed_reason = entry.closed_reason,
            .created_ns = entry.created_ns,
            .updated_ns = entry.updated_ns,
        };
    }
    return out;
}

pub fn freeSnapshot(allocator: std.mem.Allocator, rows: []Snapshot) void {
    for (rows) |row| freeSnapshotRow(allocator, row);
    allocator.free(rows);
}

pub fn appendRouteCandidates(
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    term: []const u8,
    out: *search.CandidateList,
) !void {
    const rows = try snapshot(allocator);
    defer freeSnapshot(allocator, rows);

    var active_count: usize = 0;
    for (rows) |row| {
        if (row.active) active_count += 1;
    }

    if (active_count > 0) {
        const title = try keep(dynamic_owned, allocator, "Dismiss All Notifications");
        const subtitle = try keep(dynamic_owned, allocator, "Close all active notifications");
        const action = try keep(dynamic_owned, allocator, "notif-dismiss-all");
        try out.append(allocator, search.Candidate.initWithIcon(.action, title, subtitle, action, "window-close-symbolic"));
    }

    if (rows.len == 0) {
        const title = try keep(dynamic_owned, allocator, "No notifications yet");
        const subtitle = try keep(dynamic_owned, allocator, "Send a notification, then search with $ prefix");
        try out.append(allocator, search.Candidate.initWithIcon(.hint, title, subtitle, "", "preferences-system-notifications-symbolic"));
        return;
    }

    var i: usize = rows.len;
    while (i > 0) {
        i -= 1;
        const row = rows[i];
        if (!matchesTerm(row, term)) continue;

        const title = if (row.summary.len > 0) row.summary else row.app_name;
        const age = formatAge(allocator, row.updated_ns) catch continue;
        defer allocator.free(age);
        const subtitle_base = if (row.active)
            try std.fmt.allocPrint(allocator, "{s} | {s}", .{ row.app_name, age })
        else
            try std.fmt.allocPrint(allocator, "{s} | closed ({d}) | {s}", .{ row.app_name, row.closed_reason, age });
        defer allocator.free(subtitle_base);

        const subtitle_buf = if (row.body.len > 0) blk: {
            const snippet = try truncateBody(allocator, row.body, 120);
            defer allocator.free(snippet);
            break :blk try std.fmt.allocPrint(allocator, "{s} | {s}", .{ subtitle_base, snippet });
        } else try allocator.dupe(u8, subtitle_base);
        defer allocator.free(subtitle_buf);

        const action_buf = if (row.active)
            try std.fmt.allocPrint(allocator, "notif-dismiss:{d}", .{row.id})
        else
            try std.fmt.allocPrint(allocator, "notif-noop:{d}", .{row.id});
        defer allocator.free(action_buf);

        const kept_title = try keep(dynamic_owned, allocator, title);
        const kept_subtitle = try keep(dynamic_owned, allocator, subtitle_buf);
        const kept_action = try keep(dynamic_owned, allocator, action_buf);
        const icon_hint = if (std.mem.trim(u8, row.app_icon, " \t\r\n").len > 0) row.app_icon else row.app_name;
        const kept_icon = try keep(dynamic_owned, allocator, icon_hint);
        try out.append(allocator, search.Candidate.initWithIcon(
            .notification,
            kept_title,
            kept_subtitle,
            kept_action,
            kept_icon,
        ));
    }
}

fn findIndexLocked(id: u32) ?usize {
    for (runtime.entries.items, 0..) |row, idx| {
        if (row.id == id) return idx;
    }
    return null;
}

fn freeEntry(allocator: std.mem.Allocator, row: Entry) void {
    allocator.free(row.app_name);
    allocator.free(row.app_icon);
    allocator.free(row.summary);
    allocator.free(row.body);
}

fn freeSnapshotRow(allocator: std.mem.Allocator, row: Snapshot) void {
    allocator.free(row.app_name);
    allocator.free(row.app_icon);
    allocator.free(row.summary);
    allocator.free(row.body);
}

fn keep(dynamic_owned: *std.ArrayListUnmanaged([]u8), allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    const copy = try allocator.dupe(u8, value);
    try dynamic_owned.append(allocator, copy);
    return copy;
}

fn matchesTerm(row: Snapshot, term: []const u8) bool {
    const trimmed = std.mem.trim(u8, term, " \t\r\n");
    if (trimmed.len == 0) return true;
    return containsIgnoreCase(row.summary, trimmed) or
        containsIgnoreCase(row.body, trimmed) or
        containsIgnoreCase(row.app_name, trimmed);
}

fn containsIgnoreCase(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (hay.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(hay[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn truncateBody(allocator: std.mem.Allocator, body: []const u8, max_len: usize) ![]u8 {
    const trimmed = std.mem.trim(u8, body, " \t\r\n");
    if (trimmed.len <= max_len) return allocator.dupe(u8, trimmed);
    return std.fmt.allocPrint(allocator, "{s}...", .{trimmed[0..max_len]});
}

fn formatAge(allocator: std.mem.Allocator, ts_ns: i128) ![]u8 {
    const now = std.time.nanoTimestamp();
    const diff_ns: u64 = if (now <= ts_ns) 0 else @intCast(now - ts_ns);
    const secs = diff_ns / std.time.ns_per_s;
    if (secs < 60) return std.fmt.allocPrint(allocator, "{d}s ago", .{secs});
    const mins = secs / 60;
    if (mins < 60) return std.fmt.allocPrint(allocator, "{d}m ago", .{mins});
    const hours = mins / 60;
    return std.fmt.allocPrint(allocator, "{d}h ago", .{hours});
}

test "recordNotify and snapshot preserve latest state" {
    const allocator = std.testing.allocator;
    resetForTest(allocator);
    defer resetForTest(allocator);

    try recordNotify(allocator, 7, "app", "app-icon", "hello", "body", 2, true);
    recordClosed(7, 3);
    try recordNotify(allocator, 7, "app2", "app2-icon", "hello2", "body2", 1, false);

    const rows = try snapshot(allocator);
    defer freeSnapshot(allocator, rows);
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expectEqual(@as(u32, 7), rows[0].id);
    try std.testing.expectEqualStrings("app2", rows[0].app_name);
    try std.testing.expectEqualStrings("app2-icon", rows[0].app_icon);
    try std.testing.expect(rows[0].active);
}

test "appendRouteCandidates emits dismiss-all and notification rows" {
    const allocator = std.testing.allocator;
    resetForTest(allocator);
    defer resetForTest(allocator);

    try recordNotify(allocator, 1, "notify-send", "notify-send", "Title", "Body", 1, false);
    var owned = std.ArrayListUnmanaged([]u8){};
    defer {
        for (owned.items) |item| allocator.free(item);
        owned.deinit(allocator);
    }
    var out = search.CandidateList.empty;
    defer out.deinit(allocator);

    try appendRouteCandidates(&owned, allocator, "", &out);
    try std.testing.expect(out.items.len >= 2);
    try std.testing.expectEqual(search.CandidateKind.action, out.items[0].kind);
    try std.testing.expectEqualStrings("notif-dismiss-all", out.items[0].action);
    try std.testing.expectEqual(search.CandidateKind.notification, out.items[1].kind);
    try std.testing.expectEqualStrings("notify-send", out.items[1].icon);
}
