const build_options = @import("build_options");
const gtk_types = @import("types.zig");
const SurfaceMode = @import("../surfaces/mod.zig").SurfaceMode;

const impl = if (build_options.enable_layer_shell) enabled else disabled;

pub fn shouldUseLayerShell(surface_mode: SurfaceMode) bool {
    return impl.shouldUseLayerShell(surface_mode);
}

pub fn applyLauncher(window: *gtk_types.c.GtkWidget) bool {
    return impl.applyLauncher(window);
}

pub fn applyNotifications(window: *gtk_types.c.GtkWidget) bool {
    return impl.applyNotifications(window);
}

const disabled = struct {
    pub fn shouldUseLayerShell(surface_mode: SurfaceMode) bool {
        _ = surface_mode;
        return false;
    }

    pub fn applyLauncher(window: *gtk_types.c.GtkWidget) bool {
        _ = window;
        return false;
    }

    pub fn applyNotifications(window: *gtk_types.c.GtkWidget) bool {
        _ = window;
        return false;
    }
};

const enabled = struct {
    const c = @cImport({
        @cInclude("gtk/gtk.h");
        @cInclude("gtk4-layer-shell.h");
    });

    pub fn shouldUseLayerShell(surface_mode: SurfaceMode) bool {
        return switch (surface_mode) {
            .toplevel => false,
            .layer_shell => runtimeAvailable(),
            .auto => runtimeAvailable(),
        };
    }

    pub fn applyLauncher(window: *gtk_types.c.GtkWidget) bool {
        if (!runtimeAvailable()) return false;
        const win: *c.GtkWindow = @ptrCast(@alignCast(window));
        c.gtk_layer_init_for_window(win);
        c.gtk_layer_set_namespace(win, "god-search-ui-launcher");
        c.gtk_layer_set_layer(win, c.GTK_LAYER_SHELL_LAYER_TOP);
        c.gtk_layer_set_keyboard_mode(win, c.GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE);
        c.gtk_layer_set_anchor(win, c.GTK_LAYER_SHELL_EDGE_TOP, 1);
        c.gtk_layer_set_anchor(win, c.GTK_LAYER_SHELL_EDGE_BOTTOM, 0);
        c.gtk_layer_set_anchor(win, c.GTK_LAYER_SHELL_EDGE_LEFT, 0);
        c.gtk_layer_set_anchor(win, c.GTK_LAYER_SHELL_EDGE_RIGHT, 0);
        c.gtk_layer_set_margin(win, c.GTK_LAYER_SHELL_EDGE_TOP, 36);
        if (primaryMonitorObject(window)) |monitor_obj| {
            defer c.g_object_unref(monitor_obj);
            const monitor: *c.GdkMonitor = @ptrCast(@alignCast(monitor_obj));
            c.gtk_layer_set_monitor(win, monitor);
        }
        return true;
    }

    pub fn applyNotifications(window: *gtk_types.c.GtkWidget) bool {
        if (!runtimeAvailable()) return false;
        const win: *c.GtkWindow = @ptrCast(@alignCast(window));
        c.gtk_layer_init_for_window(win);
        c.gtk_layer_set_namespace(win, "god-search-ui-notifications");
        c.gtk_layer_set_layer(win, c.GTK_LAYER_SHELL_LAYER_TOP);
        c.gtk_layer_set_keyboard_mode(win, c.GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
        c.gtk_layer_set_anchor(win, c.GTK_LAYER_SHELL_EDGE_TOP, 1);
        c.gtk_layer_set_anchor(win, c.GTK_LAYER_SHELL_EDGE_RIGHT, 1);
        c.gtk_layer_set_anchor(win, c.GTK_LAYER_SHELL_EDGE_BOTTOM, 0);
        c.gtk_layer_set_anchor(win, c.GTK_LAYER_SHELL_EDGE_LEFT, 0);
        c.gtk_layer_set_margin(win, c.GTK_LAYER_SHELL_EDGE_TOP, 24);
        c.gtk_layer_set_margin(win, c.GTK_LAYER_SHELL_EDGE_RIGHT, 24);
        if (primaryMonitorObject(window)) |monitor_obj| {
            defer c.g_object_unref(monitor_obj);
            const monitor: *c.GdkMonitor = @ptrCast(@alignCast(monitor_obj));
            c.gtk_layer_set_monitor(win, monitor);
        }
        return true;
    }

    fn runtimeAvailable() bool {
        return c.gtk_layer_is_supported() != 0;
    }

    fn primaryMonitorObject(window: *gtk_types.c.GtkWidget) ?*anyopaque {
        const display = gtk_types.c.gtk_widget_get_display(window) orelse return null;
        const monitors = gtk_types.c.gdk_display_get_monitors(display) orelse return null;
        if (gtk_types.c.g_list_model_get_n_items(monitors) == 0) return null;
        return gtk_types.c.g_list_model_get_item(monitors, 0);
    }
};
