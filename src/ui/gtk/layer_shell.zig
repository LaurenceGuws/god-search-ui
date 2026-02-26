const build_options = @import("build_options");
const gtk_types = @import("types.zig");
const SurfaceMode = @import("../surfaces/mod.zig").SurfaceMode;
const placement = @import("../placement/mod.zig");

const impl = if (build_options.enable_layer_shell) enabled else disabled;

pub fn shouldUseLayerShell(surface_mode: SurfaceMode) bool {
    return impl.shouldUseLayerShell(surface_mode);
}

pub fn applyLauncher(window: *gtk_types.c.GtkWidget) bool {
    return impl.applyLauncher(window);
}

pub fn applyNotifications(window: *gtk_types.c.GtkWidget, policy: placement.NotificationPolicy) bool {
    return impl.applyNotifications(window, policy);
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

    pub fn applyNotifications(window: *gtk_types.c.GtkWidget, policy: placement.NotificationPolicy) bool {
        _ = window;
        _ = policy;
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
        return true;
    }

    pub fn applyNotifications(window: *gtk_types.c.GtkWidget, policy: placement.NotificationPolicy) bool {
        if (!runtimeAvailable()) return false;
        const win: *c.GtkWindow = @ptrCast(@alignCast(window));
        c.gtk_layer_init_for_window(win);
        c.gtk_layer_set_namespace(win, "god-search-ui-notifications");
        c.gtk_layer_set_layer(win, c.GTK_LAYER_SHELL_LAYER_TOP);
        c.gtk_layer_set_keyboard_mode(win, c.GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
        applyAnchor(win, policy.window.anchor);
        c.gtk_layer_set_margin(win, c.GTK_LAYER_SHELL_EDGE_TOP, policy.window.margins.top);
        c.gtk_layer_set_margin(win, c.GTK_LAYER_SHELL_EDGE_RIGHT, policy.window.margins.right);
        c.gtk_layer_set_margin(win, c.GTK_LAYER_SHELL_EDGE_BOTTOM, policy.window.margins.bottom);
        c.gtk_layer_set_margin(win, c.GTK_LAYER_SHELL_EDGE_LEFT, policy.window.margins.left);
        return true;
    }

    fn applyAnchor(win: *c.GtkWindow, anchor: placement.Anchor) void {
        const top: c.gboolean = switch (anchor) {
            .top_left, .top_center, .top_right => 1,
            .center, .bottom_left, .bottom_center, .bottom_right => 0,
        };
        const bottom: c.gboolean = switch (anchor) {
            .bottom_left, .bottom_center, .bottom_right => 1,
            .center, .top_left, .top_center, .top_right => 0,
        };
        const left: c.gboolean = switch (anchor) {
            .top_left, .bottom_left => 1,
            .center, .top_center, .top_right, .bottom_center, .bottom_right => 0,
        };
        const right: c.gboolean = switch (anchor) {
            .top_right, .bottom_right => 1,
            .center, .top_left, .top_center, .bottom_left, .bottom_center => 0,
        };
        c.gtk_layer_set_anchor(win, c.GTK_LAYER_SHELL_EDGE_TOP, top);
        c.gtk_layer_set_anchor(win, c.GTK_LAYER_SHELL_EDGE_RIGHT, right);
        c.gtk_layer_set_anchor(win, c.GTK_LAYER_SHELL_EDGE_BOTTOM, bottom);
        c.gtk_layer_set_anchor(win, c.GTK_LAYER_SHELL_EDGE_LEFT, left);
    }

    fn runtimeAvailable() bool {
        return c.gtk_layer_is_supported() != 0;
    }

};
