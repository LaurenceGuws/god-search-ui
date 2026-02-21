const std = @import("std");

pub const Shell = struct {
    pub fn run() !void {
        const c = @cImport({
            @cInclude("gtk/gtk.h");
        });

        const app = c.gtk_application_new("io.god.search.ui", c.G_APPLICATION_DEFAULT_FLAGS);
        defer c.g_object_unref(app);

        _ = c.g_signal_connect_data(app, "activate", c.G_CALLBACK(onActivate), null, null, 0);
        _ = c.g_application_run(@ptrCast(app), 0, null);
    }

    fn onActivate(app: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
        const c = @cImport({
            @cInclude("gtk/gtk.h");
        });
        const gtk_app: *c.GtkApplication = @ptrCast(@alignCast(app.?));
        const window = c.gtk_application_window_new(gtk_app);
        c.gtk_window_set_title(@ptrCast(window), "God Search");
        c.gtk_window_set_default_size(@ptrCast(window), 900, 560);

        const root_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 8);
        c.gtk_widget_set_margin_top(root_box, 12);
        c.gtk_widget_set_margin_bottom(root_box, 12);
        c.gtk_widget_set_margin_start(root_box, 12);
        c.gtk_widget_set_margin_end(root_box, 12);

        const entry = c.gtk_search_entry_new();
        c.gtk_editable_set_text(@ptrCast(entry), "Type to search...");

        const list = c.gtk_list_box_new();
        const row = c.gtk_label_new("Result placeholder");
        c.gtk_list_box_append(@ptrCast(list), row);

        c.gtk_box_append(@ptrCast(root_box), entry);
        c.gtk_box_append(@ptrCast(root_box), list);
        c.gtk_window_set_child(@ptrCast(window), root_box);
        c.gtk_window_present(@ptrCast(window));
    }
};
