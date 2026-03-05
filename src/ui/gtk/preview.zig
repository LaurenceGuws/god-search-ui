const std = @import("std");
const common_dispatch = @import("../common/dispatch.zig");
const gtk_types = @import("types.zig");
const gtk_actions = @import("actions.zig");
const gtk_row_data = @import("row_data.zig");
const runtime_tools = @import("../../config/runtime_tools.zig");

const c = gtk_types.c;
const UiContext = gtk_types.UiContext;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const UiKind = common_dispatch.kinds.UiKind;

const max_file_preview_bytes: usize = 256 * 1024;
const max_dir_preview_bytes: usize = 256 * 1024;
const max_workspace_preview_bytes: usize = 8 * 1024 * 1024;
const max_package_preview_bytes: usize = 1024 * 1024;
const package_preview_debounce_ms: c.guint = 180;

const PreviewDoc = struct {
    title: []u8,
    text: []u8,
    highlight_line: ?usize = null,
    show_toggle: bool = false,
    toggle_label: []const u8 = "",

    fn deinit(self: *const PreviewDoc, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.text);
    }
};

pub fn toggle(ctx: *UiContext) void {
    const next = if (ctx.preview_enabled == GTRUE) GFALSE else GTRUE;
    setEnabled(ctx, next == GTRUE);
    if (next == GTRUE) refreshFromSelection(ctx);
}

pub fn setEnabled(ctx: *UiContext, enabled: bool) void {
    ctx.preview_enabled = if (enabled) GTRUE else GFALSE;
    c.gtk_widget_set_visible(ctx.preview_panel, ctx.preview_enabled);
    if (ctx.preview_enabled == GFALSE) {
        cancelPendingWork(ctx);
        ctx.last_preview_hash = 0;
    }
}

pub fn clear(ctx: *UiContext) void {
    if (ctx.preview_enabled == GFALSE) return;
    cancelPendingWork(ctx);
    const allocator = contextAllocator(ctx);
    const title = allocator.dupe(u8, "Preview") catch return;
    errdefer allocator.free(title);
    const text = allocator.dupe(u8, "No selection") catch return;
    var doc = PreviewDoc{ .title = title, .text = text };
    defer doc.deinit(allocator);
    setPreviewIfChanged(ctx, doc);
}

pub fn refreshFromSelection(ctx: *UiContext) void {
    if (ctx.preview_enabled == GFALSE) return;
    const row = c.gtk_list_box_get_selected_row(ctx.list) orelse {
        clear(ctx);
        return;
    };
    updateForRow(ctx, row);
}

pub fn updateForRow(ctx: *UiContext, row: *c.GtkListBoxRow) void {
    if (ctx.preview_enabled == GFALSE) return;
    cancelPendingWork(ctx);

    const kind = gtk_row_data.kind(row);
    const title = gtk_row_data.title(row) orelse "";
    const subtitle = gtk_row_data.subtitle(row) orelse "";
    const action = gtk_row_data.action(row) orelse "";

    if (isPackagePreviewCandidate(kind, action)) {
        const allocator = contextAllocator(ctx);
        var placeholder = buildPackageLoadingDoc(allocator, title, subtitle, action) catch return;
        defer placeholder.deinit(allocator);
        setPreviewIfChanged(ctx, placeholder);
        schedulePackagePreview(ctx, action);
        return;
    }

    const allocator = contextAllocator(ctx);
    var doc = buildPreviewDoc(ctx, allocator, kind, title, subtitle, action) catch return;
    defer doc.deinit(allocator);
    setPreviewIfChanged(ctx, doc);
}

pub fn onPreviewToggleClicked(_: ?*c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
    if (user_data == null) return;
    const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
    if (ctx.preview_enabled == GFALSE) return;
    ctx.preview_dir_tree_mode = if (ctx.preview_dir_tree_mode == GTRUE) GFALSE else GTRUE;
    refreshFromSelection(ctx);
}

fn contextAllocator(ctx: *UiContext) std.mem.Allocator {
    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    return allocator_ptr.*;
}

