const std = @import("std");
const providers = @import("../../providers/mod.zig");
const tool_check = @import("../../providers/tool_check.zig");
const notifications = @import("../../notifications/mod.zig");
const search = @import("../../search/mod.zig");
const runtime_tools = @import("../../config/runtime_tools.zig");

const max_rg_capture_bytes = 64 * 1024 * 1024;
const max_pkg_capture_bytes = 16 * 1024 * 1024;
const max_icon_capture_bytes = 16 * 1024 * 1024;
const nerd_icons_default_rel_path = "personal/bash_engine/src/modules/fun/nerd_icons_fzf/icons_simple.txt";
const emoji_translit_path = "/usr/share/i18n/locales/translit_emojis";
const tool_state_refresh_ttl_ns: i64 = 5 * std.time.ns_per_s;

pub const ToolState = struct {
    fd_available: ?bool = null,
    rg_available: ?bool = null,
    rg_include_hidden: ?bool = null,
    fd_last_checked_ns: i128 = 0,
    rg_last_checked_ns: i128 = 0,
    rg_hidden_last_checked_ns: i128 = 0,
};

pub fn invalidateToolStateCache(state: *ToolState) void {
    state.fd_available = null;
    state.rg_available = null;
    state.rg_include_hidden = null;
    state.fd_last_checked_ns = 0;
    state.rg_last_checked_ns = 0;
    state.rg_hidden_last_checked_ns = 0;
}

