const std = @import("std");
const common_dispatch = @import("../common/dispatch.zig");
const gtk_types = @import("types.zig");
const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const CandidateKind = gtk_types.CandidateKind;

pub fn appendModuleFilterMenu(list: *c.GtkListBox, allocator: std.mem.Allocator) void {
    appendHeaderRow(list, "Quick Modules");
    appendInfoRow(list, "Pick a module (Enter) or type directly for blended search.");
    appendLegendRow(list, "Hotkeys: Enter select | Ctrl+L focus | PgUp/PgDn move | Home/End jump | Ctrl+R refresh | Esc close");

    appendModuleFilterRow(list, allocator, "Apps", "Launch installed applications", "@", "@", .app);
    appendModuleFilterRow(list, allocator, "Windows", "Focus open windows", "#", "#", .window);
    appendModuleFilterRow(list, allocator, "Recent Dirs", "Jump to zoxide terminal locations", "~", "~", .dir);
    appendModuleFilterRow(list, allocator, "Files + Folders", "Find paths with fd", "%", "%", .file);
    appendModuleFilterRow(list, allocator, "Code Search", "Search file contents with rg", "&", "&", .grep);
    appendModuleFilterRow(list, allocator, "Run Command", "Execute a shell command", ">", ">", .action);
    appendModuleFilterRow(list, allocator, "Calculator", "Evaluate an expression", "=", "=", .action);
    appendModuleFilterRow(list, allocator, "Web Search", "Search the web", "?", "?", .action);
}

fn appendModuleFilterRow(
    list: *c.GtkListBox,
    allocator: std.mem.Allocator,
    title: []const u8,
    subtitle: []const u8,
    route: []const u8,
    chip_text: []const u8,
    kind: CandidateKind,
) void {
    const title_markup = std.fmt.allocPrint(allocator, "<span weight=\"600\">{s}</span>", .{title}) catch return;
    defer allocator.free(title_markup);
    const title_markup_z = allocator.dupeZ(u8, title_markup) catch return;
    defer allocator.free(title_markup_z);

    const primary_label = c.gtk_label_new(null);
    c.gtk_label_set_markup(@ptrCast(primary_label), title_markup_z.ptr);
    c.gtk_label_set_xalign(@ptrCast(primary_label), 0.0);
    c.gtk_label_set_ellipsize(@ptrCast(primary_label), c.PANGO_ELLIPSIZE_END);
    c.gtk_label_set_single_line_mode(@ptrCast(primary_label), GTRUE);
    c.gtk_widget_set_hexpand(primary_label, GTRUE);
    c.gtk_widget_add_css_class(primary_label, "gs-candidate-primary");

    const icon_text_z = allocator.dupeZ(u8, kindIcon(kind)) catch return;
    defer allocator.free(icon_text_z);
    const icon = c.gtk_label_new(icon_text_z.ptr);
    c.gtk_widget_add_css_class(icon, "gs-kind-icon");
    c.gtk_widget_set_valign(icon, c.GTK_ALIGN_CENTER);

    const chip = moduleChipWidget(allocator, chip_text, kind);
    c.gtk_widget_set_valign(chip, c.GTK_ALIGN_CENTER);

    const primary_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
    c.gtk_widget_add_css_class(primary_row, "gs-primary-row");
    c.gtk_box_append(@ptrCast(primary_row), primary_label);
    c.gtk_box_append(@ptrCast(primary_row), chip);

    const subtitle_z = allocator.dupeZ(u8, subtitle) catch return;
    defer allocator.free(subtitle_z);
    const secondary_label = c.gtk_label_new(subtitle_z.ptr);
    c.gtk_label_set_xalign(@ptrCast(secondary_label), 0.0);
    c.gtk_label_set_ellipsize(@ptrCast(secondary_label), c.PANGO_ELLIPSIZE_END);
    c.gtk_label_set_single_line_mode(@ptrCast(secondary_label), GTRUE);
    c.gtk_label_set_max_width_chars(@ptrCast(secondary_label), 64);
    c.gtk_widget_add_css_class(secondary_label, "gs-candidate-secondary");

    const text_col = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 2);
    c.gtk_widget_set_margin_top(text_col, 2);
    c.gtk_widget_set_margin_bottom(text_col, 2);
    c.gtk_widget_add_css_class(text_col, "gs-candidate-content");
    c.gtk_box_append(@ptrCast(text_col), primary_row);
    c.gtk_box_append(@ptrCast(text_col), secondary_label);

    const content = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
    c.gtk_widget_add_css_class(content, "gs-entry-layout");
    c.gtk_box_append(@ptrCast(content), icon);
    c.gtk_box_append(@ptrCast(content), text_col);

    const row = c.gtk_list_box_row_new();
    c.gtk_widget_add_css_class(row, "gs-actionable-row");
    c.gtk_list_box_row_set_child(@ptrCast(row), content);

    const action_z = allocator.dupeZ(u8, route) catch return;
    defer allocator.free(action_z);
    const title_z = allocator.dupeZ(u8, title) catch return;
    defer allocator.free(title_z);
    c.g_object_set_data(@ptrCast(row), "gs-kind-id", @ptrFromInt(@intFromEnum(common_dispatch.kinds.UiKind.module) + 1));
    c.g_object_set_data_full(@ptrCast(row), "gs-action", c.g_strdup(action_z.ptr), c.g_free);
    c.g_object_set_data_full(@ptrCast(row), "gs-title", c.g_strdup(title_z.ptr), c.g_free);
    c.gtk_list_box_append(@ptrCast(list), row);
}