pub fn cancelPendingWork(ctx: *UiContext) void {
    if (ctx.package_preview_timeout_id != 0) {
        _ = c.g_source_remove(ctx.package_preview_timeout_id);
        ctx.package_preview_timeout_id = 0;
    }
    clearPendingPackageAction(ctx);
}

fn setPreviewIfChanged(ctx: *UiContext, doc: PreviewDoc) void {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(doc.title);
    hasher.update("\n---doc---\n");
    hasher.update(doc.text);
    if (doc.highlight_line) |line| {
        var line_buf: [32]u8 = undefined;
        const line_txt = std.fmt.bufPrint(&line_buf, "{d}", .{line}) catch "";
        hasher.update(line_txt);
    }
    hasher.update(if (doc.show_toggle) "1" else "0");
    hasher.update(doc.toggle_label);

    const h = hasher.final();
    if (ctx.last_preview_hash == h) return;

    const title_z = std.heap.page_allocator.dupeZ(u8, doc.title) catch return;
    defer std.heap.page_allocator.free(title_z);
    c.gtk_label_set_text(ctx.preview_title, title_z.ptr);

    const text_buffer = c.gtk_text_view_get_buffer(ctx.preview_text_view) orelse return;
    c.gtk_text_buffer_set_text(text_buffer, doc.text.ptr, @intCast(doc.text.len));
    applyGrepHighlight(ctx, text_buffer, doc.highlight_line);

    if (doc.show_toggle) {
        const label_z = std.heap.page_allocator.dupeZ(u8, doc.toggle_label) catch return;
        defer std.heap.page_allocator.free(label_z);
        c.gtk_button_set_label(@ptrCast(ctx.preview_toggle_button), label_z.ptr);
        c.gtk_widget_set_visible(ctx.preview_toggle_button, GTRUE);
    } else {
        c.gtk_widget_set_visible(ctx.preview_toggle_button, GFALSE);
    }

    ctx.last_preview_hash = h;
}

fn applyGrepHighlight(ctx: *UiContext, buffer: *c.GtkTextBuffer, highlight_line_opt: ?usize) void {
    var start_iter: c.GtkTextIter = undefined;
    var end_iter: c.GtkTextIter = undefined;
    c.gtk_text_buffer_get_start_iter(buffer, &start_iter);
    c.gtk_text_buffer_get_end_iter(buffer, &end_iter);
    c.gtk_text_buffer_remove_tag_by_name(buffer, "gs-preview-hit", &start_iter, &end_iter);

    const line = highlight_line_opt orelse return;
    if (line == 0) return;

    _ = c.gtk_text_buffer_create_tag(
        buffer,
        "gs-preview-hit",
        "background",
        "#2d3850",
        "foreground",
        "#f8fbff",
        @as(?*anyopaque, null),
    );

    const line_count = c.gtk_text_buffer_get_line_count(buffer);
    if (line > @as(usize, @intCast(line_count))) return;

    var line_start: c.GtkTextIter = undefined;
    var line_end: c.GtkTextIter = undefined;
    _ = c.gtk_text_buffer_get_iter_at_line(buffer, &line_start, @intCast(line - 1));
    if (line < @as(usize, @intCast(line_count))) {
        _ = c.gtk_text_buffer_get_iter_at_line(buffer, &line_end, @intCast(line));
    } else {
        c.gtk_text_buffer_get_end_iter(buffer, &line_end);
    }

    c.gtk_text_buffer_apply_tag_by_name(buffer, "gs-preview-hit", &line_start, &line_end);
    _ = c.gtk_text_view_scroll_to_iter(ctx.preview_text_view, &line_start, 0.1, GFALSE, 0.0, 0.0);
}

