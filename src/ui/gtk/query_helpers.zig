const std = @import("std");
const gtk_types = @import("types.zig");
const c = gtk_types.c;

pub fn searchDebounceMsForQuery(query_trimmed: []const u8) c.guint {
    const query_len = query_trimmed.len;
    if (query_len == 0) return 110;
    if (query_trimmed[0] == '?') {
        const term_len = if (query_len > 1) std.mem.trim(u8, query_trimmed[1..], " \t\r\n").len else 0;
        if (term_len == 0) return 220;
        return 800;
    }
    if (query_len >= 1 and (query_trimmed[0] == '%' or query_trimmed[0] == '&' or query_trimmed[0] == '+' or query_trimmed[0] == '^' or query_trimmed[0] == '*' or query_trimmed[0] == ':')) {
        const term_len = if (query_len > 1) std.mem.trim(u8, query_trimmed[1..], " \t\r\n").len else 0;
        if (term_len <= 1) return 300;
        if (term_len <= 3) return 220;
        return 160;
    }
    if (query_len <= 2) return 90;
    if (query_len <= 5) return 75;
    return 60;
}

pub fn routeIconForLeadingPrefix(query: []const u8) ?[]const u8 {
    if (query.len == 0) return null;
    return switch (query[0]) {
        '@' => "applications-system-symbolic",
        '#' => "window-new-symbolic",
        '!' => "view-grid-symbolic",
        '~' => "folder-symbolic",
        '%' => "text-x-generic-symbolic",
        '&' => "edit-find-symbolic",
        '+' => "system-software-install-symbolic",
        '^' => "image-x-generic-symbolic",
        '*' => "font-x-generic-symbolic",
        ':' => "face-smile-symbolic",
        '$' => "preferences-system-notifications-symbolic",
        '>' => "utilities-terminal-symbolic",
        '=' => "accessories-calculator-symbolic",
        '?' => "web-browser-symbolic",
        else => null,
    };
}

pub fn shouldAsyncRouteQuery(query_trimmed: []const u8) bool {
    if (query_trimmed.len == 1 and (query_trimmed[0] == '*' or query_trimmed[0] == ':')) return true;
    if (query_trimmed.len < 2) return false;
    const route = query_trimmed[0];
    return switch (route) {
        '%', '&', '+', '^', '*', ':', '$', '=', '?' => std.mem.trim(u8, query_trimmed[1..], " \t\r\n").len > 0,
        else => false,
    };
}

pub fn routeHintForQuery(query_trimmed: []const u8) ?[]const u8 {
    if (query_trimmed.len != 1) return null;
    return switch (query_trimmed[0]) {
        '@' => "Apps route active: type app name after @",
        '#' => "Windows route active: type window title/class after #",
        '!' => "Workspaces route active: type workspace name/id after !",
        '~' => "Recent dirs route active: zoxide terminal locations after ~",
        '%' => "Files route active: find files and folders after %",
        '&' => "Grep route active: type text to search after &",
        '+' => "Packages route active: search yay/pacman packages after +",
        '^' => "Icons route active: search icon filenames in installed themes after ^",
        '*' => "Nerd Icons route active: search Nerd Font glyph names after *",
        ':' => "Emoji route active: search emoji names after :",
        '$' => "Notifications route active: search and dismiss notifications after $",
        '>' => "Run route active: type command after >",
        '=' => "Calc route active: type expression after =",
        '?' => "Web route: ? <term>, ?g/?ddg/?w <term>, ?b [query] (browser bookmarks)",
        else => null,
    };
}

pub fn highlightTokenForQuery(query_trimmed: []const u8) []const u8 {
    var token = std.mem.trim(u8, query_trimmed, " \t\r\n");
    if (token.len == 0) return "";
    if (token.len > 1) {
        token = switch (token[0]) {
            '@', '#', '!', '~', '%', '&', '+', '^', '*', ':', '$', '>', '=', '?' => std.mem.trim(u8, token[1..], " \t\r\n"),
            else => token,
        };
    }
    return token;
}

