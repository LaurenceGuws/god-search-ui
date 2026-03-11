const std = @import("std");
const gtk_types = @import("types.zig");
const action_provider = @import("../../providers/actions.zig");

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;

const HelpEntryState = struct {
    key_text: []const u8,
    details: ?[]const []const u8,
    insert_text: ?[]const u8,
    ui_state: *HelpUiState,
    entry: *c.GtkWidget,
    panel: *c.GtkWidget,
};

const HelpToggleState = struct {
    button: *c.GtkWidget,
    panel: *c.GtkWidget,
    ui_state: *HelpUiState,
};

pub const HelpUiState = struct {
    entry: *c.GtkWidget,
    panel: *c.GtkWidget,
    content: *c.GtkWidget,
};

const files_options = [_][]const u8{
    "Files route: % <term>",
    "Powered by fd for quick file and folder lookup.",
    "Includes hidden files/folders by default.",
    "No launcher runtime toggle yet; adjust fd behavior in command-level config.",
};

const grep_options = [_][]const u8{
    "Grep route: & <term>",
    "Uses rg to search file contents.",
    "Default: ignore hidden entries.",
    "Set tools.grep_include_hidden = true in Lua config to include hidden files/dirs.",
};

const packages_options = [_][]const u8{
    "Packages route: + <term>",
    "Searches packages via configured tools.package_manager (Lua).",
    "Filter installed only: +i <term> (or +installed <term>).",
    "Installed packages: Enter updates; extra Remove action is listed.",
    "Install/update/remove use configured package_manager + terminal tools.",
};

const icons_options = [_][]const u8{
    "Icons route: ^ <term>",
    "Searches icon filenames across installed icon themes.",
    "Includes ~/.icons, ~/.local/share/icons, /usr/share/icons and /usr/share/pixmaps.",
    "Select a result to open the icon file path directly.",
};

const nerd_icons_options = [_][]const u8{
    "Nerd Icons route: * <term>",
    "Searches Nerd Font icon names from your icon_finder dataset.",
    "Enter copies the selected glyph to clipboard.",
    "Source file: ~/personal/bash_engine/src/modules/fun/nerd_icons_fzf/icons_simple.txt",
};

const emoji_options = [_][]const u8{
    "Emoji route: : <term>",
    "Searches emoji names from glibc transliteration data.",
    "Enter copies the selected emoji to clipboard.",
    "Source file: /usr/share/i18n/locales/translit_emojis",
};

pub fn build(entry: *c.GtkWidget) ?struct {
    button: *c.GtkWidget,
    panel_row: *c.GtkWidget,
    content: *c.GtkWidget,
} {
    const help_button = c.gtk_button_new_with_label("?");
    c.gtk_widget_add_css_class(help_button, "gs-help-btn");
    c.gtk_widget_set_tooltip_text(help_button, "Search routes and shortcuts");

    const help_content = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 4);
    c.gtk_widget_set_margin_top(help_content, 8);
    c.gtk_widget_set_margin_bottom(help_content, 8);
    c.gtk_widget_set_margin_start(help_content, 10);
    c.gtk_widget_set_margin_end(help_content, 10);

    const help_scroll = c.gtk_scrolled_window_new();
    c.gtk_widget_add_css_class(help_scroll, "gs-help-popover");
    c.gtk_widget_add_css_class(help_scroll, "gs-help-scroll");
    c.gtk_widget_set_size_request(help_scroll, 380, 360);
    c.gtk_scrolled_window_set_policy(@ptrCast(help_scroll), c.GTK_POLICY_NEVER, c.GTK_POLICY_AUTOMATIC);
    c.gtk_scrolled_window_set_overlay_scrolling(@ptrCast(help_scroll), GTRUE);
    c.gtk_scrolled_window_set_child(@ptrCast(help_scroll), help_content);

    const help_panel_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 0);
    c.gtk_widget_set_hexpand(help_panel_row, GTRUE);
    c.gtk_widget_set_visible(help_panel_row, GFALSE);
    c.gtk_widget_set_halign(help_panel_row, c.GTK_ALIGN_FILL);
    c.gtk_widget_set_valign(help_panel_row, c.GTK_ALIGN_START);
    const help_panel_spacer = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 0);
    c.gtk_widget_set_hexpand(help_panel_spacer, GTRUE);
    c.gtk_widget_set_halign(help_scroll, c.GTK_ALIGN_END);
    c.gtk_box_append(@ptrCast(help_panel_row), help_panel_spacer);
    c.gtk_box_append(@ptrCast(help_panel_row), help_scroll);

    const help_ui_state = std.heap.page_allocator.create(HelpUiState) catch return null;
    help_ui_state.* = .{
        .entry = entry,
        .panel = help_panel_row,
        .content = help_content,
    };
    populateHelpMainMenu(help_ui_state);

    const help_toggle_state = std.heap.page_allocator.create(HelpToggleState) catch return null;
    help_toggle_state.* = .{
        .button = help_button,
        .panel = help_panel_row,
        .ui_state = help_ui_state,
    };
    _ = c.g_signal_connect_data(help_button, "clicked", c.G_CALLBACK(onHelpClicked), help_toggle_state, @as(c.GClosureNotify, onHelpToggleStateDestroy), 0);

    return .{
        .button = help_button,
        .panel_row = help_panel_row,
        .content = help_content,
    };
}