pub fn appendInfoRow(list: *c.GtkListBox, message: []const u8) void {
    const msg_z = std.heap.page_allocator.dupeZ(u8, message) catch return;
    defer std.heap.page_allocator.free(msg_z);

    const label = c.gtk_label_new(null);
    c.gtk_label_set_text(@ptrCast(label), msg_z.ptr);
    c.gtk_label_set_xalign(@ptrCast(label), 0.0);
    c.gtk_widget_add_css_class(label, "gs-info");

    const row = c.gtk_list_box_row_new();
    c.gtk_widget_add_css_class(row, "gs-meta-row");
    c.gtk_list_box_row_set_child(@ptrCast(row), label);
    c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
    c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
    c.gtk_list_box_append(@ptrCast(list), row);
}

pub fn appendLegendRow(list: *c.GtkListBox, message: []const u8) void {
    const msg_z = std.heap.page_allocator.dupeZ(u8, message) catch return;
    defer std.heap.page_allocator.free(msg_z);

    const label = c.gtk_label_new(null);
    c.gtk_label_set_text(@ptrCast(label), msg_z.ptr);
    c.gtk_label_set_xalign(@ptrCast(label), 0.0);
    c.gtk_widget_add_css_class(label, "gs-legend");

    const row = c.gtk_list_box_row_new();
    c.gtk_widget_add_css_class(row, "gs-meta-row");
    c.gtk_list_box_row_set_child(@ptrCast(row), label);
    c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
    c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
    c.gtk_list_box_append(@ptrCast(list), row);
}

pub fn appendHeaderRow(list: *c.GtkListBox, title: []const u8) void {
    const title_escaped = c.g_markup_escape_text(title.ptr, @intCast(title.len));
    if (title_escaped == null) return;
    defer c.g_free(title_escaped);

    const markup = std.fmt.allocPrint(std.heap.page_allocator, "<b>{s}</b>", .{std.mem.span(@as([*:0]const u8, @ptrCast(title_escaped)))}) catch return;
    defer std.heap.page_allocator.free(markup);
    const markup_z = std.heap.page_allocator.dupeZ(u8, markup) catch return;
    defer std.heap.page_allocator.free(markup_z);

    const label = c.gtk_label_new(null);
    c.gtk_label_set_markup(@ptrCast(label), markup_z.ptr);
    c.gtk_label_set_xalign(@ptrCast(label), 0.0);
    c.gtk_widget_add_css_class(label, "gs-header");

    const row = c.gtk_list_box_row_new();
    c.gtk_widget_add_css_class(row, "gs-meta-row");
    c.gtk_list_box_row_set_child(@ptrCast(row), label);
    c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
    c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
    c.gtk_list_box_append(@ptrCast(list), row);
}

pub fn appendSectionSeparatorRow(list: *c.GtkListBox) void {
    const separator = c.gtk_separator_new(c.GTK_ORIENTATION_HORIZONTAL);
    c.gtk_widget_add_css_class(separator, "gs-separator");

    const row = c.gtk_list_box_row_new();
    c.gtk_widget_add_css_class(row, "gs-meta-row");
    c.gtk_list_box_row_set_child(@ptrCast(row), separator);
    c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
    c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
    c.gtk_list_box_append(@ptrCast(list), row);
}