fn buildPreviewDoc(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    kind: UiKind,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
) !PreviewDoc {
    return switch (kind) {
        .file, .grep => try buildFilePreviewDoc(allocator, kind, title, subtitle, action),
        .dir => try buildDirPreviewDoc(ctx, allocator, title, subtitle, action),
        .workspace => (try buildWorkspacePreviewDoc(allocator, title, subtitle, action)) orelse try buildGenericPreviewDoc(allocator, kind, title, subtitle, action),
        .app => (try buildAppPreviewDoc(allocator, title, subtitle, action)) orelse try buildGenericPreviewDoc(allocator, kind, title, subtitle, action),
        .action, .hint => (try buildPackagePreviewDoc(allocator, title, subtitle, action)) orelse try buildGenericPreviewDoc(allocator, kind, title, subtitle, action),
        else => try buildGenericPreviewDoc(allocator, kind, title, subtitle, action),
    };
}

fn isPackagePreviewCandidate(kind: UiKind, action: []const u8) bool {
    if (kind != .action and kind != .hint) return false;
    return parsePackageAction(action) != null;
}

fn buildPackageLoadingDoc(
    allocator: std.mem.Allocator,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
) !PreviewDoc {
    const pkg = parsePackageAction(action) orelse "(unknown)";
    var text = std.ArrayList(u8).empty;
    defer text.deinit(allocator);
    const w = text.writer(allocator);
    try w.print("package: {s}\n", .{pkg});
    if (title.len > 0) try w.print("title: {s}\n", .{title});
    if (subtitle.len > 0) try w.print("summary: {s}\n", .{subtitle});
    try w.writeAll("\nLoading package metadata...");
    return .{
        .title = try allocator.dupe(u8, "Package Preview"),
        .text = try text.toOwnedSlice(allocator),
    };
}

fn schedulePackagePreview(ctx: *UiContext, action: []const u8) void {
    const allocator = contextAllocator(ctx);
    const owned = allocator.dupe(u8, action) catch return;
    clearPendingPackageAction(ctx);
    ctx.package_preview_action_ptr = owned.ptr;
    ctx.package_preview_action_len = owned.len;
    ctx.package_preview_timeout_id = c.g_timeout_add(package_preview_debounce_ms, onPackagePreviewTimeout, ctx);
}

fn onPackagePreviewTimeout(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    if (user_data == null) return GFALSE;
    const ctx: *UiContext = @ptrCast(@alignCast(user_data.?));
    ctx.package_preview_timeout_id = 0;
    if (ctx.preview_enabled == GFALSE) {
        clearPendingPackageAction(ctx);
        return GFALSE;
    }

    const pending = pendingPackageAction(ctx) orelse return GFALSE;
    const row = c.gtk_list_box_get_selected_row(ctx.list) orelse {
        clearPendingPackageAction(ctx);
        return GFALSE;
    };
    const row_action = gtk_row_data.action(row) orelse "";
    if (!std.mem.eql(u8, row_action, pending)) {
        clearPendingPackageAction(ctx);
        return GFALSE;
    }

    const kind = gtk_row_data.kind(row);
    const title = gtk_row_data.title(row) orelse "";
    const subtitle = gtk_row_data.subtitle(row) orelse "";
    if (!isPackagePreviewCandidate(kind, row_action)) {
        clearPendingPackageAction(ctx);
        return GFALSE;
    }

    const allocator = contextAllocator(ctx);
    if (buildPackagePreviewDoc(allocator, title, subtitle, row_action) catch null) |doc| {
        defer doc.deinit(allocator);
        setPreviewIfChanged(ctx, doc);
    }
    clearPendingPackageAction(ctx);
    return GFALSE;
}

fn pendingPackageAction(ctx: *UiContext) ?[]const u8 {
    const ptr = ctx.package_preview_action_ptr orelse return null;
    if (ctx.package_preview_action_len == 0) return null;
    return ptr[0..ctx.package_preview_action_len];
}

fn clearPendingPackageAction(ctx: *UiContext) void {
    const ptr = ctx.package_preview_action_ptr orelse return;
    const allocator = contextAllocator(ctx);
    allocator.free(ptr[0..ctx.package_preview_action_len]);
    ctx.package_preview_action_ptr = null;
    ctx.package_preview_action_len = 0;
}

