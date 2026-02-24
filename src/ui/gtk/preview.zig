const std = @import("std");
const common_dispatch = @import("../common/dispatch.zig");
const gtk_types = @import("types.zig");
const gtk_row_data = @import("row_data.zig");
const gtk_query = @import("query_helpers.zig");

const c = gtk_types.c;
const UiContext = gtk_types.UiContext;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const UiKind = common_dispatch.kinds.UiKind;

pub fn toggle(ctx: *UiContext) void {
    const next = if (ctx.preview_enabled == GTRUE) GFALSE else GTRUE;
    setEnabled(ctx, next == GTRUE);
    if (next == GTRUE) {
        refreshFromSelection(ctx);
    }
}

pub fn setEnabled(ctx: *UiContext, enabled: bool) void {
    ctx.preview_enabled = if (enabled) GTRUE else GFALSE;
    c.gtk_widget_set_visible(ctx.preview_panel, ctx.preview_enabled);
    if (ctx.preview_enabled == GFALSE) {
        ctx.last_preview_hash = 0;
    }
}

pub fn clear(ctx: *UiContext) void {
    if (ctx.preview_enabled == GFALSE) return;
    setMarkupIfChanged(ctx, "<span foreground=\"#7c8498\">No selection</span>");
}

pub fn refreshFromSelection(ctx: *UiContext) void {
    if (ctx.preview_enabled == GFALSE) return;
    const row = c.gtk_list_box_get_selected_row(ctx.list) orelse {
        clear(ctx);
        return;
    };
    updateForRow(ctx, row);
}

pub fn updateForRow(ctx: *UiContext, row: *c.GtkListBoxRow) void {
    if (ctx.preview_enabled == GFALSE) return;

    const kind = gtk_row_data.kind(row);
    const title = gtk_row_data.title(row) orelse "";
    const subtitle = gtk_row_data.subtitle(row) orelse "";
    const action = gtk_row_data.action(row) orelse "";

    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    const markup = buildPreviewMarkup(allocator, kind, title, subtitle, action) catch return;
    defer allocator.free(markup);
    setMarkupIfChanged(ctx, markup);
}

fn setMarkupIfChanged(ctx: *UiContext, markup: []const u8) void {
    const h = std.hash.Wyhash.hash(0, markup);
    if (ctx.last_preview_hash == h) return;
    const z = std.heap.page_allocator.dupeZ(u8, markup) catch return;
    defer std.heap.page_allocator.free(z);
    c.gtk_label_set_markup(ctx.preview_label, z.ptr);
    ctx.last_preview_hash = h;
}

fn buildPreviewMarkup(
    allocator: std.mem.Allocator,
    kind: UiKind,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
) ![]u8 {
    const kind_text = common_dispatch.kinds.statusLabel(kind);
    const title_esc = try gtk_query.escapeMarkupAlloc(allocator, if (title.len > 0) title else "(untitled)");
    defer allocator.free(title_esc);
    const subtitle_trim = std.mem.trim(u8, subtitle, " \t\r\n");
    const action_trim = std.mem.trim(u8, action, " \t\r\n");
    const subtitle_esc = if (subtitle_trim.len > 0) try gtk_query.escapeMarkupAlloc(allocator, subtitle_trim) else null;
    defer if (subtitle_esc) |s| allocator.free(s);
    const action_esc = if (showAction(kind, action_trim)) try gtk_query.escapeMarkupAlloc(allocator, action_trim) else null;
    defer if (action_esc) |s| allocator.free(s);

    var body = std.ArrayList(u8).empty;
    defer body.deinit(allocator);
    const w = body.writer(allocator);

    try w.print("<span foreground=\"#7c8498\" weight=\"700\">{s}</span>\n", .{kind_text});
    try w.print("<span foreground=\"#f1f5ff\" weight=\"700\" size=\"large\">{s}</span>", .{title_esc});

    if (subtitle_esc) |sub| {
        try w.print("\n\n<span foreground=\"#9aa1b5\" weight=\"700\">Details</span>\n<span foreground=\"#cdd5e8\">{s}</span>", .{sub});
    }

    if (action_esc) |act| {
        try w.print("\n\n<span foreground=\"#9aa1b5\" weight=\"700\">Action</span>\n<span foreground=\"#b6c2df\" font_family=\"monospace\">{s}</span>", .{act});
    }

    if (kind == .hint and std.mem.startsWith(u8, action_trim, "calc-copy:")) {
        const value = action_trim["calc-copy:".len..];
        const value_esc = try gtk_query.escapeMarkupAlloc(allocator, value);
        defer allocator.free(value_esc);
        try w.print("\n\n<span foreground=\"#7fb0ff\">Enter copies result to clipboard</span>\n<span foreground=\"#f8fbff\" weight=\"700\">{s}</span>", .{value_esc});
    }

    if (kind == .module) {
        try w.print("\n\n<span foreground=\"#7fb0ff\">Enter activates module filter</span>", .{});
    }

    return body.toOwnedSlice(allocator);
}

fn showAction(kind: UiKind, action: []const u8) bool {
    if (action.len == 0) return false;
    return switch (kind) {
        .module => true,
        .hint => std.mem.startsWith(u8, action, "calc-copy:"),
        else => true,
    };
}

test "showAction hides empty and unrelated hints" {
    try std.testing.expect(!showAction(.hint, ""));
    try std.testing.expect(showAction(.hint, "calc-copy:7"));
    try std.testing.expect(!showAction(.hint, "just-a-hint"));
    try std.testing.expect(showAction(.workspace, "1"));
}
