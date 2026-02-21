const std = @import("std");
const app_mod = @import("../app/mod.zig");
const providers_mod = @import("../providers/mod.zig");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});

const LaunchContext = struct {
    allocator: std.mem.Allocator,
    service: *app_mod.SearchService,
};

const UiContext = extern struct {
    window: *c.GtkWidget,
    entry: *c.GtkSearchEntry,
    list: *c.GtkListBox,
    allocator: *anyopaque,
    service: *app_mod.SearchService,
};

pub const Shell = struct {
    pub fn run(allocator: std.mem.Allocator, service: *app_mod.SearchService) !void {
        const gtk_app = c.gtk_application_new("io.god.search.ui", c.G_APPLICATION_DEFAULT_FLAGS);
        defer c.g_object_unref(gtk_app);

        var launch = LaunchContext{
            .allocator = allocator,
            .service = service,
        };
        _ = c.g_signal_connect_data(gtk_app, "activate", c.G_CALLBACK(onActivate), &launch, null, 0);
        _ = c.g_application_run(@ptrCast(gtk_app), 0, null);
    }

    fn onActivate(app_ptr: ?*anyopaque, user_data: ?*anyopaque) callconv(.c) void {
        const gtk_app: *c.GtkApplication = @ptrCast(@alignCast(app_ptr.?));
        const launch: *LaunchContext = @ptrCast(@alignCast(user_data.?));
        const window = c.gtk_application_window_new(gtk_app);
        c.gtk_window_set_title(@ptrCast(window), "God Search");
        c.gtk_window_set_default_size(@ptrCast(window), 900, 560);

        const root_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 8);
        c.gtk_widget_set_margin_top(root_box, 12);
        c.gtk_widget_set_margin_bottom(root_box, 12);
        c.gtk_widget_set_margin_start(root_box, 12);
        c.gtk_widget_set_margin_end(root_box, 12);

        const entry = c.gtk_search_entry_new();
        c.gtk_entry_set_placeholder_text(@ptrCast(entry), "Type to search...");

        const list = c.gtk_list_box_new();
        c.gtk_list_box_set_selection_mode(@ptrCast(list), c.GTK_SELECTION_SINGLE);
        const row = c.gtk_label_new("Result placeholder");
        c.gtk_list_box_append(@ptrCast(list), row);
        const first = c.gtk_list_box_get_row_at_index(@ptrCast(list), 0);
        if (first != null) c.gtk_list_box_select_row(@ptrCast(list), first);

        const ctx: *UiContext = @ptrCast(@alignCast(c.g_malloc0(@sizeOf(UiContext))));
        ctx.window = @ptrCast(window);
        ctx.entry = @ptrCast(entry);
        ctx.list = @ptrCast(list);
        ctx.allocator = @ptrCast(@constCast(&launch.allocator));
        ctx.service = launch.service;

        const key_controller = c.gtk_event_controller_key_new();
        _ = c.g_signal_connect_data(key_controller, "key-pressed", c.G_CALLBACK(onKeyPressed), ctx, null, 0);
        c.gtk_widget_add_controller(window, @ptrCast(key_controller));
        _ = c.g_signal_connect_data(entry, "search-changed", c.G_CALLBACK(onSearchChanged), ctx, null, 0);
        _ = c.g_signal_connect_data(list, "row-activated", c.G_CALLBACK(onRowActivated), ctx, null, 0);
        _ = c.g_signal_connect_data(window, "destroy", c.G_CALLBACK(onDestroy), ctx, null, 0);

        c.gtk_box_append(@ptrCast(root_box), entry);
        c.gtk_box_append(@ptrCast(root_box), list);
        c.gtk_window_set_child(@ptrCast(window), root_box);
        c.gtk_window_present(@ptrCast(window));

        populateResults(ctx, "");
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

    fn onSearchChanged(entry: ?*c.GtkSearchEntry, user_data: ?*anyopaque) callconv(.c) void {
        _ = entry;
        if (user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
        if (text_ptr == null) {
            populateResults(ctx, "");
            return;
        }
        const query = std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr)));
        populateResults(ctx, query);
    }

    fn onRowActivated(_: ?*c.GtkListBox, row: ?*c.GtkListBoxRow, user_data: ?*anyopaque) callconv(.c) void {
        if (row == null or user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));

        const kind_ptr = c.g_object_get_data(@ptrCast(row), "gs-kind");
        const action_ptr = c.g_object_get_data(@ptrCast(row), "gs-action");
        if (kind_ptr == null or action_ptr == null) return;

        const kind = std.mem.span(@as([*:0]const u8, @ptrCast(kind_ptr)));
        const action = std.mem.span(@as([*:0]const u8, @ptrCast(action_ptr)));
        executeSelected(ctx, kind, action);
    }

    fn selectOffset(list: *c.GtkListBox, delta: i32) void {
        const selected = c.gtk_list_box_get_selected_row(list);
        var idx: i32 = 0;
        if (selected != null) idx = c.gtk_list_box_row_get_index(selected) + delta;
        if (idx < 0) idx = 0;

        const target = c.gtk_list_box_get_row_at_index(list, idx);
        if (target != null) c.gtk_list_box_select_row(list, target);
    }

    fn populateResults(ctx: *UiContext, query: []const u8) void {
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const allocator = allocator_ptr.*;

        clearList(ctx.list);
        const ranked = ctx.service.searchQuery(allocator, query) catch return;
        defer allocator.free(ranked);

        const limit = @min(ranked.len, 20);
        for (ranked[0..limit]) |row| {
            const text = std.fmt.allocPrintZ(allocator, "{s} — {s}", .{ row.candidate.title, row.candidate.subtitle }) catch continue;
            defer allocator.free(text);

            const label = c.gtk_label_new(text.ptr);
            c.gtk_label_set_xalign(@ptrCast(label), 0.0);
            const list_row = c.gtk_list_box_row_new();
            c.gtk_list_box_row_set_child(@ptrCast(list_row), label);

            const kind = kindTag(row.candidate.kind);
            const kind_c = std.fmt.allocPrintZ(allocator, "{s}", .{kind}) catch continue;
            defer allocator.free(kind_c);
            const action_c = std.fmt.allocPrintZ(allocator, "{s}", .{row.candidate.action}) catch continue;
            defer allocator.free(action_c);

            c.g_object_set_data_full(@ptrCast(list_row), "gs-kind", c.g_strdup(kind_c.ptr), c.g_free);
            c.g_object_set_data_full(@ptrCast(list_row), "gs-action", c.g_strdup(action_c.ptr), c.g_free);
            c.gtk_list_box_append(@ptrCast(ctx.list), list_row);
        }

        const first = c.gtk_list_box_get_row_at_index(ctx.list, 0);
        if (first != null) c.gtk_list_box_select_row(ctx.list, first);
    }

    fn clearList(list: *c.GtkListBox) void {
        var child = c.gtk_widget_get_first_child(@ptrCast(list));
        while (child != null) {
            const next = c.gtk_widget_get_next_sibling(child);
            c.gtk_list_box_remove(list, child);
            child = next;
        }
    }

    fn executeSelected(ctx: *UiContext, kind: []const u8, action: []const u8) void {
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        const allocator = allocator_ptr.*;

        ctx.service.recordSelection(allocator, action) catch {};

        if (std.mem.eql(u8, kind, "action")) {
            providers_mod.executeAction(action, runShellCommand) catch {};
            return;
        }
        if (std.mem.eql(u8, kind, "app")) {
            if (!std.mem.eql(u8, action, "__drun__")) runShellCommand(action) catch {};
            return;
        }
        if (std.mem.eql(u8, kind, "dir")) {
            const cmd = std.fmt.allocPrint(allocator, "xdg-open \"{s}\"", .{action}) catch return;
            defer allocator.free(cmd);
            runShellCommand(cmd) catch {};
            return;
        }
        if (std.mem.eql(u8, kind, "window")) {
            const cmd = std.fmt.allocPrint(allocator, "hyprctl dispatch focuswindow \"address:{s}\"", .{action}) catch return;
            defer allocator.free(cmd);
            runShellCommand(cmd) catch {};
            return;
        }
    }

    fn runShellCommand(command: []const u8) !void {
        const result = try std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &.{ "sh", "-lc", command },
        });
        defer {
            std.heap.page_allocator.free(result.stdout);
            std.heap.page_allocator.free(result.stderr);
        }
        if (result.term != .Exited or result.term.Exited != 0) return error.CommandFailed;
    }

    fn kindTag(kind: @import("../search/mod.zig").CandidateKind) []const u8 {
        return switch (kind) {
            .app => "app",
            .window => "window",
            .dir => "dir",
            .action => "action",
            .hint => "hint",
        };
    }
};
