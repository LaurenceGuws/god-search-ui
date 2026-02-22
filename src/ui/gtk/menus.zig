const std = @import("std");
const common_dispatch = @import("../common/dispatch.zig");
const gtk_types = @import("types.zig");
const gtk_widgets = @import("widgets.zig");
const gtk_actions = @import("actions.zig");

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const CandidateKind = gtk_types.CandidateKind;
const UiContext = gtk_types.UiContext;

pub const Hooks = struct {
    set_status: *const fn (*UiContext, []const u8) void,
    select_first: *const fn (*UiContext) void,
};

pub fn showDirActionMenu(ctx: *UiContext, allocator: std.mem.Allocator, dir_path: []const u8, hooks: Hooks) void {
    gtk_widgets.clearList(ctx.list);
    gtk_widgets.appendHeaderRow(ctx.list, "Directory Actions");
    const path_msg = std.fmt.allocPrint(allocator, "Target: {s}", .{dir_path}) catch return;
    defer allocator.free(path_msg);
    gtk_widgets.appendInfoRow(ctx.list, path_msg);
    gtk_widgets.appendInfoRow(ctx.list, "Enter to run selected action | Esc to close | Type to return to search");

    const term_cmd = gtk_actions.buildDirTerminalCommand(allocator, dir_path) catch null;
    if (term_cmd) |cmd| {
        defer allocator.free(cmd);
        appendOptionRow(ctx.list, allocator, .dir, "DIR", "dir_option", "Open Terminal Here", "Launch terminal in this folder", cmd);
    }

    const explorer_cmd = gtk_actions.buildDirExplorerCommand(allocator, dir_path) catch null;
    if (explorer_cmd) |cmd| {
        defer allocator.free(cmd);
        appendOptionRow(ctx.list, allocator, .dir, "DIR", "dir_option", "Open in File Explorer", "Use default file manager", cmd);
    }

    const editor_cmd = gtk_actions.buildDirEditorCommand(allocator, dir_path) catch null;
    if (editor_cmd) |cmd| {
        defer allocator.free(cmd);
        appendOptionRow(ctx.list, allocator, .dir, "DIR", "dir_option", "Open in Editor", "Use $VISUAL/$EDITOR fallback", cmd);
    }

    const copy_cmd = gtk_actions.buildDirCopyPathCommand(allocator, dir_path) catch null;
    if (copy_cmd) |cmd| {
        defer allocator.free(cmd);
        appendOptionRow(ctx.list, allocator, .dir, "DIR", "dir_option", "Copy Path", "Copy directory path to clipboard", cmd);
    }

    hooks.set_status(ctx, "Directory action menu");
    hooks.select_first(ctx);
}

pub fn showFileActionMenu(ctx: *UiContext, allocator: std.mem.Allocator, file_action: []const u8, hooks: Hooks) void {
    const parsed = gtk_actions.parseFileAction(file_action);
    gtk_widgets.clearList(ctx.list);
    gtk_widgets.appendHeaderRow(ctx.list, "File Actions");
    const target_msg = std.fmt.allocPrint(allocator, "Target: {s}", .{parsed.path}) catch return;
    defer allocator.free(target_msg);
    gtk_widgets.appendInfoRow(ctx.list, target_msg);
    gtk_widgets.appendInfoRow(ctx.list, "Enter to run selected action | Esc to close | Type to return to search");

    const edit_cmd = gtk_actions.buildFileEditCommand(allocator, parsed.path, parsed.line) catch null;
    if (edit_cmd) |cmd| {
        defer allocator.free(cmd);
        appendOptionRow(ctx.list, allocator, .file, "FILE", "file_option", "Open in Editor", "Use $VISUAL/$EDITOR (line-aware when possible)", cmd);
    }

    const open_cmd = gtk_actions.buildFileOpenCommand(allocator, parsed.path) catch null;
    if (open_cmd) |cmd| {
        defer allocator.free(cmd);
        appendOptionRow(ctx.list, allocator, .file, "FILE", "file_option", "Open with Default App", "Use xdg-open", cmd);
    }

    const reveal_cmd = gtk_actions.buildFileRevealCommand(allocator, parsed.path) catch null;
    if (reveal_cmd) |cmd| {
        defer allocator.free(cmd);
        appendOptionRow(ctx.list, allocator, .file, "FILE", "file_option", "Reveal in File Explorer", "Open parent directory", cmd);
    }

    const copy_cmd = gtk_actions.buildFileCopyPathCommand(allocator, parsed.path) catch null;
    if (copy_cmd) |cmd| {
        defer allocator.free(cmd);
        appendOptionRow(ctx.list, allocator, .file, "FILE", "file_option", "Copy Path", "Copy file path to clipboard", cmd);
    }

    hooks.set_status(ctx, "File action menu");
    hooks.select_first(ctx);
}

fn appendOptionRow(
    list: *c.GtkListBox,
    allocator: std.mem.Allocator,
    kind: CandidateKind,
    chip_text: []const u8,
    kind_tag: []const u8,
    title: []const u8,
    subtitle: []const u8,
    command: []const u8,
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

    const icon_text_z = allocator.dupeZ(u8, gtk_widgets.kindIcon(kind)) catch return;
    defer allocator.free(icon_text_z);
    const icon = c.gtk_label_new(icon_text_z.ptr);
    c.gtk_widget_add_css_class(icon, "gs-kind-icon");
    c.gtk_widget_set_valign(icon, c.GTK_ALIGN_CENTER);

    const chip_z = allocator.dupeZ(u8, chip_text) catch return;
    defer allocator.free(chip_z);
    const chip = c.gtk_label_new(chip_z.ptr);
    c.gtk_widget_add_css_class(chip, "gs-chip");
    switch (kind) {
        .dir => c.gtk_widget_add_css_class(chip, "gs-chip-dir"),
        .file => c.gtk_widget_add_css_class(chip, "gs-chip-file"),
        else => {},
    }
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

    const action_z = allocator.dupeZ(u8, command) catch return;
    defer allocator.free(action_z);
    const title_z = allocator.dupeZ(u8, title) catch return;
    defer allocator.free(title_z);
    c.g_object_set_data(@ptrCast(row), "gs-kind-id", @ptrFromInt(@intFromEnum(common_dispatch.kinds.parse(kind_tag)) + 1));
    c.g_object_set_data_full(@ptrCast(row), "gs-action", c.g_strdup(action_z.ptr), c.g_free);
    c.g_object_set_data_full(@ptrCast(row), "gs-title", c.g_strdup(title_z.ptr), c.g_free);
    c.gtk_list_box_append(@ptrCast(list), row);
}