fn onHelpClicked(button: ?*c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
    if (button == null or user_data == null) return;
    const state = @as(*HelpToggleState, @ptrCast(@alignCast(user_data.?)));
    const button_width = c.gtk_widget_get_width(state.button);
    const panel_width = c.gtk_widget_get_width(state.panel);
    const is_open = c.gtk_widget_get_visible(state.panel);
    std.log.info("help panel toggle button_w={d} panel_w={d} open={d}", .{ button_width, panel_width, is_open });
    if (is_open == GTRUE) {
        c.gtk_widget_set_visible(state.panel, GFALSE);
    } else {
        populateHelpMainMenu(state.ui_state);
        c.gtk_widget_set_visible(state.panel, GTRUE);
    }
}

fn onHelpItemClicked(button: ?*c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
    if (user_data == null or button == null) return;
    const state = @as(*HelpEntryState, @ptrCast(@alignCast(user_data.?)));
    if (state.details) |lines| {
        std.log.info("help item submenu key={s} details_len={d}", .{ state.key_text, lines.len });
        c.gtk_widget_set_visible(state.panel, GFALSE);
        populateHelpSubmenu(state.ui_state, state.key_text, lines);
        c.gtk_widget_set_visible(state.panel, GTRUE);
        return;
    }
    if (state.insert_text) |prefix| {
        const prefix_z = std.heap.page_allocator.dupeZ(u8, prefix) catch return;
        defer std.heap.page_allocator.free(prefix_z);
        c.gtk_editable_set_text(@ptrCast(state.entry), prefix_z.ptr);
        c.gtk_editable_set_position(@ptrCast(state.entry), -1);
        _ = c.gtk_entry_grab_focus_without_selecting(@ptrCast(@alignCast(state.entry)));
        c.gtk_widget_set_visible(state.panel, GFALSE);
        std.log.info("help item prefix key={s} text={s}", .{ state.key_text, prefix });
    }
}

fn onHelpEntryStateDestroy(data: ?*anyopaque, _: ?*c.GClosure) callconv(.c) void {
    if (data == null) return;
    const state: *HelpEntryState = @ptrCast(@alignCast(data.?));
    std.heap.page_allocator.destroy(state);
}

fn onHelpToggleStateDestroy(data: ?*anyopaque, _: ?*c.GClosure) callconv(.c) void {
    if (data == null) return;
    const state: *HelpToggleState = @ptrCast(@alignCast(data.?));
    std.heap.page_allocator.destroy(state.ui_state);
    std.heap.page_allocator.destroy(state);
}

fn onHelpBackClicked(_: ?*c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
    if (user_data == null) return;
    const ui_state = @as(*HelpUiState, @ptrCast(@alignCast(user_data.?)));
    populateHelpMainMenu(ui_state);
}

fn appendHelpTitle(box: *c.GtkWidget, title: []const u8, subtitle: []const u8) void {
    const title_label = c.gtk_label_new(null);
    c.gtk_label_set_xalign(@ptrCast(title_label), 0.0);
    c.gtk_widget_add_css_class(title_label, "gs-help-title");
    const title_z = std.heap.page_allocator.dupeZ(u8, title) catch return;
    defer std.heap.page_allocator.free(title_z);
    c.gtk_label_set_text(@ptrCast(title_label), title_z.ptr);
    c.gtk_box_append(@ptrCast(box), title_label);

    const subtitle_label = c.gtk_label_new(null);
    c.gtk_label_set_xalign(@ptrCast(subtitle_label), 0.0);
    c.gtk_label_set_wrap(@ptrCast(subtitle_label), GTRUE);
    c.gtk_widget_add_css_class(subtitle_label, "gs-help-subtitle");
    const subtitle_z = std.heap.page_allocator.dupeZ(u8, subtitle) catch return;
    defer std.heap.page_allocator.free(subtitle_z);
    c.gtk_label_set_text(@ptrCast(subtitle_label), subtitle_z.ptr);
    c.gtk_box_append(@ptrCast(box), subtitle_label);
}

