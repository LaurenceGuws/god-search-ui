const std = @import("std");
const dispatch = @import("dispatch.zig");

pub const Intent = enum {
    none,
    module_filter,
    dir_menu,
    file_menu,
    run_plan,
};

pub const SelectionDecision = struct {
    record_selection: bool = false,
    clear_power_confirmation: bool = true,
    guard_waiting_confirmation: bool = false,
    intent: Intent = .none,
    plan: ?dispatch.CommandPlan = null,

    pub fn deinit(self: *SelectionDecision, allocator: std.mem.Allocator) void {
        if (self.plan) |*plan| plan.deinit(allocator);
        self.* = .{};
    }
};

pub fn resolveSelection(
    allocator: std.mem.Allocator,
    kind: []const u8,
    action: []const u8,
    pending_power_confirm: bool,
) !SelectionDecision {
    var result = SelectionDecision{
        .record_selection = dispatch.shouldRecordSelection(kind),
    };

    if (dispatch.isModuleKind(kind)) {
        result.intent = .module_filter;
        return result;
    }
    if (dispatch.isDirMenuKind(kind)) {
        result.intent = .dir_menu;
        return result;
    }
    if (dispatch.isFileMenuKind(kind)) {
        result.intent = .file_menu;
        return result;
    }

    if (dispatch.requiresConfirmation(kind, action) and !pending_power_confirm) {
        result.clear_power_confirmation = false;
        result.guard_waiting_confirmation = true;
        return result;
    }

    const plan = try dispatch.planCommand(allocator, kind, action);
    result.plan = plan;
    result.intent = .run_plan;
    return result;
}
