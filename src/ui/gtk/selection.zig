const std = @import("std");
const common_actions = @import("../common/actions.zig");
const common_dispatch = @import("../common/dispatch.zig");
const common_execute = @import("../common/execute.zig");
const gtk_types = @import("types.zig");
const gtk_actions = @import("actions.zig");

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

    var decision = common_execute.resolveSelectionKind(allocator, kind, action, ctx.pending_power_confirm == gtk_types.GTRUE) catch return;
    defer decision.deinit(allocator);

    if (decision.record_selection) {
        ctx.service.recordSelection(allocator, action) catch {};
    }

    if (decision.guard_waiting_confirmation) {
        hooks.arm_power_confirmation(ctx);
        hooks.emit_telemetry(ctx, "action", action, "guarded", "await-confirm");
        return;
    }

    if (decision.clear_power_confirmation) {
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
                const outcome = common_actions.executePlan(kind, plan, gtk_actions.runShellCommand);
                switch (outcome.status) {
                    .failed => {
                        hooks.emit_telemetry(ctx, outcome.telemetry_kind, action, "error", outcome.telemetry_detail);
                        hooks.show_launch_feedback(ctx, outcome.error_message);
                        return;
                    },
                    .ok => {
                        hooks.emit_telemetry(ctx, outcome.telemetry_kind, action, "ok", outcome.telemetry_detail);
                        if (outcome.close_on_success) {
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