fn buildPackagePreviewDoc(
    allocator: std.mem.Allocator,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
) !?PreviewDoc {
    const pkg = parsePackageAction(action) orelse return null;
    const pkg_q = try shellSingleQuote(allocator, pkg);
    defer allocator.free(pkg_q);
    const pkg_cmd = switch (runtime_tools.packageManager()) {
        .yay => "yay -Si --color never \"$1\"",
        .pacman => "pacman -Si --color never \"$1\"",
    };
    const cmd = try std.fmt.allocPrint(
        allocator,
        "sh -lc '{s}' _ {s} 2>/dev/null",
        .{ pkg_cmd, pkg_q },
    );
    defer allocator.free(cmd);

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "sh", "-lc", cmd },
        .max_output_bytes = max_package_preview_bytes,
    }) catch |err| {
        std.log.warn("package preview spawn failed pkg={s} err={s}", .{ pkg, @errorName(err) });
        return null;
    };
    defer allocator.free(result.stderr);
    defer allocator.free(result.stdout);

    if (result.term != .Exited or result.term.Exited != 0) {
        std.log.warn("package preview command failed pkg={s} exit={any}", .{ pkg, result.term });
        return null;
    }

    if (result.stdout.len == 0) return null;

    var text = std.ArrayList(u8).empty;
    defer text.deinit(allocator);
    const w = text.writer(allocator);
    try w.print("package: {s}\n", .{pkg});
    if (title.len > 0) try w.print("title: {s}\n", .{title});
    if (subtitle.len > 0) try w.print("summary: {s}\n", .{subtitle});
    try w.print("\n{s}", .{result.stdout});

    return .{
        .title = try allocator.dupe(u8, "Package Preview"),
        .text = try text.toOwnedSlice(allocator),
    };
}

fn parsePackageAction(action: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, action, "pkg-install:")) return action["pkg-install:".len..];
    if (std.mem.startsWith(u8, action, "pkg-update:")) return action["pkg-update:".len..];
    if (std.mem.startsWith(u8, action, "pkg-remove:")) return action["pkg-remove:".len..];
    return null;
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

fn buildGenericPreviewDoc(
    allocator: std.mem.Allocator,
    kind: UiKind,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
) !PreviewDoc {
    var text = std.ArrayList(u8).empty;
    defer text.deinit(allocator);
    const w = text.writer(allocator);

    const kind_text = common_dispatch.kinds.statusLabel(kind);
    const picked_title = if (title.len > 0) title else "(untitled)";
    const subtitle_trim = std.mem.trim(u8, subtitle, " \t\r\n");
    const action_trim = std.mem.trim(u8, action, " \t\r\n");

    try w.print("kind: {s}\n", .{kind_text});
    try w.print("title: {s}", .{picked_title});

    if (subtitle_trim.len > 0) {
        try w.print("\n\n{s}", .{subtitle_trim});
    }
    if (showAction(kind, action_trim)) {
        try w.print("\n\naction: {s}", .{action_trim});
    }

    return .{
        .title = try allocator.dupe(u8, "Preview"),
        .text = try text.toOwnedSlice(allocator),
    };
}

fn showAction(kind: UiKind, action: []const u8) bool {
    if (action.len == 0) return false;
    return switch (kind) {
        .module => true,
        .hint => std.mem.startsWith(u8, action, "calc-copy:"),
        else => true,
    };
}

fn buildAppPreviewDoc(
    allocator: std.mem.Allocator,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
) !?PreviewDoc {
    var row = try lookupAppCacheRow(allocator, title, action) orelse return null;
    defer row.deinit(allocator);

    var text = std.ArrayList(u8).empty;
    defer text.deinit(allocator);
    const w = text.writer(allocator);
    try w.print("name: {s}\n", .{row.name});
    try w.print("category: {s}\n", .{row.category});
    try w.print("exec: {s}\n", .{row.exec_cmd});
    try w.print("icon: {s}", .{if (row.icon_name.len > 0) row.icon_name else "(none)"});
    if (subtitle.len > 0) try w.print("\n\n{s}", .{subtitle});

    return .{
        .title = try allocator.dupe(u8, "App Preview"),
        .text = try text.toOwnedSlice(allocator),
    };
}