pub fn highlightedMarkup(allocator: std.mem.Allocator, text: []const u8, token: []const u8) ![]u8 {
    if (text.len == 0) return allocator.dupe(u8, "");

    const trimmed_token = std.mem.trim(u8, token, " \t\r\n");
    if (trimmed_token.len == 0) return escapeMarkupAlloc(allocator, text);

    const idx = firstCaseInsensitiveIndex(text, trimmed_token) orelse return escapeMarkupAlloc(allocator, text);
    const head = try escapeMarkupAlloc(allocator, text[0..idx]);
    defer allocator.free(head);
    const hit = try escapeMarkupAlloc(allocator, text[idx .. idx + trimmed_token.len]);
    defer allocator.free(hit);
    const tail = try escapeMarkupAlloc(allocator, text[idx + trimmed_token.len ..]);
    defer allocator.free(tail);

    return std.fmt.allocPrint(allocator, "{s}<b>{s}</b>{s}", .{ head, hit, tail });
}

pub fn postLaunchStatus(message: []const u8) []const u8 {
    if (std.mem.eql(u8, message, "Action launched")) return "Action launched | Enter repeats selected action";
    if (std.mem.eql(u8, message, "App launched")) return "App launched | Enter repeats selected app";
    if (std.mem.eql(u8, message, "Directory opened")) return "Directory opened | Enter repeats selected item";
    if (std.mem.eql(u8, message, "Window focused")) return "Window focused | Enter repeats selected window";
    if (std.mem.eql(u8, message, "Workspace switched")) return "Workspace switched | Enter repeats selected workspace";
    return message;
}

pub fn escapeMarkupAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    const escaped_ptr = c.g_markup_escape_text(text.ptr, @intCast(text.len));
    if (escaped_ptr == null) return error.OutOfMemory;
    defer c.g_free(escaped_ptr);
    const escaped = std.mem.span(@as([*:0]const u8, @ptrCast(escaped_ptr)));
    return allocator.dupe(u8, escaped);
}

fn firstCaseInsensitiveIndex(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or haystack.len < needle.len) return null;
    var idx: usize = 0;
    while (idx + needle.len <= haystack.len) : (idx += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[idx .. idx + needle.len], needle)) return idx;
    }
    return null;
}

test "highlightedMarkup escapes text and highlights first token match" {
    const allocator = std.testing.allocator;
    const markup = try highlightedMarkup(allocator, "Alpha <tag> & omega", "<TAG>");
    defer allocator.free(markup);
    try std.testing.expectEqualStrings("Alpha <b>&lt;tag&gt;</b> &amp; omega", markup);
}

test "highlightedMarkup escapes without highlighting when token missing" {
    const allocator = std.testing.allocator;
    const markup = try highlightedMarkup(allocator, "<b>safe</b> & text", "missing");
    defer allocator.free(markup);
    try std.testing.expectEqualStrings("&lt;b&gt;safe&lt;/b&gt; &amp; text", markup);
}

test "route query prefixes with heavy backends should be async" {
    try std.testing.expect(shouldAsyncRouteQuery("% files"));
    try std.testing.expect(shouldAsyncRouteQuery("& needle"));
    try std.testing.expect(shouldAsyncRouteQuery("+ ripgrep"));
    try std.testing.expect(shouldAsyncRouteQuery("^ arch"));
    try std.testing.expect(shouldAsyncRouteQuery("* git"));
    try std.testing.expect(shouldAsyncRouteQuery(": smile"));
    try std.testing.expect(shouldAsyncRouteQuery("$ one"));
    try std.testing.expect(shouldAsyncRouteQuery("= 2+2"));
    try std.testing.expect(shouldAsyncRouteQuery("? chatgpt"));
}

test "route query prefixes without term should stay sync for hint rendering" {
    try std.testing.expect(!shouldAsyncRouteQuery("%"));
    try std.testing.expect(!shouldAsyncRouteQuery("$"));
    try std.testing.expect(shouldAsyncRouteQuery("*"));
    try std.testing.expect(shouldAsyncRouteQuery(":"));
}
