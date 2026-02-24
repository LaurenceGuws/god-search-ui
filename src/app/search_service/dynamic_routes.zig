const std = @import("std");
const providers = @import("../../providers/mod.zig");
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
        .calc => try collectCalcCandidates(dynamic_owned, allocator, term, out),
        else => {},
    }
}

pub fn clearOwned(dynamic_owned: *std.ArrayListUnmanaged([]u8), allocator: std.mem.Allocator) void {
    for (dynamic_owned.items) |item| allocator.free(item);
    dynamic_owned.clearRetainingCapacity();
}

const ParsedRgRow = struct {
    path: []const u8,
    line_num: []const u8,
    snippet: []const u8,
};

const RgJsonEvent = struct {
    type: []const u8,
    data: ?Data = null,

    const Data = struct {
        path: ?TextField = null,
        line_number: ?usize = null,
        lines: ?TextField = null,
    };

    const TextField = struct {
        text: ?[]const u8 = null,
    };
};

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
        const path = parseFdOutputRow(line) orelse continue;
        try appendFdCandidate(dynamic_owned, allocator, path, kind, out);
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
        // Bound output at the source. `--max-count` is per-file, so using 200 there can
        // explode JSON output on broad queries and overflow our capture buffer.
        "rg --json --line-number --color never --smart-case --hidden --max-count 1 --max-files 400 --max-columns 300 --max-columns-preview --glob '!.git' --glob '!node_modules' --glob '!.cache/**' --glob '!.codex/**' --glob '!.local/share/Trash/**' --glob '!.local/share/opencode/**' --glob '!.local/share/containers/**' {s} {s} 2>/dev/null || true",
        .{ term_q, home_q },
    );
    defer allocator.free(cmd);

    const rows = try runShellCapture(allocator, cmd);
    defer allocator.free(rows);
    var lines = std.mem.splitScalar(u8, rows, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        const parsed = parseRgJsonRow(allocator, line) orelse continue;
        errdefer freeParsedRgRow(allocator, parsed);
        try appendRgCandidate(dynamic_owned, allocator, parsed, out);
        freeParsedRgRow(allocator, parsed);
        count += 1;
        if (count >= 200) break;
    }
}

fn parseFdOutputRow(line: []const u8) ?[]const u8 {
    const path = std.mem.trim(u8, line, " \t\r");
    if (path.len == 0) return null;
    return path;
}

fn parseRgJsonRow(allocator: std.mem.Allocator, line: []const u8) ?ParsedRgRow {
    const row = std.mem.trim(u8, line, " \t\r");
    if (row.len == 0) return null;
    var parsed = std.json.parseFromSlice(RgJsonEvent, allocator, row, .{
        .ignore_unknown_fields = true,
    }) catch return null;
    defer parsed.deinit();

    if (!std.mem.eql(u8, parsed.value.type, "match")) return null;
    const data = parsed.value.data orelse return null;
    const path_field = data.path orelse return null;
    const path = path_field.text orelse return null;
    const line_number = data.line_number orelse return null;
    const line_num = std.fmt.allocPrint(allocator, "{d}", .{line_number}) catch return null;
    errdefer allocator.free(line_num);
    const line_field = data.lines orelse return null;
    const raw_snippet = line_field.text orelse return null;
    const snippet = std.mem.trim(u8, raw_snippet, " \t\r\n");
    const path_out = allocator.dupe(u8, path) catch return null;
    errdefer allocator.free(path_out);
    const snippet_out = allocator.dupe(u8, snippet) catch {
        allocator.free(path_out);
        return null;
    };
    errdefer allocator.free(snippet_out);

    return .{
        .path = path_out,
        .line_num = line_num,
        .snippet = snippet_out,
    };
}

fn appendFdCandidate(
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    path: []const u8,
    kind: search.CandidateKind,
    out: *search.CandidateList,
) !void {
    const title = std.fs.path.basename(path);
    const kept_title = try keepDynamicString(dynamic_owned, allocator, title);
    const kept_path = try keepDynamicString(dynamic_owned, allocator, path);
    try out.append(allocator, search.Candidate.init(kind, kept_title, kept_path, kept_path));
}

