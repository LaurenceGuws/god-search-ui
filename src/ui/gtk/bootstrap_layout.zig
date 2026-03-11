const gtk_types = @import("types.zig");
const gtk_help_panel = @import("help_panel.zig");

const c = gtk_types.c;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;

pub const Layout = struct {
    root_box: *c.GtkWidget,
    entry: *c.GtkWidget,
    status: *c.GtkWidget,
    list: *c.GtkWidget,
    scroller: *c.GtkWidget,
    preview_panel: *c.GtkWidget,
    preview_title: *c.GtkWidget,
    preview_toggle_button: *c.GtkWidget,
    preview_text_scroller: *c.GtkWidget,
    preview_text: *c.GtkWidget,
};

pub fn build() ?Layout {
    const root_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 8);
    c.gtk_widget_set_margin_top(root_box, 12);
    c.gtk_widget_set_margin_bottom(root_box, 12);
    c.gtk_widget_set_margin_start(root_box, 12);
    c.gtk_widget_set_margin_end(root_box, 12);

    const entry = c.gtk_entry_new();
    c.gtk_entry_set_placeholder_text(@ptrCast(entry), "Type to search...");

    const help_panel = gtk_help_panel.build(entry) orelse return null;
    const help_button = help_panel.button;
    const help_panel_row = help_panel.panel_row;

    const entry_row = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
    c.gtk_widget_set_hexpand(entry_row, GTRUE);
    c.gtk_widget_set_vexpand(entry_row, GFALSE);
    c.gtk_widget_set_hexpand(entry, GTRUE);
    c.gtk_box_append(@ptrCast(entry_row), entry);
    c.gtk_box_append(@ptrCast(entry_row), help_button);

    const status = c.gtk_label_new("Esc to close, Ctrl+R to refresh");
    c.gtk_label_set_xalign(@ptrCast(status), 0.0);
    c.gtk_label_set_single_line_mode(@ptrCast(status), GTRUE);
    c.gtk_label_set_ellipsize(@ptrCast(status), c.PANGO_ELLIPSIZE_END);
    c.gtk_label_set_max_width_chars(@ptrCast(status), 96);
    c.gtk_widget_set_margin_bottom(status, 4);
    c.gtk_widget_add_css_class(status, "gs-status");

    const list = c.gtk_list_box_new();
    c.gtk_widget_add_css_class(list, "gs-results");
    c.gtk_list_box_set_selection_mode(@ptrCast(list), c.GTK_SELECTION_SINGLE);
    const scroller = c.gtk_scrolled_window_new();
    c.gtk_widget_set_vexpand(scroller, GTRUE);
    c.gtk_widget_set_hexpand(scroller, GTRUE);
    c.gtk_widget_set_size_request(scroller, 420, -1);
    c.gtk_widget_add_css_class(scroller, "gs-results-scroll");
    c.gtk_scrolled_window_set_policy(@ptrCast(scroller), c.GTK_POLICY_NEVER, c.GTK_POLICY_AUTOMATIC);
    c.gtk_scrolled_window_set_overlay_scrolling(@ptrCast(scroller), GTRUE);
    c.gtk_scrolled_window_set_child(@ptrCast(scroller), list);

    const preview_title = c.gtk_label_new("Preview");
    c.gtk_label_set_xalign(@ptrCast(preview_title), 0.0);
    c.gtk_widget_set_hexpand(preview_title, GTRUE);
    c.gtk_widget_add_css_class(preview_title, "gs-preview-title");

    const preview_toggle_button = c.gtk_button_new_with_label("tree");
    c.gtk_widget_add_css_class(preview_toggle_button, "gs-preview-toggle");
    c.gtk_widget_set_visible(preview_toggle_button, GFALSE);

    const preview_text = c.gtk_text_view_new();
    c.gtk_text_view_set_editable(@ptrCast(preview_text), GFALSE);
    c.gtk_text_view_set_cursor_visible(@ptrCast(preview_text), GFALSE);
    c.gtk_text_view_set_wrap_mode(@ptrCast(preview_text), c.PANGO_WRAP_NONE);
    c.gtk_text_view_set_monospace(@ptrCast(preview_text), GTRUE);
    c.gtk_widget_set_hexpand(preview_text, GTRUE);
    c.gtk_widget_set_vexpand(preview_text, GTRUE);
    c.gtk_widget_add_css_class(preview_text, "gs-preview-text");

    const preview_text_scroller = c.gtk_scrolled_window_new();
    c.gtk_scrolled_window_set_policy(@ptrCast(preview_text_scroller), c.GTK_POLICY_AUTOMATIC, c.GTK_POLICY_AUTOMATIC);
    c.gtk_scrolled_window_set_min_content_height(@ptrCast(preview_text_scroller), 180);
    c.gtk_widget_set_vexpand(preview_text_scroller, GTRUE);
    c.gtk_widget_add_css_class(preview_text_scroller, "gs-preview-text-scroll");
    c.gtk_scrolled_window_set_child(@ptrCast(preview_text_scroller), preview_text);
    c.gtk_widget_set_visible(preview_text_scroller, GTRUE);

    const preview_header = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
    c.gtk_widget_add_css_class(preview_header, "gs-preview-header");
    c.gtk_box_append(@ptrCast(preview_header), preview_title);
    c.gtk_box_append(@ptrCast(preview_header), preview_toggle_button);

    const preview_inner = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 8);
    c.gtk_widget_add_css_class(preview_inner, "gs-preview-inner");
    c.gtk_box_append(@ptrCast(preview_inner), preview_header);
    c.gtk_box_append(@ptrCast(preview_inner), preview_text_scroller);

    const preview_scroller = c.gtk_scrolled_window_new();
    c.gtk_scrolled_window_set_policy(@ptrCast(preview_scroller), c.GTK_POLICY_NEVER, c.GTK_POLICY_AUTOMATIC);
    c.gtk_widget_set_vexpand(preview_scroller, GTRUE);
    c.gtk_widget_add_css_class(preview_scroller, "gs-results-scroll");
    c.gtk_widget_add_css_class(preview_scroller, "gs-preview-scroll");
    c.gtk_scrolled_window_set_child(@ptrCast(preview_scroller), preview_inner);

    const preview_panel = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_widget_add_css_class(preview_panel, "gs-preview-panel");
    c.gtk_widget_set_size_request(preview_panel, 300, -1);
    c.gtk_box_append(@ptrCast(preview_panel), preview_scroller);
    c.gtk_widget_set_visible(preview_panel, GFALSE);

    const content_pane = c.gtk_paned_new(c.GTK_ORIENTATION_HORIZONTAL);
    c.gtk_widget_add_css_class(content_pane, "gs-content-pane");
    c.gtk_widget_set_vexpand(content_pane, GTRUE);
    c.gtk_widget_set_hexpand(content_pane, GTRUE);
    c.gtk_paned_set_position(@ptrCast(content_pane), 620);
    c.gtk_paned_set_start_child(@ptrCast(content_pane), scroller);
    c.gtk_paned_set_end_child(@ptrCast(content_pane), preview_panel);
    c.gtk_paned_set_resize_start_child(@ptrCast(content_pane), GTRUE);
    c.gtk_paned_set_shrink_start_child(@ptrCast(content_pane), GFALSE);
    c.gtk_paned_set_resize_end_child(@ptrCast(content_pane), GFALSE);
    c.gtk_paned_set_shrink_end_child(@ptrCast(content_pane), GFALSE);

    const content_stack = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);
    c.gtk_widget_set_hexpand(content_stack, GTRUE);
    c.gtk_widget_set_vexpand(content_stack, GTRUE);
    c.gtk_box_append(@ptrCast(content_stack), status);
    c.gtk_box_append(@ptrCast(content_stack), content_pane);

    const content_overlay = c.gtk_overlay_new();
    c.gtk_widget_set_hexpand(content_overlay, GTRUE);
    c.gtk_widget_set_vexpand(content_overlay, GTRUE);
    c.gtk_overlay_set_child(@ptrCast(content_overlay), content_stack);
    c.gtk_overlay_add_overlay(@ptrCast(content_overlay), help_panel_row);

    c.gtk_box_append(@ptrCast(root_box), entry_row);
    c.gtk_box_append(@ptrCast(root_box), content_overlay);

    return .{
        .root_box = root_box,
        .entry = entry,
        .status = status,
        .list = list,
        .scroller = scroller,
        .preview_panel = preview_panel,
        .preview_title = preview_title,
        .preview_toggle_button = preview_toggle_button,
        .preview_text_scroller = preview_text_scroller,
        .preview_text = preview_text,
    };
}
