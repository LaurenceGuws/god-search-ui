const std = @import("std");
const app_mod = @import("../app/mod.zig");
const providers_mod = @import("../providers/mod.zig");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});
const CandidateKind = @import("../search/mod.zig").CandidateKind;
const GTRUE: c.gboolean = 1;
const GFALSE: c.gboolean = 0;

const LaunchContext = struct {
    allocator: std.mem.Allocator,
    service: *app_mod.SearchService,
    telemetry: *app_mod.TelemetrySink,
};

const UiContext = extern struct {
    window: *c.GtkWidget,
    entry: *c.GtkSearchEntry,
    list: *c.GtkListBox,
    allocator: *anyopaque,
    service: *app_mod.SearchService,
    telemetry: *app_mod.TelemetrySink,
    pending_power_confirm: c.gboolean,
};

pub const Shell = struct {
    pub fn run(allocator: std.mem.Allocator, service: *app_mod.SearchService, telemetry: *app_mod.TelemetrySink) !void {
        const gtk_app = c.gtk_application_new("io.god.search.ui", c.G_APPLICATION_DEFAULT_FLAGS);
        defer c.g_object_unref(gtk_app);

        var launch = LaunchContext{
            .allocator = allocator,
            .service = service,
            .telemetry = telemetry,
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
        ctx.telemetry = launch.telemetry;
        ctx.pending_power_confirm = GFALSE;

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
        if (user_data == null) return GFALSE;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));

        switch (keyval) {
            c.GDK_KEY_Escape => {
                c.gtk_window_close(@ptrCast(ctx.window));
                return GTRUE;
            },
            c.GDK_KEY_Down => {
                selectOffset(ctx.list, 1);
                return GTRUE;
            },
            c.GDK_KEY_Up => {
                selectOffset(ctx.list, -1);
                return GTRUE;
            },
            c.GDK_KEY_Return, c.GDK_KEY_KP_Enter => {
                const row = c.gtk_list_box_get_selected_row(ctx.list);
                if (row != null) c.g_signal_emit_by_name(ctx.list, "row-activated", row);
                return GTRUE;
            },
            else => return GFALSE,
        }
    }

    fn onSearchChanged(entry: ?*c.GtkSearchEntry, user_data: ?*anyopaque) callconv(.c) void {
        _ = entry;
        if (user_data == null) return;
        const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
        clearPowerConfirmation(ctx);
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
        const rows = ranked[0..limit];
        appendGroupedRows(ctx, allocator, rows);

        const first = c.gtk_list_box_get_row_at_index(ctx.list, 0);
        if (first != null) c.gtk_list_box_select_row(ctx.list, first);
    }

    fn appendGroupedRows(ctx: *UiContext, allocator: std.mem.Allocator, rows: []const @import("../search/mod.zig").ScoredCandidate) void {
        appendGroup(ctx, allocator, rows, .app, "Apps");
        appendGroup(ctx, allocator, rows, .window, "Windows");
        appendGroup(ctx, allocator, rows, .dir, "Directories");
        appendGroup(ctx, allocator, rows, .action, "Actions");
        appendGroup(ctx, allocator, rows, .hint, "Hints");
    }

    fn appendGroup(
        ctx: *UiContext,
        allocator: std.mem.Allocator,
        rows: []const @import("../search/mod.zig").ScoredCandidate,
        kind: CandidateKind,
        title: []const u8,
    ) void {
        var has_any = false;
        for (rows) |row| {
            if (row.candidate.kind == kind) {
                has_any = true;
                break;
            }
        }
        if (!has_any) return;

        appendHeaderRow(ctx.list, title);
        for (rows) |row| {
            if (row.candidate.kind != kind) continue;
            appendCandidateRow(ctx.list, allocator, row);
        }
    }

    fn appendHeaderRow(list: *c.GtkListBox, title: []const u8) void {
        const title_escaped = c.g_markup_escape_text(title.ptr, @intCast(title.len));
        if (title_escaped == null) return;
        defer c.g_free(title_escaped);

        const markup = std.fmt.allocPrint(std.heap.page_allocator, "<span foreground='#8b93a8' weight='bold'>{s}</span>", .{std.mem.span(@as([*:0]const u8, @ptrCast(title_escaped)))}) catch return;
        defer std.heap.page_allocator.free(markup);
        const markup_z = std.heap.page_allocator.dupeZ(u8, markup) catch return;
        defer std.heap.page_allocator.free(markup_z);

        const label = c.gtk_label_new(null);
        c.gtk_label_set_markup(@ptrCast(label), markup_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(label), 0.0);

        const row = c.gtk_list_box_row_new();
        c.gtk_list_box_row_set_child(@ptrCast(row), label);
        c.gtk_list_box_row_set_selectable(@ptrCast(row), GFALSE);
        c.gtk_list_box_row_set_activatable(@ptrCast(row), GFALSE);
        c.gtk_list_box_append(@ptrCast(list), row);
    }

    fn appendCandidateRow(list: *c.GtkListBox, allocator: std.mem.Allocator, row: @import("../search/mod.zig").ScoredCandidate) void {
        const title_escaped = c.g_markup_escape_text(row.candidate.title.ptr, @intCast(row.candidate.title.len));
        if (title_escaped == null) return;
        defer c.g_free(title_escaped);
        const subtitle_escaped = c.g_markup_escape_text(row.candidate.subtitle.ptr, @intCast(row.candidate.subtitle.len));
        if (subtitle_escaped == null) return;
        defer c.g_free(subtitle_escaped);

        const icon = kindIcon(row.candidate.kind);
        const chip = kindChip(row.candidate.kind);
        const markup = std.fmt.allocPrint(
            allocator,
            "{s}  <span foreground='#9fb2ff' weight='bold'>{s}</span>  <span foreground='#e8ecf7'>{s}</span>  <span foreground='#9aa1b5'>{s}</span>",
            .{ icon, chip, std.mem.span(@as([*:0]const u8, @ptrCast(title_escaped))), std.mem.span(@as([*:0]const u8, @ptrCast(subtitle_escaped))) },
        ) catch return;
        defer allocator.free(markup);
        const markup_z = allocator.dupeZ(u8, markup) catch return;
        defer allocator.free(markup_z);

        const label = c.gtk_label_new(null);
        c.gtk_label_set_markup(@ptrCast(label), markup_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(label), 0.0);
        const list_row = c.gtk_list_box_row_new();
        c.gtk_list_box_row_set_child(@ptrCast(list_row), label);

        const kind = kindTag(row.candidate.kind);
        const kind_c = std.fmt.allocPrint(allocator, "{s}", .{kind}) catch return;
        defer allocator.free(kind_c);
        const action_c = std.fmt.allocPrint(allocator, "{s}", .{row.candidate.action}) catch return;
        defer allocator.free(action_c);
        const kind_z = allocator.dupeZ(u8, kind_c) catch return;
        defer allocator.free(kind_z);
        const action_z = allocator.dupeZ(u8, action_c) catch return;
        defer allocator.free(action_z);

        c.g_object_set_data_full(@ptrCast(list_row), "gs-kind", c.g_strdup(kind_z.ptr), c.g_free);
        c.g_object_set_data_full(@ptrCast(list_row), "gs-action", c.g_strdup(action_z.ptr), c.g_free);
        c.gtk_list_box_append(@ptrCast(list), list_row);
    }

    fn clearList(list: *c.GtkListBox) void {
        var child = c.gtk_widget_get_first_child(@ptrCast(@alignCast(list)));
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
            if (providers_mod.requiresConfirmation(action)) {
                if (ctx.pending_power_confirm == GFALSE) {
                    armPowerConfirmation(ctx);
                    emitTelemetry(ctx, "action", action, "guarded", "await-confirm");
                    return;
                }
                clearPowerConfirmation(ctx);
            } else {
                clearPowerConfirmation(ctx);
            }
            const cmd = providers_mod.resolveActionCommand(action) orelse {
                emitTelemetry(ctx, "action", action, "error", "unknown-action");
                return;
            };
            runShellCommand(cmd) catch {
                emitTelemetry(ctx, "action", action, "error", "command-failed");
                return;
            };
            emitTelemetry(ctx, "action", action, "ok", cmd);
            return;
        }
        clearPowerConfirmation(ctx);
        if (std.mem.eql(u8, kind, "app")) {
            if (!std.mem.eql(u8, action, "__drun__")) {
                runShellCommand(action) catch {
                    emitTelemetry(ctx, "app", action, "error", "command-failed");
                    return;
                };
                emitTelemetry(ctx, "app", action, "ok", action);
            }
            return;
        }
        if (std.mem.eql(u8, kind, "dir")) {
            const cmd = std.fmt.allocPrint(allocator, "xdg-open \"{s}\"", .{action}) catch return;
            defer allocator.free(cmd);
            runShellCommand(cmd) catch {
                emitTelemetry(ctx, "dir", action, "error", "command-failed");
                return;
            };
            emitTelemetry(ctx, "dir", action, "ok", cmd);
            return;
        }
        if (std.mem.eql(u8, kind, "window")) {
            const cmd = std.fmt.allocPrint(allocator, "hyprctl dispatch focuswindow \"address:{s}\"", .{action}) catch return;
            defer allocator.free(cmd);
            runShellCommand(cmd) catch {
                emitTelemetry(ctx, "window", action, "error", "command-failed");
                return;
            };
            emitTelemetry(ctx, "window", action, "ok", cmd);
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

    fn armPowerConfirmation(ctx: *UiContext) void {
        ctx.pending_power_confirm = GTRUE;
        c.gtk_entry_set_placeholder_text(@ptrCast(@alignCast(ctx.entry)), "Press Enter again to confirm Power menu");
    }

    fn clearPowerConfirmation(ctx: *UiContext) void {
        if (ctx.pending_power_confirm == GFALSE) return;
        ctx.pending_power_confirm = GFALSE;
        c.gtk_entry_set_placeholder_text(@ptrCast(@alignCast(ctx.entry)), "Type to search...");
    }

    fn emitTelemetry(ctx: *UiContext, kind: []const u8, action: []const u8, status: []const u8, detail: []const u8) void {
        const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
        ctx.telemetry.emitActionEvent(allocator_ptr.*, kind, action, status, detail) catch {};
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

    fn kindIcon(kind: @import("../search/mod.zig").CandidateKind) []const u8 {
        return switch (kind) {
            .app => "󰀻",
            .window => "",
            .dir => "󰉋",
            .action => "",
            .hint => "󰘥",
        };
    }

    fn kindChip(kind: @import("../search/mod.zig").CandidateKind) []const u8 {
        return switch (kind) {
            .app => "APP",
            .window => "WIN",
            .dir => "DIR",
            .action => "ACT",
            .hint => "TIP",
        };
    }
};
