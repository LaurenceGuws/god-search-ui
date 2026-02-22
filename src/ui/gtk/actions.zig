const std = @import("std");
const gtk_types = @import("types.zig");
const c = gtk_types.c;

pub const ParsedFileAction = struct {
    path: []const u8,
    line: ?[]const u8,
};

pub fn runShellCommand(command: []const u8) !void {
    const command_z = try std.heap.page_allocator.dupeZ(u8, command);
    defer std.heap.page_allocator.free(command_z);

    var gerr: ?*c.GError = null;
    const ok = c.g_spawn_command_line_async(command_z.ptr, &gerr);
    if (ok == 0) {
        if (gerr != null) c.g_error_free(gerr);
        return error.CommandFailed;
    }
}

pub fn buildDirTerminalCommand(allocator: std.mem.Allocator, dir_path: []const u8) ![]u8 {
    const quoted = try shellSingleQuote(allocator, dir_path);
    defer allocator.free(quoted);
    return std.fmt.allocPrint(
        allocator,
        "sh -lc 'cd -- \"$1\" || exit 1; term=\"${{TERMINAL:-}}\"; if [ -n \"$term\" ] && command -v \"$term\" >/dev/null 2>&1; then exec \"$term\"; fi; for t in kitty alacritty footclient foot wezterm gnome-terminal konsole xfce4-terminal tilix xterm; do if command -v \"$t\" >/dev/null 2>&1; then exec \"$t\"; fi; done; exit 127' _ {s}",
        .{quoted},
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
        "sh -lc 'printf %s \"$1\" | wl-copy 2>/dev/null || printf %s \"$1\" | xclip -selection clipboard' _ {s}",
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
        "sh -lc 'printf %s \"$1\" | wl-copy 2>/dev/null || printf %s \"$1\" | xclip -selection clipboard' _ {s}",
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
