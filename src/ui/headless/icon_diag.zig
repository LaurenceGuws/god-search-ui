const std = @import("std");
const app = @import("../../app/mod.zig");

pub fn printIconDiagnostics(allocator: std.mem.Allocator, writer: anytype, service: *app.SearchService, json: bool) !void {
    const ranked = try service.searchQuery(allocator, "");
    defer allocator.free(ranked);

    var app_count: usize = 0;
    var with_icon_metadata: usize = 0;
    var with_action_icon_token: usize = 0;
    var likely_glyph_fallback: usize = 0;
    var glyph_samples = std.ArrayList([]u8).empty;
    defer {
        for (glyph_samples.items) |item| allocator.free(item);
        glyph_samples.deinit(allocator);
    }

    for (ranked) |row| {
        if (row.candidate.kind != .app) continue;
        app_count += 1;

        const icon_trimmed = std.mem.trim(u8, row.candidate.icon, " \t\r\n");
        if (icon_trimmed.len > 0) {
            with_icon_metadata += 1;
            continue;
        }

        if (actionCommandToken(row.candidate.action).len > 0) {
            with_action_icon_token += 1;
        } else {
            likely_glyph_fallback += 1;
            if (glyph_samples.items.len < 5) {
                const sample = try std.fmt.allocPrint(allocator, "{s} ({s})", .{ row.candidate.title, row.candidate.action });
                try glyph_samples.append(allocator, sample);
            }
        }
    }

    const metadata_pct = percent(with_icon_metadata, app_count);
    const fallback_pct = percent(likely_glyph_fallback, app_count);
    if (json) {
        try writer.print(
            "{{\"apps_total\":{d},\"with_icon_metadata\":{d},\"with_command_token_icon\":{d},\"likely_glyph_fallback\":{d},\"metadata_coverage_pct\":{d:.2},\"glyph_fallback_pct\":{d:.2},\"glyph_fallback_samples\":[",
            .{ app_count, with_icon_metadata, with_action_icon_token, likely_glyph_fallback, metadata_pct, fallback_pct },
        );
        for (glyph_samples.items, 0..) |sample, idx| {
            if (idx > 0) try writer.print(",", .{});
            try writeJsonString(writer, sample);
        }
        try writer.print("]}}\n", .{});
        return;
    }

    try writer.print("  icon diagnostics:\n", .{});
    try writer.print("    apps total: {d}\n", .{app_count});
    try writer.print("    with icon metadata: {d}\n", .{with_icon_metadata});
    try writer.print("    with command-token icon fallback: {d}\n", .{with_action_icon_token});
    try writer.print("    likely glyph fallback: {d}\n", .{likely_glyph_fallback});
    try writer.print("    metadata coverage: {d:.2}%\n", .{metadata_pct});
    try writer.print("    glyph fallback ratio: {d:.2}%\n", .{fallback_pct});
    if (glyph_samples.items.len > 0) {
        try writer.print("    glyph fallback samples:\n", .{});
        for (glyph_samples.items) |sample| {
            try writer.print("      - {s}\n", .{sample});
        }
    }
}

fn percent(part: usize, total: usize) f64 {
    if (total == 0) return 0;
    return (@as(f64, @floatFromInt(part)) * 100.0) / @as(f64, @floatFromInt(total));
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.print("\"", .{});
    for (value) |ch| {
        switch (ch) {
            '"' => try writer.print("\\\"", .{}),
            '\\' => try writer.print("\\\\", .{}),
            '\n' => try writer.print("\\n", .{}),
            '\r' => try writer.print("\\r", .{}),
            '\t' => try writer.print("\\t", .{}),
            else => try writer.print("{c}", .{ch}),
        }
    }
    try writer.print("\"", .{});
}

fn actionCommandToken(action: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, action, " \t\r\n");
    if (trimmed.len == 0) return "";

    var words = std.mem.tokenizeAny(u8, trimmed, " \t\r\n");
    while (words.next()) |word_raw| {
        var word = std.mem.trim(u8, word_raw, "\"'");
        if (word.len == 0) continue;
        if (std.mem.eql(u8, word, "env")) continue;
        if (word[0] == '%') continue;
        if (word[0] == '-') continue;
        if (std.mem.indexOfScalar(u8, word, '=') != null and word[0] != '/' and !std.mem.startsWith(u8, word, "./")) continue;

        if (std.mem.lastIndexOfScalar(u8, word, '/')) |slash_idx| {
            if (slash_idx + 1 < word.len) word = word[slash_idx + 1 ..];
        }
        return word;
    }
    return "";
}