fn appendHelpSection(box: *c.GtkWidget, section_name: []const u8) void {
    const section = c.gtk_label_new(null);
    c.gtk_label_set_xalign(@ptrCast(section), 0.0);
    c.gtk_widget_set_margin_top(section, 6);
    c.gtk_widget_add_css_class(section, "gs-help-section");
    const section_z = std.heap.page_allocator.dupeZ(u8, section_name) catch return;
    defer std.heap.page_allocator.free(section_z);
    c.gtk_label_set_text(@ptrCast(section), section_z.ptr);
    c.gtk_box_append(@ptrCast(box), section);
}

fn appendHelpItemWithDetails(box: *c.GtkWidget, key_text: []const u8, description_text: []const u8, details: ?[]const []const u8, insert_text: ?[]const u8, ui_state: *HelpUiState) void {
    const row_button = c.gtk_button_new();
    c.gtk_widget_add_css_class(row_button, "gs-help-row");
    c.gtk_widget_add_css_class(row_button, "gs-help-item-btn");
    c.gtk_widget_set_hexpand(row_button, GTRUE);

    const row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
    c.gtk_widget_set_hexpand(row, GTRUE);

    const key = c.gtk_label_new(null);
    c.gtk_widget_set_size_request(key, 70, -1);
    c.gtk_label_set_xalign(@ptrCast(key), 0.0);
    c.gtk_widget_add_css_class(key, "gs-help-key");
    const key_z = std.heap.page_allocator.dupeZ(u8, key_text) catch return;
    defer std.heap.page_allocator.free(key_z);
    c.gtk_label_set_text(@ptrCast(key), key_z.ptr);

    const desc = c.gtk_label_new(null);
    c.gtk_label_set_xalign(@ptrCast(desc), 0.0);
    c.gtk_label_set_wrap(@ptrCast(desc), GTRUE);
    c.gtk_widget_set_hexpand(desc, GTRUE);
    c.gtk_widget_add_css_class(desc, "gs-help-desc");
    const desc_z = std.heap.page_allocator.dupeZ(u8, description_text) catch return;
    defer std.heap.page_allocator.free(desc_z);
    c.gtk_label_set_text(@ptrCast(desc), desc_z.ptr);

    c.gtk_box_append(@ptrCast(row), key);
    c.gtk_box_append(@ptrCast(row), desc);
    c.gtk_button_set_child(@ptrCast(row_button), @ptrCast(row));

    if (details != null or insert_text != null) {
        const state = std.heap.page_allocator.create(HelpEntryState) catch return;
        state.* = .{
            .key_text = key_text,
            .details = details,
            .insert_text = insert_text,
            .ui_state = ui_state,
            .entry = ui_state.entry,
            .panel = ui_state.panel,
        };
        _ = c.g_signal_connect_data(row_button, "clicked", c.G_CALLBACK(onHelpItemClicked), state, @as(c.GClosureNotify, onHelpEntryStateDestroy), 0);
    }

    c.gtk_box_append(@ptrCast(box), row_button);
}

fn appendHelpItem(box: *c.GtkWidget, key_text: []const u8, description_text: []const u8, ui_state: *HelpUiState) void {
    appendHelpItemWithDetails(box, key_text, description_text, null, null, ui_state);
}

fn appendHelpPrefixItem(box: *c.GtkWidget, key_text: []const u8, description_text: []const u8, ui_state: *HelpUiState) void {
    const insert_text: ?[]const u8 = if (std.mem.eql(u8, key_text, "@")) "@ " else if (std.mem.eql(u8, key_text, "#")) "# " else if (std.mem.eql(u8, key_text, "!")) "! " else if (std.mem.eql(u8, key_text, "~")) "~ " else if (std.mem.eql(u8, key_text, "+")) "+ " else if (std.mem.eql(u8, key_text, "$")) "$ " else if (std.mem.eql(u8, key_text, ">")) "> " else if (std.mem.eql(u8, key_text, "=")) "= " else if (std.mem.eql(u8, key_text, "?")) "? " else null;
    appendHelpItemWithDetails(box, key_text, description_text, null, insert_text, ui_state);
}

fn appendActionsInfo(box: *c.GtkWidget, ui_state: *HelpUiState) void {
    const specs = action_provider.allSpecs();
    for (specs) |spec| {
        var detail = std.ArrayList(u8).empty;
        defer detail.deinit(std.heap.page_allocator);

        const writer = detail.writer(std.heap.page_allocator);
        writer.print("{s}", .{spec.help}) catch continue;
        if (spec.confirm) {
            writer.print(" Requires confirmation.", .{}) catch continue;
        }
        const detail_text = detail.toOwnedSlice(std.heap.page_allocator) catch continue;
        defer std.heap.page_allocator.free(detail_text);
        appendHelpItem(box, spec.title, detail_text, ui_state);
    }
}

