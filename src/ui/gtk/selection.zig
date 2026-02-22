const std = @import("std");
const common_dispatch = @import("../common/dispatch.zig");
const gtk_types = @import("types.zig");
const gtk_actions = @import("actions.zig");

const c = gtk_types.c;
const UiContext = gtk_types.UiContext;

pub const Hooks = struct {
    set_status: *const fn (*UiContext, []const u8) void,
    show_launch_feedback: *const fn (*UiContext, []const u8) void,
    emit_telemetry: *const fn (*UiContext, []const u8, []const u8, []const u8, []const u8) void,
    arm_power_confirmation: *const fn (*UiContext) void,
    clear_power_confirmation: *const fn (*UiContext) void,
    show_dir_action_menu: *const fn (*UiContext, std.mem.Allocator, []const u8) void,
    show_file_action_menu: *const fn (*UiContext, std.mem.Allocator, []const u8) void,
};

pub fn executeSelected(ctx: *UiContext, kind: []const u8, action: []const u8, hooks: Hooks) void {
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;

    if (common_dispatch.shouldRecordSelection(kind)) {
        ctx.service.recordSelection(allocator, action) catch {};
    }

    if (std.mem.eql(u8, kind, "action")) {
        if (common_dispatch.requiresConfirmation(kind, action)) {
            if (ctx.pending_power_confirm == gtk_types.GFALSE) {
                hooks.arm_power_confirmation(ctx);
                hooks.emit_telemetry(ctx, "action", action, "guarded", "await-confirm");
                return;
            }
            hooks.clear_power_confirmation(ctx);
        } else {
            hooks.clear_power_confirmation(ctx);
        }
    }
    if (common_dispatch.isModuleKind(kind)) {
        applyModuleFilter(ctx, allocator, action, hooks);
        return;
    }
    hooks.clear_power_confirmation(ctx);

    if (common_dispatch.isDirMenuKind(kind)) {
        hooks.show_dir_action_menu(ctx, allocator, action);
        return;
    }
    if (common_dispatch.isFileMenuKind(kind)) {
        hooks.show_file_action_menu(ctx, allocator, action);
        return;
    }

    var plan = common_dispatch.planCommand(allocator, kind, action) catch return;
    defer plan.deinit(allocator);
    const cmd = plan.command orelse return;
    gtk_actions.runShellCommand(cmd) catch {
        const telemetry_kind = if (plan.telemetry_kind.len > 0) plan.telemetry_kind else kind;
        const telemetry_detail = if (plan.unknown_action) "unknown-action" else "command-failed";
        hooks.emit_telemetry(ctx, telemetry_kind, action, "error", telemetry_detail);
        if (plan.error_message.len > 0) {
            hooks.show_launch_feedback(ctx, plan.error_message);
        } else {
            hooks.show_launch_feedback(ctx, "Command failed");
        }
        return;
    };
    if (plan.telemetry_kind.len > 0) {
        hooks.emit_telemetry(ctx, plan.telemetry_kind, action, "ok", plan.telemetry_ok_detail);
    } else {
        hooks.emit_telemetry(ctx, kind, action, "ok", cmd);
    }
    if (plan.close_on_success) {
        c.gtk_window_close(@ptrCast(ctx.window));
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