pub fn collectForRoute(
    tool_state: *ToolState,
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    query: search.Query,
    out: *search.CandidateList,
) !void {
    const term = std.mem.trim(u8, query.term, " \t\r\n");
    if (term.len == 0 and query.route != .notifications and query.route != .nerd_icons and query.route != .emoji) return;

    switch (query.route) {
        .files => try collectFdCandidates(tool_state, dynamic_owned, allocator, term, out),
        .grep => try collectRgCandidates(tool_state, dynamic_owned, allocator, term, out),
        .packages => try collectPackageCandidates(tool_state, dynamic_owned, allocator, term, out),
        .icons => try collectIconCandidates(tool_state, dynamic_owned, allocator, term, out),
        .nerd_icons => try collectNerdIconCandidates(dynamic_owned, allocator, term, out),
        .emoji => try collectEmojiCandidates(dynamic_owned, allocator, term, out),
        .notifications => try notifications.runtime.appendRouteCandidates(dynamic_owned, allocator, term, out),
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

    const hidden_flag = if (rgIncludeHidden(tool_state)) "--hidden" else "";
    const cmd = try std.fmt.allocPrint(
        allocator,
        "rg --json --line-number --color never --smart-case {s} --max-columns 300 --max-columns-preview --glob '!.git' --glob '!node_modules' --glob '!.cache/**' --glob '!.codex/**' --glob '!.local/share/Trash/**' --glob '!.local/share/opencode/**' --glob '!.local/share/containers/**' {s} {s} 2>/dev/null",
        .{ hidden_flag, term_q, home_q },
    );
    defer allocator.free(cmd);

    std.log.info("grep collect start route=grep term={s} cmd={s}", .{ term, cmd });
    const rows = runShellCaptureBoundedWithAllowExitOne(allocator, cmd, max_rg_capture_bytes, true) catch |err| {
        std.log.warn("grep collect failed route=grep term={s} err={s}", .{ term, @errorName(err) });
        return err;
    };
    defer allocator.free(rows);
    var lines = std.mem.splitScalar(u8, rows, '\n');
    var parsed_count: usize = 0;
    var emitted_count: usize = 0;
    while (lines.next()) |line| {
        parsed_count += 1;
        const parsed = parseRgJsonRow(allocator, line) orelse continue;
        errdefer freeParsedRgRow(allocator, parsed);
        try appendRgCandidate(dynamic_owned, allocator, parsed, out);
        freeParsedRgRow(allocator, parsed);
        emitted_count += 1;
    }
    std.log.info("grep collect done term={s} parsed_lines={d} emitted={d}", .{ term, parsed_count, emitted_count });
}

const PackageRow = struct {
    package_name: []const u8,
    source_name: []const u8,
    version: []const u8,
    description: []const u8,
    installed: bool,
};

fn collectPackageCandidates(
    tool_state: *ToolState,
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    term: []const u8,
    out: *search.CandidateList,
) !void {
    const pkg_query = parsePackageQuery(term);
    _ = tool_state;
    const source_cmd = packageSearchCommand();
    const term_q = try shellSingleQuote(allocator, pkg_query.term);
    defer allocator.free(term_q);
    const cmd = switch (source_cmd) {
        .yay => if (pkg_query.term.len > 0)
            try std.fmt.allocPrint(allocator, "yay -Ss --color never {s} 2>/dev/null", .{term_q})
        else
            try allocator.dupe(u8, "yay -Qq 2>/dev/null"),
        .pacman => if (pkg_query.term.len > 0)
            try std.fmt.allocPrint(allocator, "pacman -Ss --color never {s} 2>/dev/null", .{term_q})
        else
            try allocator.dupe(u8, "pacman -Qq 2>/dev/null"),
    };
    defer allocator.free(cmd);

    std.log.info("packages collect start route=packages term={s} cmd={s}", .{ term, cmd });
    const allow_no_match_exit = pkg_query.term.len > 0;
    const rows = runShellCaptureBoundedWithAllowExitOne(
        allocator,
        cmd,
        max_pkg_capture_bytes,
        allow_no_match_exit,
    ) catch |err| {
        std.log.warn("packages collect failed route=packages term={s} err={s}", .{ term, @errorName(err) });
        return err;
    };
    defer allocator.free(rows);

    var lines = std.mem.splitScalar(u8, rows, '\n');
    var pending: ?PackageRow = null;
    var parsed_count: usize = 0;
    var emitted_count: usize = 0;
    while (lines.next()) |line_raw| {
        const line = std.mem.trimRight(u8, line_raw, "\r");
        if (line.len == 0) continue;
        parsed_count += 1;
        if (pkg_query.term.len == 0) {
            // Installed listing mode returns one package name per line.
            if (appendInstalledPackageCandidate(dynamic_owned, allocator, line, out)) |_| {
                emitted_count += 1;
            } else |_| {}
            continue;
        }
        if (line[0] == ' ' or line[0] == '\t') {
            if (pending) |*entry| {
                entry.description = std.mem.trim(u8, line, " \t");
            }
            continue;
        }

        if (pending) |entry| {
            if (!pkg_query.installed_only or entry.installed) {
                try appendPackageCandidate(dynamic_owned, allocator, entry, entry.installed, out);
                emitted_count += 1;
                if (entry.installed) {
                    try appendPackageRemoveAction(dynamic_owned, allocator, entry.package_name, out);
                    emitted_count += 1;
                }
            }
        }
        pending = parsePackageHeaderLine(line) orelse null;
    }
    if (pending) |entry| {
        if (!pkg_query.installed_only or entry.installed) {
            try appendPackageCandidate(dynamic_owned, allocator, entry, entry.installed, out);
            emitted_count += 1;
            if (entry.installed) {
                try appendPackageRemoveAction(dynamic_owned, allocator, entry.package_name, out);
                emitted_count += 1;
            }
        }
    }
    std.log.info("packages collect done term={s} parsed_lines={d} emitted={d}", .{ term, parsed_count, emitted_count });
}

const PackageQuery = struct {
    installed_only: bool,
    term: []const u8,
};

fn parsePackageQuery(term: []const u8) PackageQuery {
    const trimmed = std.mem.trim(u8, term, " \t\r\n");
    if (std.mem.eql(u8, trimmed, "i") or std.mem.eql(u8, trimmed, "installed")) {
        return .{ .installed_only = true, .term = "" };
    }
    if (std.mem.startsWith(u8, trimmed, "i ")) {
        return .{ .installed_only = true, .term = std.mem.trim(u8, trimmed[2..], " \t\r\n") };
    }
    if (std.mem.startsWith(u8, trimmed, "installed ")) {
        return .{ .installed_only = true, .term = std.mem.trim(u8, trimmed["installed ".len..], " \t\r\n") };
    }
    return .{ .installed_only = false, .term = trimmed };
}

fn appendInstalledPackageCandidate(
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    package_name_raw: []const u8,
    out: *search.CandidateList,
) !void {
    const package_name = std.mem.trim(u8, package_name_raw, " \t\r\n");
    if (package_name.len == 0) return;
    const row = PackageRow{
        .package_name = package_name,
        .source_name = "local",
        .version = "",
        .description = "",
        .installed = true,
    };
    try appendPackageCandidate(dynamic_owned, allocator, row, true, out);
    try appendPackageRemoveAction(dynamic_owned, allocator, package_name, out);
}

fn parsePackageHeaderLine(line: []const u8) ?PackageRow {
    var tokens = std.mem.tokenizeAny(u8, line, " \t");
    const source_pkg = tokens.next() orelse return null;
    const version = tokens.next() orelse "";
    const installed = std.ascii.indexOfIgnoreCase(line, "[installed") != null;
    const slash_idx = std.mem.indexOfScalar(u8, source_pkg, '/') orelse return null;
    if (slash_idx == 0 or slash_idx + 1 >= source_pkg.len) return null;
    const source_name = source_pkg[0..slash_idx];
    const package_name = source_pkg[slash_idx + 1 ..];
    return .{
        .package_name = package_name,
        .source_name = source_name,
        .version = version,
        .description = "",
        .installed = installed,
    };
}

fn appendPackageCandidate(
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    row: PackageRow,
    installed: bool,
    out: *search.CandidateList,
) !void {
    const title = try std.fmt.allocPrint(allocator, "{s} ({s})", .{ row.package_name, row.source_name });
    defer allocator.free(title);
    const subtitle = if (row.description.len > 0)
        try std.fmt.allocPrint(allocator, "{s} {s} | {s}", .{ row.source_name, row.version, row.description })
    else
        try std.fmt.allocPrint(allocator, "{s} {s}", .{ row.source_name, row.version });
    defer allocator.free(subtitle);
    const action = if (installed)
        try std.fmt.allocPrint(allocator, "pkg-update:{s}", .{row.package_name})
    else
        try std.fmt.allocPrint(allocator, "pkg-install:{s}", .{row.package_name});
    defer allocator.free(action);

    const kept_title = try keepDynamicString(dynamic_owned, allocator, title);
    const kept_subtitle = try keepDynamicString(dynamic_owned, allocator, subtitle);
    const kept_action = try keepDynamicString(dynamic_owned, allocator, action);
    const kept_icon = try keepDynamicString(dynamic_owned, allocator, row.package_name);
    try out.append(allocator, search.Candidate.initWithIcon(
        .action,
        kept_title,
        kept_subtitle,
        kept_action,
        kept_icon,
    ));
}

fn appendPackageRemoveAction(
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    package_name: []const u8,
    out: *search.CandidateList,
) !void {
    const title = try std.fmt.allocPrint(allocator, "Remove {s}", .{package_name});
    defer allocator.free(title);
    const subtitle = try allocator.dupe(u8, "Uninstall package");
    defer allocator.free(subtitle);
    const action = try std.fmt.allocPrint(allocator, "pkg-remove:{s}", .{package_name});
    defer allocator.free(action);
    const kept_title = try keepDynamicString(dynamic_owned, allocator, title);
    const kept_subtitle = try keepDynamicString(dynamic_owned, allocator, subtitle);
    const kept_action = try keepDynamicString(dynamic_owned, allocator, action);
    try out.append(allocator, search.Candidate.initWithIcon(
        .hint,
        kept_title,
        kept_subtitle,
        kept_action,
        "user-trash-symbolic",
    ));
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

fn collectIconCandidates(
    tool_state: *ToolState,
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    term: []const u8,
    out: *search.CandidateList,
) !void {
    if (!fdAvailable(tool_state)) return;
    const term_trimmed = std.mem.trim(u8, term, " \t\r\n");
    if (term_trimmed.len == 0) return;

    const term_q = try shellSingleQuote(allocator, term_trimmed);
    defer allocator.free(term_q);
    const cmd = try std.fmt.allocPrint(
        allocator,
        "for d in \"$HOME/.icons\" \"$HOME/.local/share/icons\" /usr/share/icons /usr/share/pixmaps; do [ -d \"$d\" ] || continue; fd --type f --hidden --follow --ignore-case --color never -e svg -e png -e xpm --max-results 250 {s} \"$d\"; done | awk '!seen[$0]++'",
        .{term_q},
    );
    defer allocator.free(cmd);

    const rows = runShellCaptureBounded(allocator, cmd, max_icon_capture_bytes) catch |err| {
        std.log.warn("icons collect failed route=icons term={s} err={s}", .{ term_trimmed, @errorName(err) });
        return;
    };
    defer allocator.free(rows);

    var lines = std.mem.splitScalar(u8, rows, '\n');
    var parsed_count: usize = 0;
    var emitted_count: usize = 0;
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0) continue;
        parsed_count += 1;
        const title = std.fs.path.basename(line);
        const kept_title = try keepDynamicString(dynamic_owned, allocator, title);
        const kept_path = try keepDynamicString(dynamic_owned, allocator, line);
        try out.append(allocator, search.Candidate.initWithIcon(.file, kept_title, kept_path, kept_path, kept_path));
        emitted_count += 1;
    }
    std.log.info("icons collect done term={s} parsed_lines={d} emitted={d}", .{ term_trimmed, parsed_count, emitted_count });
}

