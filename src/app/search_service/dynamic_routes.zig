const std = @import("std");
const search = @import("../../search/mod.zig");

pub const ToolState = struct {
    fd_available: ?bool = null,
    rg_available: ?bool = null,
};

pub fn collectForRoute(
    tool_state: *ToolState,
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    query: search.Query,
    out: *search.CandidateList,
) !void {
    const term = std.mem.trim(u8, query.term, " \t\r\n");
    if (term.len == 0) return;

    switch (query.route) {
        .files => try collectFdCandidates(tool_state, dynamic_owned, allocator, term, out),
        .grep => try collectRgCandidates(tool_state, dynamic_owned, allocator, term, out),
        else => {},
    }
}

pub fn clearOwned(dynamic_owned: *std.ArrayListUnmanaged([]u8), allocator: std.mem.Allocator) void {
    for (dynamic_owned.items) |item| allocator.free(item);
    dynamic_owned.clearRetainingCapacity();
}

fn collectFdCandidates(
    tool_state: *ToolState,
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    term: []const u8,
    out: *search.CandidateList,
) !void {
    if (!fdAvailable(tool_state)) return;
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return;
    defer allocator.free(home);

    const term_q = try shellSingleQuote(allocator, term);
    defer allocator.free(term_q);
    const home_q = try shellSingleQuote(allocator, home);
    defer allocator.free(home_q);

    try collectFdTypeCandidates(dynamic_owned, allocator, term_q, home_q, "d", .dir, 120, out);
    try collectFdTypeCandidates(dynamic_owned, allocator, term_q, home_q, "f", .file, 180, out);
}

fn collectFdTypeCandidates(
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    term_q: []const u8,
    home_q: []const u8,
    fd_type: []const u8,
    kind: search.CandidateKind,
    max_results: usize,
    out: *search.CandidateList,
) !void {
    const cmd = try std.fmt.allocPrint(
        allocator,
        "fd --type {s} --hidden --follow --color never --ignore-case --max-results {d} --exclude .git --exclude node_modules --exclude .cache --exclude .codex --exclude .local/share/Trash --exclude .local/share/opencode --exclude .local/share/containers {s} {s}",
        .{ fd_type, max_results, term_q, home_q },
    );
    defer allocator.free(cmd);

    const rows = try runShellCapture(allocator, cmd);
    defer allocator.free(rows);
    var lines = std.mem.splitScalar(u8, rows, '\n');
    while (lines.next()) |line| {
        const path = std.mem.trim(u8, line, " \t\r");
        if (path.len == 0) continue;
        const title = std.fs.path.basename(path);
        const kept_title = try keepDynamicString(dynamic_owned, allocator, title);
        const kept_path = try keepDynamicString(dynamic_owned, allocator, path);
        try out.append(allocator, search.Candidate.init(kind, kept_title, kept_path, kept_path));
    }
}

fn collectRgCandidates(
    tool_state: *ToolState,
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    term: []const u8,
    out: *search.CandidateList,
) !void {
    if (!rgAvailable(tool_state)) return;
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return;
    defer allocator.free(home);

    const term_q = try shellSingleQuote(allocator, term);
    defer allocator.free(term_q);
    const home_q = try shellSingleQuote(allocator, home);
    defer allocator.free(home_q);

    const cmd = try std.fmt.allocPrint(
        allocator,
        "rg --line-number --no-heading --color never --smart-case --hidden --max-count 200 --max-columns 300 --max-columns-preview --glob '!.git' --glob '!node_modules' --glob '!.cache/**' --glob '!.codex/**' --glob '!.local/share/Trash/**' --glob '!.local/share/opencode/**' --glob '!.local/share/containers/**' {s} {s} 2>/dev/null || true",
        .{ term_q, home_q },
    );
    defer allocator.free(cmd);

    const rows = try runShellCapture(allocator, cmd);
    defer allocator.free(rows);
    var lines = std.mem.splitScalar(u8, rows, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        const row = std.mem.trim(u8, line, " \t\r");
        if (row.len == 0) continue;
        const first_colon = std.mem.indexOfScalar(u8, row, ':') orelse continue;
        const second_colon_rel = std.mem.indexOfScalar(u8, row[first_colon + 1 ..], ':') orelse continue;
        const second_colon = first_colon + 1 + second_colon_rel;
        const path = row[0..first_colon];
        const line_num = row[first_colon + 1 .. second_colon];
        const snippet = std.mem.trim(u8, row[second_colon + 1 ..], " \t");
        const base = std.fs.path.basename(path);
        const title = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ base, line_num });
        defer allocator.free(title);
        const subtitle = if (snippet.len > 0)
            try std.fmt.allocPrint(allocator, "{s} | {s}", .{ path, snippet })
        else
            try allocator.dupe(u8, path);
        defer allocator.free(subtitle);
        const action = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ path, line_num });
        defer allocator.free(action);
        const kept_title = try keepDynamicString(dynamic_owned, allocator, title);
        const kept_subtitle = try keepDynamicString(dynamic_owned, allocator, subtitle);
        const kept_action = try keepDynamicString(dynamic_owned, allocator, action);
        try out.append(allocator, search.Candidate.init(.grep, kept_title, kept_subtitle, kept_action));
        count += 1;
        if (count >= 200) break;
    }
}

