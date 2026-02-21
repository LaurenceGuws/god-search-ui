const std = @import("std");
const app_mod = @import("../app/mod.zig");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});

const UiContext = extern struct {
    window: *c.GtkWidget,
    list: *c.GtkListBox,
};

pub const Shell = struct {
    pub fn run(_: std.mem.Allocator, _: *app_mod.SearchService) !void {
        const gtk_app = c.gtk_application_new("io.god.search.ui", c.G_APPLICATION_DEFAULT_FLAGS);
        defer c.g_object_unref(gtk_app);

        _ = c.g_signal_connect_data(gtk_app, "activate", c.G_CALLBACK(onActivate), null, null, 0);
        _ = c.g_application_run(@ptrCast(gtk_app), 0, null);
    }

    fn onActivate(app_ptr: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
        const gtk_app: *c.GtkApplication = @ptrCast(@alignCast(app_ptr.?));
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
        c.gtk_list_box_set_selection_mode(@ptrCast(list), c.GTK_SELECTION_SINGLE);
        const row = c.gtk_label_new("Result placeholder");
        c.gtk_list_box_append(@ptrCast(list), row);
        const first = c.gtk_list_box_get_row_at_index(@ptrCast(list), 0);
        if (first != null) c.gtk_list_box_select_row(@ptrCast(list), first);

        const ctx: *UiContext = @ptrCast(@alignCast(c.g_malloc0(@sizeOf(UiContext))));
        ctx.window = @ptrCast(window);
        ctx.list = @ptrCast(list);

        const key_controller = c.gtk_event_controller_key_new();
        _ = c.g_signal_connect_data(key_controller, "key-pressed", c.G_CALLBACK(onKeyPressed), ctx, null, 0);
        c.gtk_widget_add_controller(window, @ptrCast(key_controller));
        _ = c.g_signal_connect_data(window, "destroy", c.G_CALLBACK(onDestroy), ctx, null, 0);

        c.gtk_box_append(@ptrCast(root_box), entry);
        c.gtk_box_append(@ptrCast(root_box), list);
        c.gtk_window_set_child(@ptrCast(window), root_box);
        c.gtk_window_present(@ptrCast(window));
    }

    fn onDestroy(_: ?*c.GtkWidget, user_data: ?*anyopaque) callconv(.c) void {
        if (user_data == null) return;
        c.g_free(user_data);
    }

    fn onKeyPressed(
        _: ?*c.GtkEventControllerKey,
        keyval: c.guint,
        _: c.guint,
        _: c.GdkModifierType,
        user_data: ?*anyopaque,
    ) callconv(.c) c.gboolean {
        if (user_data == null) return c.FALSE;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));

        switch (keyval) {
            c.GDK_KEY_Escape => {
                c.gtk_window_close(@ptrCast(ctx.window));
                return c.TRUE;
            },
            c.GDK_KEY_Down => {
                selectOffset(ctx.list, 1);
                return c.TRUE;
            },
            c.GDK_KEY_Up => {
                selectOffset(ctx.list, -1);
                return c.TRUE;
            },
            c.GDK_KEY_Return, c.GDK_KEY_KP_Enter => {
                const row = c.gtk_list_box_get_selected_row(ctx.list);
                if (row != null) c.gtk_list_box_row_activate(row);
                return c.TRUE;
            },
            else => return c.FALSE,
        }
    }

    fn selectOffset(list: *c.GtkListBox, delta: i32) void {
        const selected = c.gtk_list_box_get_selected_row(list);
        var idx: i32 = 0;
        if (selected != null) idx = c.gtk_list_box_row_get_index(selected) + delta;
        if (idx < 0) idx = 0;

        const target = c.gtk_list_box_get_row_at_index(list, idx);
        if (target != null) c.gtk_list_box_select_row(list, target);
    }
};
