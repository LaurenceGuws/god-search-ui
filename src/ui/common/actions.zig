const dispatch = @import("dispatch.zig");
const UiKind = dispatch.kinds.UiKind;

pub const ExecuteStatus = enum {
    noop,
    ok,
    failed,
};

pub const ExecuteOutcome = struct {
    status: ExecuteStatus = .noop,
    telemetry_kind: []const u8 = "",
    telemetry_detail: []const u8 = "",
    error_message: []const u8 = "",
    close_on_success: bool = false,
};

pub fn executePlan(
    kind: UiKind,
    plan: *const dispatch.CommandPlan,
    run_command: *const fn ([]const u8) anyerror!void,
) ExecuteOutcome {
    const kind_tag = dispatch.kinds.tag(kind);
    if (plan.unknown_action and plan.command == null) {
        return .{
            .status = .failed,
            .telemetry_kind = if (plan.telemetry_kind.len > 0) plan.telemetry_kind else kind_tag,
            .telemetry_detail = "unknown-action",
            .error_message = plan.error_message,
        };
    }
    const cmd = plan.command orelse return .{};
    run_command(cmd) catch {
        return .{
            .status = .failed,
            .telemetry_kind = if (plan.telemetry_kind.len > 0) plan.telemetry_kind else kind_tag,
            .telemetry_detail = if (plan.unknown_action) "unknown-action" else "command-failed",
            .error_message = if (plan.error_message.len > 0) plan.error_message else "Command failed",
        };
    };
    return .{
        .status = .ok,
        .telemetry_kind = if (plan.telemetry_kind.len > 0) plan.telemetry_kind else kind_tag,
        .telemetry_detail = if (plan.telemetry_ok_detail.len > 0) plan.telemetry_ok_detail else cmd,
        .close_on_success = plan.close_on_success,
    };
}
