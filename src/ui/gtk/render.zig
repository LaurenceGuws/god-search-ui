const std = @import("std");
const common_dispatch = @import("../common/dispatch.zig");
const gtk_types = @import("types.zig");
const gtk_row_data = @import("row_data.zig");
const gtk_widgets = @import("widgets.zig");
const gtk_query = @import("query_helpers.zig");
const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const CandidateKind = gtk_types.CandidateKind;
const UiContext = gtk_types.UiContext;
const ScoredCandidate = @import("../../search/mod.zig").ScoredCandidate;
const UiKind = common_dispatch.kinds.UiKind;

pub const Hooks = struct {
    candidate_icon_widget: *const fn (allocator: std.mem.Allocator, kind: CandidateKind, action: []const u8, icon: []const u8) *c.GtkWidget,
};

pub fn computeRenderHash(
    query_trimmed: []const u8,
    route_hint: ?[]const u8,
    rows: []const ScoredCandidate,
    total_len: usize,
) u64 {
    var h = std.hash.Wyhash.init(0);
    h.update(query_trimmed);
    if (route_hint) |hint| h.update(hint);
    var len_buf: [32]u8 = undefined;
    const len_txt = std.fmt.bufPrint(&len_buf, "{d}", .{total_len}) catch "";
    h.update(len_txt);
    for (rows) |row| {
        h.update(kindTag(row.candidate.kind));
        h.update(row.candidate.title);
        h.update(row.candidate.subtitle);
        h.update(row.candidate.action);
    }
    return h.final();
}

pub fn appendGroupedRows(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    rows: []const ScoredCandidate,
    highlight_token: []const u8,
    hooks: Hooks,
) void {
    var rendered_any = false;
    rendered_any = appendGroup(ctx, allocator, rows, .app, "Apps", rendered_any, highlight_token, hooks) or rendered_any;
    rendered_any = appendGroup(ctx, allocator, rows, .window, "Windows", rendered_any, highlight_token, hooks) or rendered_any;
    rendered_any = appendGroup(ctx, allocator, rows, .workspace, "Workspaces", rendered_any, highlight_token, hooks) or rendered_any;
    rendered_any = appendGroup(ctx, allocator, rows, .dir, "Directories", rendered_any, highlight_token, hooks) or rendered_any;
    rendered_any = appendGroup(ctx, allocator, rows, .file, "Files", rendered_any, highlight_token, hooks) or rendered_any;
    rendered_any = appendGroup(ctx, allocator, rows, .grep, "Code Search", rendered_any, highlight_token, hooks) or rendered_any;
    rendered_any = appendGroup(ctx, allocator, rows, .web, "Web", rendered_any, highlight_token, hooks) or rendered_any;
    rendered_any = appendGroup(ctx, allocator, rows, .action, "Actions", rendered_any, highlight_token, hooks) or rendered_any;
    _ = appendGroup(ctx, allocator, rows, .hint, "Hints", rendered_any, highlight_token, hooks);
}

fn appendGroup(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    rows: []const ScoredCandidate,
    kind: CandidateKind,
    title: []const u8,
    add_separator: bool,
    highlight_token: []const u8,
    hooks: Hooks,
) bool {
    var match_count: usize = 0;
    for (rows) |row| {
        if (row.candidate.kind == kind) {
            match_count += 1;
        }
    }
    if (match_count == 0) return false;

    if (add_separator) gtk_widgets.appendSectionSeparatorRow(ctx.list);
    var header_buf: [96]u8 = undefined;
    const header = std.fmt.bufPrint(&header_buf, "{s} ({d})", .{ title, match_count }) catch title;
    gtk_widgets.appendHeaderRow(ctx.list, header);
    for (rows) |row| {
        if (row.candidate.kind != kind) continue;
        appendCandidateRow(ctx.list, allocator, row, highlight_token, hooks);
    }
    return true;
}