fn collectNerdIconCandidates(
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    term: []const u8,
    out: *search.CandidateList,
) !void {
    const term_trimmed = std.mem.trim(u8, term, " \t\r\n");
    const path = resolveNerdIconSourcePath(allocator) catch return;
    defer allocator.free(path);
    const data = std.fs.openFileAbsolute(path, .{}) catch return;
    defer data.close();
    const content = data.readToEndAlloc(allocator, 8 * 1024 * 1024) catch return;
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    var parsed_count: usize = 0;
    var emitted_count: usize = 0;
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0 or line[0] == '#') continue;
        parsed_count += 1;
        if (term_trimmed.len > 0 and !containsAsciiCaseInsensitive(line, term_trimmed)) continue;
        const glyph, const alias, const description = parseNerdIconLine(line) orelse continue;
        const action = try std.fmt.allocPrint(allocator, "nerd-copy:{s}", .{glyph});
        defer allocator.free(action);
        const kept_title = try keepDynamicString(dynamic_owned, allocator, alias);
        const kept_subtitle = try keepDynamicString(dynamic_owned, allocator, description);
        const kept_action = try keepDynamicString(dynamic_owned, allocator, action);
        const kept_icon = try keepDynamicString(dynamic_owned, allocator, glyph);
        try out.append(allocator, search.Candidate.initWithIcon(.hint, kept_title, kept_subtitle, kept_action, kept_icon));
        emitted_count += 1;
    }
    std.log.info("nerd-icons collect done term={s} parsed_lines={d} emitted={d}", .{ term_trimmed, parsed_count, emitted_count });
}