const AppCacheRow = struct {
    category: []u8,
    name: []u8,
    exec_cmd: []u8,
    icon_name: []u8,

    fn deinit(self: *AppCacheRow, allocator: std.mem.Allocator) void {
        allocator.free(self.category);
        allocator.free(self.name);
        allocator.free(self.exec_cmd);
        allocator.free(self.icon_name);
        self.* = undefined;
    }
};

fn lookupAppCacheRow(allocator: std.mem.Allocator, title: []const u8, action: []const u8) !?AppCacheRow {
    const path = appCachePath(allocator) catch return null;
    defer allocator.free(path);
    const data = readFileAnyPath(allocator, path, 4 * 1024 * 1024) catch return null;
    defer allocator.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const row = std.mem.trimRight(u8, line, "\r");
        if (row.len == 0) continue;
        var fields = std.mem.splitScalar(u8, row, '\t');
        const category = std.mem.trimRight(u8, fields.next() orelse continue, " \t\r");
        const name = std.mem.trimRight(u8, fields.next() orelse continue, " \t\r");
        const exec_cmd = std.mem.trimRight(u8, fields.next() orelse continue, " \t\r");
        const icon_name = std.mem.trimRight(u8, fields.next() orelse "", " \t\r");

        if (!std.mem.eql(u8, exec_cmd, action) and !std.mem.eql(u8, name, title)) continue;

        return .{
            .category = try allocator.dupe(u8, category),
            .name = try allocator.dupe(u8, name),
            .exec_cmd = try allocator.dupe(u8, exec_cmd),
            .icon_name = try allocator.dupe(u8, icon_name),
        };
    }
    return null;
}

fn appCachePath(allocator: std.mem.Allocator) ![]u8 {
    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return std.fmt.allocPrint(allocator, "{s}/.cache/waybar/wofi-app-launcher.tsv", .{home});
}

const SnippetResult = struct {
    text: []u8,
    highlight_visual_line: ?usize,
};

fn buildFilePreviewDoc(
    allocator: std.mem.Allocator,
    kind: UiKind,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
) !PreviewDoc {
    _ = title;
    _ = subtitle;
    const parsed = gtk_actions.parseFileAction(action);
    const path = if (kind == .grep) parsed.path else action;
    const line_num = if (kind == .grep) parsed.line else null;

    const data = readFileAnyPath(allocator, path, max_file_preview_bytes) catch {
        return .{
            .title = try allocator.dupe(u8, "File Preview"),
            .text = try std.fmt.allocPrint(allocator, "Unable to read: {s}", .{path}),
        };
    };
    defer allocator.free(data);

    if (std.mem.indexOfScalar(u8, data, 0) != null) {
        return .{
            .title = try allocator.dupe(u8, if (kind == .grep) "Grep Preview" else "File Preview"),
            .text = try std.fmt.allocPrint(allocator, "Binary file preview not shown\n\npath: {s}", .{path}),
        };
    }

    const snippet = try buildFileSnippetAlloc(allocator, data, line_num);
    errdefer allocator.free(snippet.text);

    var text = std.ArrayList(u8).empty;
    defer text.deinit(allocator);
    const w = text.writer(allocator);

    try w.print("path: {s}", .{path});
    if (line_num) |line| try w.print("\nline: {s}", .{line});
    try w.print("\n\n{s}", .{snippet.text});

    allocator.free(snippet.text);
    return .{
        .title = try allocator.dupe(u8, if (kind == .grep) "Grep Preview" else "File Preview"),
        .text = try text.toOwnedSlice(allocator),
        .highlight_line = if (snippet.highlight_visual_line) |line| line + 3 else null,
    };
}