fn appendCandidateRow(
    list: *c.GtkListBox,
    allocator: std.mem.Allocator,
    row: ScoredCandidate,
    highlight_token: []const u8,
    hooks: Hooks,
) void {
    const title_markup = gtk_query.highlightedMarkup(allocator, row.candidate.title, highlight_token) catch return;
    defer allocator.free(title_markup);
    const primary_markup = std.fmt.allocPrint(
        allocator,
        "<span weight=\"600\">{s}</span>",
        .{title_markup},
    ) catch return;
    defer allocator.free(primary_markup);
    const primary_markup_z = allocator.dupeZ(u8, primary_markup) catch return;
    defer allocator.free(primary_markup_z);

    const primary_label = c.gtk_label_new(null);
    c.gtk_label_set_markup(@ptrCast(primary_label), primary_markup_z.ptr);
    c.gtk_label_set_xalign(@ptrCast(primary_label), 0.0);
    c.gtk_label_set_ellipsize(@ptrCast(primary_label), c.PANGO_ELLIPSIZE_END);
    c.gtk_label_set_single_line_mode(@ptrCast(primary_label), GTRUE);
    c.gtk_widget_set_hexpand(primary_label, GTRUE);
    c.gtk_widget_add_css_class(primary_label, "gs-candidate-primary");

    const icon_widget = hooks.candidate_icon_widget(allocator, row.candidate.kind, row.candidate.action, row.candidate.icon);
    c.gtk_widget_set_valign(icon_widget, c.GTK_ALIGN_CENTER);
    const chip = gtk_widgets.kindChipWidget(row.candidate.kind);
    c.gtk_widget_set_valign(chip, c.GTK_ALIGN_CENTER);
    const primary_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
    c.gtk_widget_add_css_class(primary_row, "gs-primary-row");
    c.gtk_box_append(@ptrCast(primary_row), primary_label);
    c.gtk_box_append(@ptrCast(primary_row), chip);

    const subtitle_markup = gtk_query.highlightedMarkup(allocator, row.candidate.subtitle, highlight_token) catch return;
    defer allocator.free(subtitle_markup);
    const subtitle_markup_z = allocator.dupeZ(u8, subtitle_markup) catch return;
    defer allocator.free(subtitle_markup_z);
    const secondary_label = c.gtk_label_new(null);
    c.gtk_label_set_markup(@ptrCast(secondary_label), subtitle_markup_z.ptr);
    c.gtk_label_set_xalign(@ptrCast(secondary_label), 0.0);
    c.gtk_label_set_ellipsize(@ptrCast(secondary_label), c.PANGO_ELLIPSIZE_END);
    c.gtk_label_set_single_line_mode(@ptrCast(secondary_label), GTRUE);
    c.gtk_label_set_max_width_chars(@ptrCast(secondary_label), 64);
    c.gtk_widget_add_css_class(secondary_label, "gs-candidate-secondary");

    const text_col = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 2);
    c.gtk_widget_set_margin_top(text_col, 2);
    c.gtk_widget_set_margin_bottom(text_col, 2);
    c.gtk_widget_add_css_class(text_col, "gs-candidate-content");
    c.gtk_widget_set_hexpand(text_col, GTRUE);
    c.gtk_box_append(@ptrCast(text_col), primary_row);
    c.gtk_box_append(@ptrCast(text_col), secondary_label);

    const content = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
    c.gtk_widget_add_css_class(content, "gs-entry-layout");
    c.gtk_box_append(@ptrCast(content), icon_widget);
    c.gtk_box_append(@ptrCast(content), text_col);

    const list_row = c.gtk_list_box_row_new();
    c.gtk_widget_add_css_class(list_row, "gs-actionable-row");
    c.gtk_list_box_row_set_child(@ptrCast(list_row), content);

    const ui_kind = common_dispatch.kinds.fromCandidateKind(row.candidate.kind);
    gtk_row_data.setActionableData(@ptrCast(@alignCast(list_row)), allocator, ui_kind, row.candidate.action, row.candidate.title);
    const title_tip = allocator.dupeZ(u8, row.candidate.title) catch null;
    if (title_tip) |tip| {
        defer allocator.free(tip);
        c.gtk_widget_set_tooltip_text(primary_label, tip.ptr);
    }
    const subtitle_tip = allocator.dupeZ(u8, row.candidate.subtitle) catch null;
    if (subtitle_tip) |tip| {
        defer allocator.free(tip);
        c.gtk_widget_set_tooltip_text(secondary_label, tip.ptr);
    }
    c.gtk_list_box_append(@ptrCast(list), list_row);
}

fn kindTag(kind: CandidateKind) []const u8 {
    return common_dispatch.kinds.tag(common_dispatch.kinds.fromCandidateKind(kind));
}