fn collectEmojiCandidates(
    dynamic_owned: *std.ArrayListUnmanaged([]u8),
    allocator: std.mem.Allocator,
    term: []const u8,
    out: *search.CandidateList,
) !void {
    const term_trimmed = std.mem.trim(u8, term, " \t\r\n");
    const file = std.fs.openFileAbsolute(emoji_translit_path, .{}) catch return;
    defer file.close();
    const content = file.readToEndAlloc(allocator, 2 * 1024 * 1024) catch return;
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    var parsed_count: usize = 0;
    var emitted_count: usize = 0;
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r\n");
        if (line.len == 0 or line[0] == '%' or std.mem.startsWith(u8, line, "translit_") or std.mem.startsWith(u8, line, "LC_") or std.mem.startsWith(u8, line, "END ")) continue;
        parsed_count += 1;
        const emoji, const alias, const name = parseEmojiTranslitLine(line) orelse continue;
        if (term_trimmed.len > 0 and !containsAsciiCaseInsensitive(name, term_trimmed) and !containsAsciiCaseInsensitive(alias, term_trimmed)) continue;
        const subtitle = if (alias.len > 0)
            try std.fmt.allocPrint(allocator, "alias: {s}", .{alias})
        else
            try allocator.dupe(u8, "emoji");
        defer allocator.free(subtitle);
        const action = try std.fmt.allocPrint(allocator, "emoji-copy:{s}", .{emoji});
        defer allocator.free(action);
        const kept_title = try keepDynamicString(dynamic_owned, allocator, name);
        const kept_subtitle = try keepDynamicString(dynamic_owned, allocator, subtitle);
        const kept_action = try keepDynamicString(dynamic_owned, allocator, action);
        const kept_icon = try keepDynamicString(dynamic_owned, allocator, emoji);
        try out.append(allocator, search.Candidate.initWithIcon(.hint, kept_title, kept_subtitle, kept_action, kept_icon));
        emitted_count += 1;
    }
    std.log.info("emoji collect done term={s} parsed_lines={d} emitted={d}", .{ term_trimmed, parsed_count, emitted_count });
}