fn appendRgCandidate(
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    parsed: ParsedRgRow,
    out: *search.CandidateList,
) !void {
    const base = std.fs.path.basename(parsed.path);
    const title = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ base, parsed.line_num });
    defer allocator.free(title);
    const subtitle = if (parsed.snippet.len > 0)
        try std.fmt.allocPrint(allocator, "{s} | {s}", .{ parsed.path, parsed.snippet })
    else
        try allocator.dupe(u8, parsed.path);
    defer allocator.free(subtitle);
    const action = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ parsed.path, parsed.line_num });
    defer allocator.free(action);
    const kept_title = try keepDynamicString(dynamic_owned, allocator, title);
    const kept_subtitle = try keepDynamicString(dynamic_owned, allocator, subtitle);
    const kept_action = try keepDynamicString(dynamic_owned, allocator, action);
    try out.append(allocator, search.Candidate.init(.grep, kept_title, kept_subtitle, kept_action));
}

fn collectCalcCandidates(
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    term: []const u8,
    out: *search.CandidateList,
) !void {
    const value = providers.calc.evaluateExpression(term) catch |err| {
        const subtitle = try std.fmt.allocPrint(allocator, "Error: {s}", .{@errorName(err)});
        defer allocator.free(subtitle);
        const kept_title = try keepDynamicString(dynamic_owned, allocator, "Calculator");
        const kept_subtitle = try keepDynamicString(dynamic_owned, allocator, subtitle);
        try out.append(allocator, .{
            .kind = .hint,
            .title = kept_title,
            .subtitle = kept_subtitle,
            .action = "",
            .icon = "accessories-calculator-symbolic",
        });
        return;
    };

    const result = try providers.calc.formatNumberAlloc(allocator, value);
    defer allocator.free(result);
    const subtitle = try std.fmt.allocPrint(allocator, "{s}  (Enter copies)", .{term});
    defer allocator.free(subtitle);
    const action = try std.fmt.allocPrint(allocator, "calc-copy:{s}", .{result});
    defer allocator.free(action);

    const kept_title = try keepDynamicString(dynamic_owned, allocator, result);
    const kept_subtitle = try keepDynamicString(dynamic_owned, allocator, subtitle);
    const kept_action = try keepDynamicString(dynamic_owned, allocator, action);
    try out.append(allocator, .{
        .kind = .hint,
        .title = kept_title,
        .subtitle = kept_subtitle,
        .action = kept_action,
        .icon = "accessories-calculator-symbolic",
    });
}

