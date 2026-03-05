const std = @import("std");
const runtime_tools = @import("../../config/runtime_tools.zig");

pub const ParsedFileAction = struct {
    path: []const u8,
    line: ?[]const u8,
};

pub fn runShellCommand(command: []const u8) !void {
    if (std.mem.startsWith(u8, std.mem.trim(u8, command, " \t\r\n"), "xdg-open ")) {
        try runDetachedShellCommand(command);
        return;
    }

    const launch_probe =
        "sh -lc \"$1\" & pid=$!; i=0; while [ \"$i\" -lt 10 ]; do if ! kill -0 \"$pid\" 2>/dev/null; then wait \"$pid\"; exit $?; fi; i=$((i + 1)); sleep 0.02; done; exit 0";

    const result = try std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "sh", "-lc", launch_probe, "_", command },
    });
    defer {
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
    }
    if (result.term != .Exited or result.term.Exited != 0) {
        return error.CommandFailed;
    }
}

pub fn runDetachedShellCommand(command: []const u8) !void {
    // `xdg-open` may stay attached to the launched app/browser. Use nohup+background
    // and return once the shell has queued the launch.
    const detach_script = "nohup sh -lc \"$1\" >/dev/null 2>&1 </dev/null &";
    const result = try std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "sh", "-lc", detach_script, "_", command },
    });
    defer {
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
    }
    if (result.term != .Exited or result.term.Exited != 0) {
        return error.CommandFailed;
    }
}

pub fn buildDirTerminalCommand(allocator: std.mem.Allocator, dir_path: []const u8) ![]u8 {
    const quoted = try shellSingleQuote(allocator, dir_path);
    defer allocator.free(quoted);
    const term_cmd = runtime_tools.terminalTool().command();
    return std.fmt.allocPrint(
        allocator,
        "sh -lc 'cd -- \"$1\" || exit 1; exec {s}' _ {s}",
        .{ term_cmd, quoted },
    );
}

pub fn buildDirExplorerCommand(allocator: std.mem.Allocator, dir_path: []const u8) ![]u8 {
    const quoted = try shellSingleQuote(allocator, dir_path);
    defer allocator.free(quoted);
    return std.fmt.allocPrint(allocator, "xdg-open {s}", .{quoted});
}

pub fn buildDirEditorCommand(allocator: std.mem.Allocator, dir_path: []const u8) ![]u8 {
    const quoted = try shellSingleQuote(allocator, dir_path);
    defer allocator.free(quoted);
    return std.fmt.allocPrint(
        allocator,
        "sh -lc 'if [ -n \"$VISUAL\" ]; then exec \"$VISUAL\" \"$1\"; elif [ -n \"$EDITOR\" ]; then exec \"$EDITOR\" \"$1\"; else exec xdg-open \"$1\"; fi' _ {s}",
        .{quoted},
    );
}

pub fn buildDirCopyPathCommand(allocator: std.mem.Allocator, dir_path: []const u8) ![]u8 {
    const quoted = try shellSingleQuote(allocator, dir_path);
    defer allocator.free(quoted);
    return std.fmt.allocPrint(
        allocator,
        "sh -lc 'printf %s \"$1\" | wl-copy 2>/dev/null || printf %s \"$1\" | xclip -selection clipboard; if command -v copyq >/dev/null 2>&1; then copyq add -- \"$1\" >/dev/null 2>&1 || true; fi' _ {s}",
        .{quoted},
    );
}

pub fn parseFileAction(file_action: []const u8) ParsedFileAction {
    if (std.mem.lastIndexOfScalar(u8, file_action, ':')) |idx| {
        if (idx + 1 < file_action.len) {
            const suffix = file_action[idx + 1 ..];
            if (isDigitsOnly(suffix)) {
                return .{ .path = file_action[0..idx], .line = suffix };
            }
        }
    }
    return .{ .path = file_action, .line = null };
}

pub fn buildFileOpenCommand(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
    const quoted = try shellSingleQuote(allocator, file_path);
    defer allocator.free(quoted);
    return std.fmt.allocPrint(allocator, "xdg-open {s}", .{quoted});
}

pub fn buildFileRevealCommand(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
    const parent = std.fs.path.dirname(file_path) orelse file_path;
    const quoted = try shellSingleQuote(allocator, parent);
    defer allocator.free(quoted);
    return std.fmt.allocPrint(allocator, "xdg-open {s}", .{quoted});
}

pub fn buildFileCopyPathCommand(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
    const quoted = try shellSingleQuote(allocator, file_path);
    defer allocator.free(quoted);
    return std.fmt.allocPrint(
        allocator,
        "sh -lc 'printf %s \"$1\" | wl-copy 2>/dev/null || printf %s \"$1\" | xclip -selection clipboard; if command -v copyq >/dev/null 2>&1; then copyq add -- \"$1\" >/dev/null 2>&1 || true; fi' _ {s}",
        .{quoted},
    );
}

pub fn buildFileEditCommand(allocator: std.mem.Allocator, file_path: []const u8, line: ?[]const u8) ![]u8 {
    const quoted = try shellSingleQuote(allocator, file_path);
    defer allocator.free(quoted);
    if (line) |line_num| {
        const line_q = try shellSingleQuote(allocator, line_num);
        defer allocator.free(line_q);
        return std.fmt.allocPrint(
            allocator,
            "sh -lc 'editor=\"${{VISUAL:-${{EDITOR:-}}}}\"; if [ -z \"$editor\" ]; then exec xdg-open \"$1\"; fi; case \"$editor\" in nvim|vim|vi|helix|hx|kak|nano) exec \"$editor\" +\"$2\" \"$1\" ;; code|codium|code-insiders) exec \"$editor\" --goto \"$1:$2\" ;; subl) exec \"$editor\" \"$1:$2\" ;; *) exec \"$editor\" \"$1\" ;; esac' _ {s} {s}",
            .{ quoted, line_q },
        );
    }
    return std.fmt.allocPrint(
        allocator,
        "sh -lc 'if [ -n \"$VISUAL\" ]; then exec \"$VISUAL\" \"$1\"; elif [ -n \"$EDITOR\" ]; then exec \"$EDITOR\" \"$1\"; else exec xdg-open \"$1\"; fi' _ {s}",
        .{quoted},
    );
}

fn isDigitsOnly(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |ch| {
        if (!std.ascii.isDigit(ch)) return false;
    }
    return true;
}

fn shellSingleQuote(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try out.append(allocator, '\'');
    for (value) |ch| {
        if (ch == '\'') {
            try out.appendSlice(allocator, "'\\''");
        } else {
            try out.append(allocator, ch);
        }
    }
    try out.append(allocator, '\'');
    return out.toOwnedSlice(allocator);
}

test "runShellCommand reports non-zero exits as CommandFailed" {
    try std.testing.expectError(error.CommandFailed, runShellCommand("exit 7"));
}

test "runShellCommand still returns for long-running launches" {
    try runShellCommand("sleep 1");
}

test "buildDirTerminalCommand uses configured terminal without fallback probes" {
    runtime_tools.apply(.{
        .tools = .{
            .terminal = .alacritty,
        },
    });
    const cmd = try buildDirTerminalCommand(std.testing.allocator, "/tmp");
    defer std.testing.allocator.free(cmd);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "exec alacritty") != null);
    try std.testing.expect(std.mem.indexOf(u8, cmd, "command -v") == null);
}
