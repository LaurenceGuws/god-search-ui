const std = @import("std");
const providers_mod = @import("../../providers/mod.zig");
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

    if (!std.mem.eql(u8, kind, "dir_option") and !std.mem.eql(u8, kind, "file_option") and !std.mem.eql(u8, kind, "module")) {
        ctx.service.recordSelection(allocator, action) catch {};
    }

    if (std.mem.eql(u8, kind, "action")) {
        if (providers_mod.requiresConfirmation(action)) {
            if (ctx.pending_power_confirm == gtk_types.GFALSE) {
                hooks.arm_power_confirmation(ctx);
                hooks.emit_telemetry(ctx, "action", action, "guarded", "await-confirm");
                return;
            }
            hooks.clear_power_confirmation(ctx);
        } else {
            hooks.clear_power_confirmation(ctx);
        }
        const cmd = providers_mod.resolveActionCommand(action) orelse {
            hooks.emit_telemetry(ctx, "action", action, "error", "unknown-action");
            hooks.show_launch_feedback(ctx, "Action failed: unknown action");
            return;
        };
        gtk_actions.runShellCommand(cmd) catch {
            hooks.emit_telemetry(ctx, "action", action, "error", "command-failed");
            hooks.show_launch_feedback(ctx, "Action failed to launch");
            return;
        };
        hooks.emit_telemetry(ctx, "action", action, "ok", cmd);
        c.gtk_window_close(@ptrCast(ctx.window));
        return;
    }
    if (std.mem.eql(u8, kind, "dir_option")) {
        gtk_actions.runShellCommand(action) catch {
            hooks.emit_telemetry(ctx, "dir", action, "error", "command-failed");
            hooks.show_launch_feedback(ctx, "Directory action failed");
            return;
        };
        hooks.emit_telemetry(ctx, "dir", action, "ok", "option-command");
        c.gtk_window_close(@ptrCast(ctx.window));
        return;
    }
    if (std.mem.eql(u8, kind, "file_option")) {
        gtk_actions.runShellCommand(action) catch {
            hooks.emit_telemetry(ctx, "file", action, "error", "command-failed");
            hooks.show_launch_feedback(ctx, "File action failed");
            return;
        };
        hooks.emit_telemetry(ctx, "file", action, "ok", "option-command");
        c.gtk_window_close(@ptrCast(ctx.window));
        return;
    }
    if (std.mem.eql(u8, kind, "module")) {
        applyModuleFilter(ctx, allocator, action, hooks);
        return;
    }
    hooks.clear_power_confirmation(ctx);
    if (std.mem.eql(u8, kind, "app")) {
        if (!std.mem.eql(u8, action, "__drun__")) {
            gtk_actions.runShellCommand(action) catch {
                hooks.emit_telemetry(ctx, "app", action, "error", "command-failed");
                hooks.show_launch_feedback(ctx, "App failed to launch");
                return;
            };
            hooks.emit_telemetry(ctx, "app", action, "ok", action);
            c.gtk_window_close(@ptrCast(ctx.window));
        }
        return;
    }
    if (std.mem.eql(u8, kind, "dir")) {
        hooks.show_dir_action_menu(ctx, allocator, action);
        return;
    }
    if (std.mem.eql(u8, kind, "file") or std.mem.eql(u8, kind, "grep")) {
        hooks.show_file_action_menu(ctx, allocator, action);
        return;
    }
    if (std.mem.eql(u8, kind, "window")) {
        const cmd = std.fmt.allocPrint(allocator, "hyprctl dispatch focuswindow \"address:{s}\"", .{action}) catch return;
        defer allocator.free(cmd);
        gtk_actions.runShellCommand(cmd) catch {
            hooks.emit_telemetry(ctx, "window", action, "error", "command-failed");
            hooks.show_launch_feedback(ctx, "Window focus failed");
            return;
        };
        hooks.emit_telemetry(ctx, "window", action, "ok", cmd);
        c.gtk_window_close(@ptrCast(ctx.window));
        return;
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