pub fn appendAsyncRow(list: *c.GtkListBox, frame: []const u8, message: []const u8) void {
    const markup = std.fmt.allocPrint(
        std.heap.page_allocator,
        "<span foreground=\"#b5d6ff\" size=\"x-large\" weight=\"700\">{s}</span> <span foreground=\"#aeb8cc\">{s}</span>",
        .{ frame, message },
    ) catch return;
    defer std.heap.page_allocator.free(markup);
    const markup_z = std.heap.page_allocator.dupeZ(u8, markup) catch return;
    defer std.heap.page_allocator.free(markup_z);

    const label = c.gtk_label_new(null);
    c.gtk_label_set_markup(@ptrCast(label), markup_z.ptr);
    c.gtk_label_set_xalign(@ptrCast(label), 0.0);
    c.gtk_widget_add_css_class(label, "gs-async-search");

    const row = c.gtk_list_box_row_new();
    c.gtk_widget_add_css_class(row, "gs-meta-row");
    c.gtk_list_box_row_set_child(@ptrCast(row), label);
    c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
    c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
    c.g_object_set_data_full(@ptrCast(row), "gs-async", c.g_strdup("1"), c.g_free);
    c.gtk_list_box_append(@ptrCast(list), row);
}

pub fn clearList(list: *c.GtkListBox) void {
    var child = c.gtk_widget_get_first_child(@ptrCast(@alignCast(list)));
    while (child != null) {
        const next = c.gtk_widget_get_next_sibling(child);
        c.gtk_list_box_remove(list, child);
        child = next;
    }
}

pub fn clearAsyncRows(list: *c.GtkListBox) void {
    var child = c.gtk_widget_get_first_child(@ptrCast(@alignCast(list)));
    while (child != null) {
        const next = c.gtk_widget_get_next_sibling(child);
        if (c.g_object_get_data(@ptrCast(child), "gs-async") != null) {
            c.gtk_list_box_remove(list, child);
        }
        child = next;
    }
}

pub fn kindIcon(kind: CandidateKind) []const u8 {
    return switch (kind) {
        .app => "󰀻",
        .window => "",
        .dir => "󰉋",
        .file => "󰈙",
        .grep => "󰍉",
        .action => "",
        .hint => "󰘥",
    };
}

pub fn kindChipWidget(kind: CandidateKind) *c.GtkWidget {
    const label = c.gtk_label_new(kindChipText(kind).ptr);
    c.gtk_widget_add_css_class(label, "gs-chip");
    switch (kind) {
        .app => c.gtk_widget_add_css_class(label, "gs-chip-app"),
        .window => c.gtk_widget_add_css_class(label, "gs-chip-window"),
        .dir => c.gtk_widget_add_css_class(label, "gs-chip-dir"),
        .file => c.gtk_widget_add_css_class(label, "gs-chip-file"),
        .grep => c.gtk_widget_add_css_class(label, "gs-chip-grep"),
        .action => c.gtk_widget_add_css_class(label, "gs-chip-action"),
        .hint => c.gtk_widget_add_css_class(label, "gs-chip-hint"),
    }
    return @ptrCast(label);
}

pub fn moduleChipWidget(allocator: std.mem.Allocator, chip_text: []const u8, kind: CandidateKind) *c.GtkWidget {
    const chip_text_z = allocator.dupeZ(u8, chip_text) catch return kindChipWidget(kind);
    defer allocator.free(chip_text_z);
    const label = c.gtk_label_new(chip_text_z.ptr);
    c.gtk_widget_add_css_class(label, "gs-chip");
    c.gtk_widget_add_css_class(label, "gs-chip-module-key");
    switch (kind) {
        .app => c.gtk_widget_add_css_class(label, "gs-chip-app"),
        .window => c.gtk_widget_add_css_class(label, "gs-chip-window"),
        .dir => c.gtk_widget_add_css_class(label, "gs-chip-dir"),
        .file => c.gtk_widget_add_css_class(label, "gs-chip-file"),
        .grep => c.gtk_widget_add_css_class(label, "gs-chip-grep"),
        .action => c.gtk_widget_add_css_class(label, "gs-chip-action"),
        .hint => c.gtk_widget_add_css_class(label, "gs-chip-hint"),
    }
    return @ptrCast(label);
}

fn kindChipText(kind: CandidateKind) [:0]const u8 {
    return switch (kind) {
        .app => "APP",
        .window => "WIN",
        .dir => "DIR",
        .file => "FILE",
        .grep => "GREP",
        .action => "ACT",
        .hint => "TIP",
    };
}