fn buildFileSnippetAlloc(allocator: std.mem.Allocator, data: []const u8, target_line_opt: ?[]const u8) !SnippetResult {
    const target_line_num = if (target_line_opt) |s| std.fmt.parseInt(usize, s, 10) catch null else null;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var line_idx: usize = 1;
    var shown: usize = 0;
    var highlight_visual_line: ?usize = null;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw_line| : (line_idx += 1) {
        const line = std.mem.trimRight(u8, raw_line, "\r");
        if (target_line_num) |target| {
            const start = if (target > 2) target - 2 else 1;
            const stop = target + 2;
            if (line_idx < start or line_idx > stop) continue;
        } else if (shown >= 20) {
            break;
        }

        if (shown > 0) try out.append(allocator, '\n');
        try std.fmt.format(out.writer(allocator), "{d: >4} | ", .{line_idx});
        try appendPreviewLine(out.writer(allocator), line, 220);

        if (target_line_num != null and target_line_num.? == line_idx) {
            highlight_visual_line = shown + 1;
        }

        shown += 1;
    }

    if (shown == 0) {
        return .{ .text = try allocator.dupe(u8, "(no preview)"), .highlight_visual_line = null };
    }

    return .{
        .text = try out.toOwnedSlice(allocator),
        .highlight_visual_line = highlight_visual_line,
    };
}

fn appendPreviewLine(writer: anytype, line: []const u8, max_chars: usize) !void {
    var count: usize = 0;
    for (line) |ch| {
        if (count >= max_chars) {
            try writer.writeAll("...");
            break;
        }
        const out_ch: u8 = if (ch == '\t') ' ' else if (ch < 0x20 and ch != ' ') '.' else ch;
        try writer.writeByte(out_ch);
        count += 1;
    }
}

fn buildDirPreviewDoc(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
) !PreviewDoc {
    _ = title;
    _ = subtitle;
    const path = std.mem.trim(u8, action, " \t\r\n");
    if (path.len == 0) {
        return .{
            .title = try allocator.dupe(u8, "Folder Preview"),
            .text = try allocator.dupe(u8, "No directory path available."),
            .show_toggle = true,
            .toggle_label = if (ctx.preview_dir_tree_mode == GTRUE) "ls -la" else "tree",
        };
    }

    const is_tree = ctx.preview_dir_tree_mode == GTRUE;
    const output = if (is_tree)
        runTreePreview(allocator, path) catch |err| try std.fmt.allocPrint(allocator, "tree preview failed: {s}", .{@errorName(err)})
    else
        runLsPreview(allocator, path) catch |err| try std.fmt.allocPrint(allocator, "ls preview failed: {s}", .{@errorName(err)});
    errdefer allocator.free(output);

    var text = std.ArrayList(u8).empty;
    defer text.deinit(allocator);
    const w = text.writer(allocator);
    try w.print("path: {s}\nview: {s}\n\n", .{ path, if (is_tree) "tree" else "ls -la" });
    try w.writeAll(output);
    allocator.free(output);

    return .{
        .title = try allocator.dupe(u8, "Folder Preview"),
        .text = try text.toOwnedSlice(allocator),
        .show_toggle = true,
        .toggle_label = if (is_tree) "ls -la" else "tree",
    };
}

fn runLsPreview(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "ls", "-la", "--", path },
        .max_output_bytes = max_dir_preview_bytes,
    });
    defer allocator.free(result.stderr);
    if (result.term != .Exited or result.term.Exited != 0) {
        allocator.free(result.stdout);
        return error.CommandFailed;
    }
    return result.stdout;
}

fn runTreePreview(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "tree", "-a", "-L", "3", "--noreport", path },
        .max_output_bytes = max_dir_preview_bytes,
    });
    defer allocator.free(result.stderr);
    if (result.term != .Exited or result.term.Exited != 0) {
        allocator.free(result.stdout);
        return error.CommandFailed;
    }
    return result.stdout;
}

fn buildWorkspacePreviewDoc(
    allocator: std.mem.Allocator,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
) !?PreviewDoc {
    const ws_id = std.fmt.parseInt(i32, std.mem.trim(u8, action, " \t\r\n"), 10) catch return null;
    const details = readWorkspaceClientPreview(allocator, ws_id) catch return null;
    defer allocator.free(details);

    var text = std.ArrayList(u8).empty;
    defer text.deinit(allocator);
    const w = text.writer(allocator);
    try w.print("workspace: {s}\n", .{title});
    if (subtitle.len > 0) try w.print("{s}\n", .{subtitle});
    try w.print("\n{s}", .{details});

    return .{
        .title = try allocator.dupe(u8, "Workspace Preview"),
        .text = try text.toOwnedSlice(allocator),
    };
}

