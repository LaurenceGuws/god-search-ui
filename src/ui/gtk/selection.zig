const std = @import("std");
const common_actions = @import("../common/actions.zig");
const common_dispatch = @import("../common/dispatch.zig");
const common_execute = @import("../common/execute.zig");
const notifications = @import("../../notifications/mod.zig");
const gtk_types = @import("types.zig");
const gtk_actions = @import("actions.zig");
const gtk_shell_startup = @import("shell_startup.zig");

const c = gtk_types.c;
const UiContext = gtk_types.UiContext;
const UiKind = common_dispatch.kinds.UiKind;

pub const Hooks = struct {
    set_status: *const fn (*UiContext, []const u8) void,
    show_launch_feedback: *const fn (*UiContext, []const u8) void,
    emit_telemetry: *const fn (*UiContext, []const u8, []const u8, []const u8, []const u8) void,
    arm_power_confirmation: *const fn (*UiContext) void,
    clear_power_confirmation: *const fn (*UiContext) void,
    show_dir_action_menu: *const fn (*UiContext, std.mem.Allocator, []const u8) void,
    show_file_action_menu: *const fn (*UiContext, std.mem.Allocator, []const u8) void,
};

pub fn executeSelected(ctx: *UiContext, kind: UiKind, action: []const u8, hooks: Hooks) void {
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;

    if (std.mem.eql(u8, action, "notif-dismiss-all")) {
        const closed = notifications.runtime.closeAllActive();
        var msg_buf: [96]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Dismissed {d} notifications", .{closed}) catch "Dismissed notifications";
        hooks.set_status(ctx, msg);
        hooks.emit_telemetry(ctx, "notification", "notif-dismiss-all", "ok", "dismiss-all");
        refreshCurrentQuery(ctx);
        return;
    }
    if (std.mem.startsWith(u8, action, "notif-dismiss:")) {
        const id_str = action["notif-dismiss:".len..];
        const id = std.fmt.parseInt(u32, id_str, 10) catch {
            hooks.set_status(ctx, "Invalid notification id");
            hooks.emit_telemetry(ctx, "notification", action, "error", "bad-id");
            return;
        };
        if (notifications.runtime.closeById(id)) {
            hooks.set_status(ctx, "Notification dismissed");
            hooks.emit_telemetry(ctx, "notification", action, "ok", "dismiss");
            refreshCurrentQuery(ctx);
        } else {
            hooks.set_status(ctx, "Notification already closed");
            hooks.emit_telemetry(ctx, "notification", action, "error", "not-found");
        }
        return;
    }

    var decision = common_execute.resolveSelectionKind(allocator, kind, action) catch return;
    defer decision.deinit(allocator);

    if (decision.record_selection) {
        ctx.service.recordSelection(allocator, action) catch |err| {
            std.log.warn("history recordSelection failed for action '{s}': {s}", .{ action, @errorName(err) });
            hooks.set_status(ctx, "History write failed");
        };
    }

    if (ctx.pending_power_confirm == gtk_types.GTRUE) {
        hooks.clear_power_confirmation(ctx);
    }

    switch (decision.intent) {
        .module_filter => {
            applyModuleFilter(ctx, allocator, action, hooks);
            return;
        },
        .dir_menu => {
            hooks.show_dir_action_menu(ctx, allocator, action);
            return;
        },
        .file_menu => {
            hooks.show_file_action_menu(ctx, allocator, action);
            return;
        },
        .run_plan => {
            if (decision.plan) |*plan| {
                const outcome = common_actions.executePlan(
                    kind,
                    plan,
                    gtk_actions.runShellCommand,
                    gtk_actions.runDetachedShellCommand,
                );
                switch (outcome.status) {
                    .failed => {
                        hooks.emit_telemetry(ctx, outcome.telemetry_kind, action, "error", outcome.telemetry_detail);
                        hooks.show_launch_feedback(ctx, outcome.error_message);
                        return;
                    },
                    .ok => {
                        hooks.emit_telemetry(ctx, outcome.telemetry_kind, action, "ok", outcome.telemetry_detail);
                        if (outcome.close_on_success) {
                            ctx.clear_query_on_close = gtk_types.GTRUE;
                            ctx.last_selected_row_index = -1;
                            ctx.last_scroll_position = 0;
                            gtk_shell_startup.clearStoredQuery(ctx);
                            // Clear stale query so next summon starts with an empty entry.
                            c.gtk_editable_set_text(@ptrCast(ctx.entry), "");
                            c.gtk_window_close(@ptrCast(ctx.window));
                        }
                    },
                    .noop => return,
                }
            }
        },
        .none => return,
    }
}

fn refreshCurrentQuery(ctx: *UiContext) void {
    const text_ptr = c.gtk_editable_get_text(@ptrCast(ctx.entry));
    if (text_ptr == null) return;
    const text = std.mem.span(@as([*:0]const u8, @ptrCast(text_ptr)));
    const text_z = std.heap.page_allocator.dupeZ(u8, text) catch return;
    defer std.heap.page_allocator.free(text_z);
    c.gtk_editable_set_text(@ptrCast(ctx.entry), text_z.ptr);
}

fn applyModuleFilter(ctx: *UiContext, allocator: std.mem.Allocator, module_action: []const u8, hooks: Hooks) void {
    const route = std.mem.trim(u8, module_action, " \t\r\n");
    if (route.len == 0) return;
    const text = std.fmt.allocPrint(allocator, "{s} ", .{route}) catch return;
    defer allocator.free(text);
    const text_z = allocator.dupeZ(u8, text) catch return;
    defer allocator.free(text_z);

    hooks.clear_power_confirmation(ctx);
    c.gtk_editable_set_text(@ptrCast(ctx.entry), text_z.ptr);
    c.gtk_editable_set_position(@ptrCast(ctx.entry), -1);
    const caret = c.gtk_editable_get_position(@ptrCast(ctx.entry));
    c.gtk_editable_select_region(@ptrCast(ctx.entry), caret, caret);
    _ = c.gtk_entry_grab_focus_without_selecting(@ptrCast(@alignCast(ctx.entry)));
    const status = std.fmt.allocPrint(allocator, "Module filter active: {s}", .{route}) catch return;
    defer allocator.free(status);
    hooks.set_status(ctx, status);
}