fn resolveNerdIconSourcePath(allocator: std.mem.Allocator) ![]u8 {
    if (std.process.getEnvVarOwned(allocator, "GOD_SEARCH_NERD_ICONS_FILE")) |path| {
        return path;
    } else |_| {}
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, nerd_icons_default_rel_path });
}

fn parseNerdIconLine(line: []const u8) ?struct { []const u8, []const u8, []const u8 } {
    const sep = std.mem.indexOf(u8, line, " - ") orelse return null;
    const left = std.mem.trim(u8, line[0..sep], " \t");
    const right = std.mem.trim(u8, line[sep + 3 ..], " \t");
    const first_space = std.mem.indexOfScalar(u8, left, ' ') orelse return null;
    const glyph = std.mem.trim(u8, left[0..first_space], " \t");
    const alias = std.mem.trim(u8, left[first_space + 1 ..], " \t");
    if (glyph.len == 0 or alias.len == 0 or right.len == 0) return null;
    return .{ glyph, alias, right };
}

fn parseEmojiTranslitLine(line: []const u8) ?struct { []const u8, []const u8, []const u8 } {
    const pct_idx = std.mem.indexOfScalar(u8, line, '%') orelse return null;
    const head = std.mem.trim(u8, line[0..pct_idx], " \t");
    const name = std.mem.trim(u8, line[pct_idx + 1 ..], " \t");
    if (head.len == 0 or name.len == 0) return null;
    const first_space = std.mem.indexOfScalar(u8, head, ' ') orelse return null;
    const emoji = std.mem.trim(u8, head[0..first_space], " \t");
    const alias_part = std.mem.trim(u8, head[first_space + 1 ..], " \t");
    const alias = std.mem.trim(u8, alias_part, "\"");
    if (emoji.len == 0) return null;
    return .{ emoji, alias, name };
}