fn keepDynamicString(
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    value: []const u8,
) ![]const u8 {
    const copy = try allocator.dupe(u8, value);
    try dynamic_owned.append(allocator, copy);
    return copy;
}

fn commandExists(name: []const u8) bool {
    const check_cmd = std.fmt.allocPrint(std.heap.page_allocator, "{s} --help >/dev/null 2>&1", .{name}) catch return false;
    defer std.heap.page_allocator.free(check_cmd);

    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "sh", "-lc", check_cmd },
    }) catch return false;
    defer {
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
    }
    return result.term == .Exited and result.term.Exited == 0;
}

fn fdAvailable(state: *ToolState) bool {
    if (state.fd_available) |value| return value;
    const value = commandExists("fd");
    state.fd_available = value;
    return value;
}

fn rgAvailable(state: *ToolState) bool {
    if (state.rg_available) |value| return value;
    const value = commandExists("rg");
    state.rg_available = value;
    return value;
}

fn shellSingleQuote(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try out.append(allocator, '\'');
    for (value) |ch| {
        if (ch == '\'') {
            try out.appendSlice(allocator, "'\\''");
        } else {
            try out.append(allocator, ch);
        }
    }
    try out.append(allocator, '\'');
    return out.toOwnedSlice(allocator);
}

fn runShellCapture(allocator: std.mem.Allocator, command: []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "sh", "-lc", command },
        .max_output_bytes = 8 * 1024 * 1024,
    });
    defer allocator.free(result.stderr);
    if (result.term != .Exited or result.term.Exited != 0) {
        allocator.free(result.stdout);
        return error.CommandFailed;
    }
    return result.stdout;
}

test "shellSingleQuote wraps and escapes apostrophes" {
    const allocator = std.testing.allocator;

    const simple = try shellSingleQuote(allocator, "alpha");
    defer allocator.free(simple);
    try std.testing.expectEqualStrings("'alpha'", simple);

    const escaped = try shellSingleQuote(allocator, "a'b");
    defer allocator.free(escaped);
    try std.testing.expectEqualStrings("'a'\\''b'", escaped);
}

test "runShellCapture returns stdout for successful command" {
    const allocator = std.testing.allocator;
    const out = try runShellCapture(allocator, "printf 'ok\\n'");
    defer allocator.free(out);
    try std.testing.expectEqualStrings("ok\n", out);
}

test "runShellCapture returns CommandFailed on non-zero exit" {
    try std.testing.expectError(error.CommandFailed, runShellCapture(std.testing.allocator, "exit 7"));
}

test "clearOwned frees entries and resets logical length" {
    const allocator = std.testing.allocator;
    var owned = std.ArrayListUnmanaged([]u8){};
    defer owned.deinit(allocator);

    try owned.append(allocator, try allocator.dupe(u8, "first"));
    try owned.append(allocator, try allocator.dupe(u8, "second"));

    clearOwned(&owned, allocator);
    try std.testing.expectEqual(@as(usize, 0), owned.items.len);
}

test "collectForRoute skips dynamic tools when cached unavailable" {
    const allocator = std.testing.allocator;
    var state = ToolState{
        .fd_available = false,
        .rg_available = false,
    };
    var owned = std.ArrayListUnmanaged([]u8){};
    defer owned.deinit(allocator);

    var out = search.CandidateList.empty;
    defer out.deinit(allocator);

    const files_query = search.Query{
        .raw = "% abc",
        .route = .files,
        .term = "abc",
    };
    try collectForRoute(&state, &owned, allocator, files_query, &out);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expectEqual(@as(usize, 0), owned.items.len);

    const grep_query = search.Query{
        .raw = "& xyz",
        .route = .grep,
        .term = "xyz",
    };
    try collectForRoute(&state, &owned, allocator, grep_query, &out);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expectEqual(@as(usize, 0), owned.items.len);
}
