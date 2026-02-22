const std = @import("std");
const dispatch = @import("dispatch.zig");
const UiKind = dispatch.kinds.UiKind;

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
    return resolveSelectionKind(allocator, dispatch.kinds.parse(kind), action, pending_power_confirm);
}

pub fn resolveSelectionKind(
    allocator: std.mem.Allocator,
    parsed_kind: UiKind,
    action: []const u8,
    pending_power_confirm: bool,
) !SelectionDecision {
    var result = SelectionDecision{
        .record_selection = dispatch.shouldRecordSelectionKind(parsed_kind),
    };

    if (dispatch.isModuleKindEnum(parsed_kind)) {
        result.intent = .module_filter;
        return result;
    }
    if (dispatch.isDirMenuKindEnum(parsed_kind)) {
        result.intent = .dir_menu;
        return result;
    }
    if (dispatch.isFileMenuKindEnum(parsed_kind)) {
        result.intent = .file_menu;
        return result;
    }

    if (dispatch.requiresConfirmationKind(parsed_kind, action) and !pending_power_confirm) {
        result.clear_power_confirmation = false;
        result.guard_waiting_confirmation = true;
        return result;
    }

    const plan = try dispatch.planCommandKind(allocator, parsed_kind, action);
    result.plan = plan;
    result.intent = .run_plan;
    return result;
}