fn freeParsedRgRow(allocator: std.mem.Allocator, row: ParsedRgRow) void {
    allocator.free(row.path);
    allocator.free(row.line_num);
    allocator.free(row.snippet);
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

test "parseFdOutputRow trims and skips blanks" {
    try std.testing.expectEqualStrings("/tmp/demo", parseFdOutputRow(" \t/tmp/demo\r ") orelse unreachable);
    try std.testing.expect(parseFdOutputRow("") == null);
    try std.testing.expect(parseFdOutputRow(" \t\r ") == null);
}

test "parseRgJsonRow handles colons in file paths and snippets" {
    const allocator = std.testing.allocator;
    const parsed = parseRgJsonRow(
        allocator,
        " {\"type\":\"match\",\"data\":{\"path\":{\"text\":\"/tmp/a:b/file.txt\"},\"lines\":{\"text\":\"  alpha:beta\\n\"},\"line_number\":42}} ",
    ) orelse unreachable;
    defer freeParsedRgRow(allocator, parsed);

    try std.testing.expectEqualStrings("/tmp/a:b/file.txt", parsed.path);
    try std.testing.expectEqualStrings("42", parsed.line_num);
    try std.testing.expectEqualStrings("alpha:beta", parsed.snippet);
}

test "parseRgJsonRow ignores non-match events and malformed rows" {
    const allocator = std.testing.allocator;
    try std.testing.expect(parseRgJsonRow(allocator, "") == null);
    try std.testing.expect(parseRgJsonRow(allocator, "{\"type\":\"begin\",\"data\":{}}") == null);
    try std.testing.expect(parseRgJsonRow(allocator, "{\"type\":\"match\",\"data\":{\"line_number\":1}}") == null);
    try std.testing.expect(parseRgJsonRow(allocator, "{not-json}") == null);
}

test "parseRgJsonRow keeps empty snippets" {
    const allocator = std.testing.allocator;
    const parsed = parseRgJsonRow(
        allocator,
        "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"/tmp/file.txt\"},\"lines\":{\"text\":\"\\n\"},\"line_number\":7}}",
    ) orelse unreachable;
    defer freeParsedRgRow(allocator, parsed);

    try std.testing.expectEqualStrings("/tmp/file.txt", parsed.path);
    try std.testing.expectEqualStrings("7", parsed.line_num);
    try std.testing.expectEqualStrings("", parsed.snippet);
}

test "collectCalcCandidates emits result and copy action" {
    const allocator = std.testing.allocator;
    var owned = std.ArrayListUnmanaged([]u8){};
    defer {
        clearOwned(&owned, allocator);
        owned.deinit(allocator);
    }
    var out = search.CandidateList.empty;
    defer out.deinit(allocator);

    try collectCalcCandidates(&owned, allocator, "1 + 2*3", &out);
    try std.testing.expectEqual(@as(usize, 1), out.items.len);
    try std.testing.expectEqual(search.CandidateKind.hint, out.items[0].kind);
    try std.testing.expectEqualStrings("7", out.items[0].title);
    try std.testing.expectEqualStrings("1 + 2*3  (Enter copies)", out.items[0].subtitle);
    try std.testing.expectEqualStrings("calc-copy:7", out.items[0].action);
}

test "collectCalcCandidates emits error hint on invalid expression" {
    const allocator = std.testing.allocator;
    var owned = std.ArrayListUnmanaged([]u8){};
    defer {
        clearOwned(&owned, allocator);
        owned.deinit(allocator);
    }
    var out = search.CandidateList.empty;
    defer out.deinit(allocator);

    try collectCalcCandidates(&owned, allocator, "(1+", &out);
    try std.testing.expectEqual(@as(usize, 1), out.items.len);
    try std.testing.expectEqualStrings("Calculator", out.items[0].title);
    try std.testing.expect(std.mem.startsWith(u8, out.items[0].subtitle, "Error: "));
    try std.testing.expectEqualStrings("", out.items[0].action);
}

test "appendFdCandidate copies dynamic strings" {
    const allocator = std.testing.allocator;

    var owned = std.ArrayListUnmanaged([]u8){};
    defer {
        clearOwned(&owned, allocator);
        owned.deinit(allocator);
    }

    var out = search.CandidateList.empty;
    defer out.deinit(allocator);

    const row_buf = try allocator.dupe(u8, "  /tmp/example.txt  ");
    defer allocator.free(row_buf);
    const path = parseFdOutputRow(row_buf) orelse unreachable;

    try appendFdCandidate(&owned, allocator, path, .file, &out);
    try std.testing.expectEqual(@as(usize, 1), out.items.len);
    try std.testing.expectEqual(@as(usize, 2), owned.items.len);
    try std.testing.expectEqualStrings("example.txt", out.items[0].title);
    try std.testing.expectEqualStrings("/tmp/example.txt", out.items[0].subtitle);
    try std.testing.expect(out.items[0].subtitle.ptr == out.items[0].action.ptr);

    @memset(row_buf, 'x');
    try std.testing.expectEqualStrings("example.txt", out.items[0].title);
    try std.testing.expectEqualStrings("/tmp/example.txt", out.items[0].subtitle);
}

test "appendRgCandidate copies parsed data and handles empty snippet" {
    const allocator = std.testing.allocator;

    var owned = std.ArrayListUnmanaged([]u8){};
    defer {
        clearOwned(&owned, allocator);
        owned.deinit(allocator);
    }

    var out = search.CandidateList.empty;
    defer out.deinit(allocator);

    const row_buf = try allocator.dupe(
        u8,
        "{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"/tmp/note.md\"},\"lines\":{\"text\":\"\\n\"},\"line_number\":7}}",
    );
    defer allocator.free(row_buf);
    const parsed = parseRgJsonRow(allocator, row_buf) orelse unreachable;
    defer freeParsedRgRow(allocator, parsed);

    try appendRgCandidate(&owned, allocator, parsed, &out);
    try std.testing.expectEqual(@as(usize, 1), out.items.len);
    try std.testing.expectEqual(@as(usize, 3), owned.items.len);
    try std.testing.expectEqualStrings("note.md:7", out.items[0].title);
    try std.testing.expectEqualStrings("/tmp/note.md", out.items[0].subtitle);
    try std.testing.expectEqualStrings("/tmp/note.md:7", out.items[0].action);

    @memset(row_buf, 'y');
    try std.testing.expectEqualStrings("note.md:7", out.items[0].title);
    try std.testing.expectEqualStrings("/tmp/note.md", out.items[0].subtitle);
    try std.testing.expectEqualStrings("/tmp/note.md:7", out.items[0].action);
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