fn containsAsciiCaseInsensitive(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    return std.ascii.indexOfIgnoreCase(haystack, needle) != null;
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

test "collectForRoute returns notifications candidates for notifications route" {
    const allocator = std.testing.allocator;
    notifications.runtime.resetForTest(allocator);
    defer notifications.runtime.resetForTest(allocator);

    try notifications.runtime.recordNotify(
        allocator,
        42,
        "notify-send",
        "build done",
        "all green",
        1,
        false,
    );

    var dynamic_owned = std.ArrayListUnmanaged([]u8){};
    defer {
        for (dynamic_owned.items) |item| allocator.free(item);
        dynamic_owned.deinit(allocator);
    }
    var out = search.CandidateList.empty;
    defer out.deinit(allocator);
    var tool_state = ToolState{};

    try collectForRoute(&tool_state, &dynamic_owned, allocator, search.parseQuery("$ build"), &out);
    try std.testing.expect(out.items.len >= 1);
}

fn isCacheFresh(last_checked_ns: i128, now_ns: i128) bool {
    if (last_checked_ns <= 0 or now_ns <= 0) return false;
    const elapsed = now_ns - last_checked_ns;
    return elapsed >= 0 and elapsed < tool_state_refresh_ttl_ns;
}

fn fdAvailable(state: *ToolState) bool {
    const now_ns = std.time.nanoTimestamp();
    if (state.fd_available) |value| {
        if (isCacheFresh(state.fd_last_checked_ns, now_ns)) return value;
    }
    const previous = state.fd_available;
    const value = tool_check.commandExists("fd");
    state.fd_available = value;
    state.fd_last_checked_ns = now_ns;
    if (previous != null and previous.? != value) {
        std.log.info("dynamic tool availability changed tool=fd available={}", .{value});
    }
    return value;
}

fn rgAvailable(state: *ToolState) bool {
    const now_ns = std.time.nanoTimestamp();
    if (state.rg_available) |value| {
        if (isCacheFresh(state.rg_last_checked_ns, now_ns)) return value;
    }
    const previous = state.rg_available;
    const value = tool_check.commandExists("rg");
    state.rg_available = value;
    state.rg_last_checked_ns = now_ns;
    if (previous != null and previous.? != value) {
        std.log.info("dynamic tool availability changed tool=rg available={}", .{value});
    }
    return value;
}

fn rgIncludeHidden(state: *ToolState) bool {
    const now_ns = std.time.nanoTimestamp();
    if (state.rg_include_hidden) |value| {
        if (isCacheFresh(state.rg_hidden_last_checked_ns, now_ns)) return value;
    }
    const previous = state.rg_include_hidden;
    const value = runtime_tools.grepIncludeHidden();
    state.rg_include_hidden = value;
    state.rg_hidden_last_checked_ns = now_ns;
    if (previous != null and previous.? != value) {
        std.log.info("dynamic hidden mode changed rg_hidden={}", .{value});
    }
    return value;
}

const PackageSearchCmd = enum {
    yay,
    pacman,
};

fn packageSearchCommand() PackageSearchCmd {
    return switch (runtime_tools.packageManager()) {
        .yay => .yay,
        .pacman => .pacman,
    };
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
    return runShellCaptureBounded(allocator, command, 8 * 1024 * 1024);
}

fn runShellCaptureBounded(allocator: std.mem.Allocator, command: []const u8, max_output_bytes: usize) ![]u8 {
    return runShellCaptureBoundedWithAllowExitOne(allocator, command, max_output_bytes, false);
}

fn runShellCaptureBoundedWithAllowExitOne(
    allocator: std.mem.Allocator,
    command: []const u8,
    max_output_bytes: usize,
    allow_exit_one: bool,
) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "sh", "-lc", command },
        .max_output_bytes = max_output_bytes,
    });
    defer allocator.free(result.stderr);
    if (result.term != .Exited) {
        allocator.free(result.stdout);
        return error.CommandFailed;
    }
    if (result.term.Exited != 0 and !(allow_exit_one and result.term.Exited == 1)) {
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

test "runShellCaptureBoundedWithAllowExitOne accepts exit code 1 when enabled" {
    const out = try runShellCaptureBoundedWithAllowExitOne(std.testing.allocator, "exit 1", 1024, true);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqual(@as(usize, 0), out.len);
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

test "invalidateToolStateCache resets tool state cache entries" {
    var state = ToolState{
        .fd_available = false,
        .rg_available = false,
        .rg_include_hidden = false,
        .fd_last_checked_ns = 12,
        .rg_last_checked_ns = 34,
        .rg_hidden_last_checked_ns = 56,
    };

    invalidateToolStateCache(&state);

    try std.testing.expect(state.fd_available == null);
    try std.testing.expect(state.rg_available == null);
    try std.testing.expect(state.rg_include_hidden == null);
    try std.testing.expectEqual(@as(i128, 0), state.fd_last_checked_ns);
    try std.testing.expectEqual(@as(i128, 0), state.rg_last_checked_ns);
    try std.testing.expectEqual(@as(i128, 0), state.rg_hidden_last_checked_ns);
}