fn clearHelpContent(content: *c.GtkWidget) void {
    var child = c.gtk_widget_get_first_child(content);
    while (child != null) : (child = c.gtk_widget_get_first_child(content)) {
        c.gtk_box_remove(@ptrCast(content), child);
    }
}

fn populateHelpMainMenu(ui_state: *HelpUiState) void {
    clearHelpContent(ui_state.content);
    appendHelpTitle(ui_state.content, "Quick Reference", "Routes, commands, and keys");
    appendHelpSection(ui_state.content, "Routes");
    appendHelpPrefixItem(ui_state.content, "@", "Apps", ui_state);
    appendHelpPrefixItem(ui_state.content, "#", "Windows", ui_state);
    appendHelpPrefixItem(ui_state.content, "!", "Workspaces", ui_state);
    appendHelpPrefixItem(ui_state.content, "~", "Recent folders", ui_state);
    appendHelpItemWithDetails(ui_state.content, "%", "Files", &files_options, null, ui_state);
    appendHelpItemWithDetails(ui_state.content, "&", "Grep matches", &grep_options, null, ui_state);
    appendHelpItemWithDetails(ui_state.content, "+", "Packages", &packages_options, null, ui_state);
    appendHelpItemWithDetails(ui_state.content, "^", "Icons", &icons_options, null, ui_state);
    appendHelpItemWithDetails(ui_state.content, "*", "Nerd Icons", &nerd_icons_options, null, ui_state);
    appendHelpItemWithDetails(ui_state.content, ":", "Emoji", &emoji_options, null, ui_state);
    appendHelpPrefixItem(ui_state.content, "$", "Notifications", ui_state);
    appendHelpSection(ui_state.content, "Commands");
    appendHelpPrefixItem(ui_state.content, ">", "Run shell command", ui_state);
    appendHelpPrefixItem(ui_state.content, "=", "Calculator", ui_state);
    appendHelpPrefixItem(ui_state.content, "?", "Web search", ui_state);
    appendHelpSection(ui_state.content, "Hotkeys");
    appendHelpItem(ui_state.content, "Enter", "Launch selected item", ui_state);
    appendHelpItem(ui_state.content, "Ctrl+P", "Toggle preview panel", ui_state);
    appendHelpItem(ui_state.content, "Ctrl+Shift+R", "Reload Lua config", ui_state);
    appendHelpItem(ui_state.content, "Ctrl+R", "Refresh providers", ui_state);
    appendHelpItem(ui_state.content, "PgUp/PgDn", "Move selection", ui_state);
    appendHelpItem(ui_state.content, "Esc", "Close launcher", ui_state);
    appendHelpSection(ui_state.content, "Actions");
    appendActionsInfo(ui_state.content, ui_state);
}

fn populateHelpSubmenu(ui_state: *HelpUiState, key_text: []const u8, lines: []const []const u8) void {
    clearHelpContent(ui_state.content);
    appendHelpTitle(ui_state.content, "Route Details", key_text);
    const back_button = c.gtk_button_new();
    c.gtk_widget_add_css_class(back_button, "gs-help-row");
    c.gtk_widget_add_css_class(back_button, "gs-help-item-btn");
    c.gtk_widget_set_hexpand(back_button, GTRUE);
    const back_label = c.gtk_label_new("Back");
    c.gtk_label_set_xalign(@ptrCast(back_label), 0.0);
    c.gtk_widget_add_css_class(back_label, "gs-help-key");
    c.gtk_button_set_child(@ptrCast(back_button), back_label);
    _ = c.g_signal_connect_data(back_button, "clicked", c.G_CALLBACK(onHelpBackClicked), ui_state, null, 0);
    c.gtk_box_append(@ptrCast(ui_state.content), back_button);

    for (lines) |line| {
        const line_label = c.gtk_label_new(null);
        c.gtk_label_set_xalign(@ptrCast(line_label), 0.0);
        c.gtk_label_set_wrap(@ptrCast(line_label), GTRUE);
        c.gtk_widget_add_css_class(line_label, "gs-help-desc");
        const line_z = std.heap.page_allocator.dupeZ(u8, line) catch continue;
        defer std.heap.page_allocator.free(line_z);
        c.gtk_label_set_text(@ptrCast(line_label), line_z.ptr);
        c.gtk_box_append(@ptrCast(ui_state.content), line_label);
    }
}