fn readWorkspaceClientPreview(allocator: std.mem.Allocator, ws_id: i32) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "hyprctl", "clients", "-j" },
        .max_output_bytes = max_workspace_preview_bytes,
    });
    defer allocator.free(result.stderr);
    if (result.term != .Exited or result.term.Exited != 0) {
        allocator.free(result.stdout);
        return error.CommandFailed;
    }
    defer allocator.free(result.stdout);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidJson;

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const w = out.writer(allocator);
    var count: usize = 0;
    for (parsed.value.array.items) |client| {
        const row = parseWorkspaceClient(client) orelse continue;
        if (!row.mapped) continue;
        if (row.workspace_id != ws_id) continue;
        if (count > 0) try w.writeByte('\n');
        const title_line = if (row.title.len > 0) row.title else if (row.class_name.len > 0) row.class_name else "Window";
        try std.fmt.format(w, "{d: >2}. {s}", .{ count + 1, title_line });
        if (row.class_name.len > 0 and !std.mem.eql(u8, row.class_name, title_line)) {
            try std.fmt.format(w, "  [{s}]", .{row.class_name});
        }
        count += 1;
        if (count >= 20) break;
    }
    if (count == 0) return allocator.dupe(u8, "(no windows found)");
    return out.toOwnedSlice(allocator);
}

const WorkspaceClientRow = struct {
    mapped: bool,
    workspace_id: i32,
    title: []const u8,
    class_name: []const u8,
};

fn parseWorkspaceClient(value: std.json.Value) ?WorkspaceClientRow {
    if (value != .object) return null;
    const obj = value.object;
    const mapped = switch (obj.get("mapped") orelse return null) {
        .bool => |b| b,
        else => false,
    };
    const workspace_id: i32 = blk: {
        const ws = obj.get("workspace") orelse break :blk -1;
        if (ws != .object) break :blk -1;
        const id_val = ws.object.get("id") orelse break :blk -1;
        break :blk switch (id_val) {
            .integer => |v| std.math.cast(i32, v) orelse -1,
            else => -1,
        };
    };
    const title = if (obj.get("title")) |v|
        switch (v) {
            .string => |s| s,
            else => "",
        }
    else
        "";
    const class_name = if (obj.get("class")) |v|
        switch (v) {
            .string => |s| s,
            else => "",
        }
    else
        "";
    return .{
        .mapped = mapped,
        .workspace_id = workspace_id,
        .title = title,
        .class_name = class_name,
    };
}

fn readFileAnyPath(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        return file.readToEndAlloc(allocator, max_bytes);
    }
    return std.fs.cwd().readFileAlloc(allocator, path, max_bytes);
}

test "showAction hides empty and unrelated hints" {
    try std.testing.expect(!showAction(.hint, ""));
    try std.testing.expect(showAction(.hint, "calc-copy:7"));
    try std.testing.expect(!showAction(.hint, "just-a-hint"));
    try std.testing.expect(showAction(.workspace, "1"));
}

test "buildFileSnippetAlloc highlights target line context" {
    const data =
        \\one
        \\two
        \\three
        \\four
        \\five
    ;
    const snippet = try buildFileSnippetAlloc(std.testing.allocator, data, "3");
    defer std.testing.allocator.free(snippet.text);
    try std.testing.expect(std.mem.indexOf(u8, snippet.text, "   3 | three") != null);
    try std.testing.expect(std.mem.indexOf(u8, snippet.text, "   2 | two") != null);
    try std.testing.expect(std.mem.indexOf(u8, snippet.text, "   4 | four") != null);
    try std.testing.expectEqual(@as(?usize, 3), snippet.highlight_visual_line);
}
