const std = @import("std");
const common_dispatch = @import("../common/dispatch.zig");
const gtk_types = @import("types.zig");
const gtk_actions = @import("actions.zig");
const gtk_row_data = @import("row_data.zig");
const gtk_query = @import("query_helpers.zig");

const c = gtk_types.c;
const UiContext = gtk_types.UiContext;
const GTRUE = gtk_types.GTRUE;
const GFALSE = gtk_types.GFALSE;
const UiKind = common_dispatch.kinds.UiKind;

pub fn toggle(ctx: *UiContext) void {
    const next = if (ctx.preview_enabled == GTRUE) GFALSE else GTRUE;
    setEnabled(ctx, next == GTRUE);
    if (next == GTRUE) {
        refreshFromSelection(ctx);
    }
}

pub fn setEnabled(ctx: *UiContext, enabled: bool) void {
    ctx.preview_enabled = if (enabled) GTRUE else GFALSE;
    c.gtk_widget_set_visible(ctx.preview_panel, ctx.preview_enabled);
    if (ctx.preview_enabled == GFALSE) {
        ctx.last_preview_hash = 0;
    }
}

pub fn clear(ctx: *UiContext) void {
    if (ctx.preview_enabled == GFALSE) return;
    setMarkupIfChanged(ctx, "<span foreground=\"#7c8498\">No selection</span>");
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

    const kind = gtk_row_data.kind(row);
    const title = gtk_row_data.title(row) orelse "";
    const subtitle = gtk_row_data.subtitle(row) orelse "";
    const action = gtk_row_data.action(row) orelse "";

    const allocator_ptr: *std.mem.Allocator = @ptrCast(@alignCast(ctx.allocator));
    const allocator = allocator_ptr.*;
    const markup = buildPreviewMarkup(ctx, allocator, kind, title, subtitle, action) catch return;
    defer allocator.free(markup);
    setMarkupIfChanged(ctx, markup);
}

fn setMarkupIfChanged(ctx: *UiContext, markup: []const u8) void {
    const h = std.hash.Wyhash.hash(0, markup);
    if (ctx.last_preview_hash == h) return;
    const z = std.heap.page_allocator.dupeZ(u8, markup) catch return;
    defer std.heap.page_allocator.free(z);
    c.gtk_label_set_markup(ctx.preview_label, z.ptr);
    ctx.last_preview_hash = h;
}

fn buildPreviewMarkup(
    ctx: *UiContext,
    allocator: std.mem.Allocator,
    kind: UiKind,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
) ![]u8 {
    switch (kind) {
        .app => if (try buildAppPreviewMarkup(allocator, title, subtitle, action)) |markup| return markup,
        .file, .grep => if (try buildFilePreviewMarkup(allocator, kind, title, subtitle, action)) |markup| return markup,
        .workspace => if (try buildWorkspacePreviewMarkup(allocator, title, subtitle, action)) |markup| return markup,
        else => {},
    }
    _ = ctx;
    return buildGenericPreviewMarkup(allocator, kind, title, subtitle, action);
}

fn buildGenericPreviewMarkup(
    allocator: std.mem.Allocator,
    kind: UiKind,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
) ![]u8 {
    const kind_text = common_dispatch.kinds.statusLabel(kind);
    const title_esc = try gtk_query.escapeMarkupAlloc(allocator, if (title.len > 0) title else "(untitled)");
    defer allocator.free(title_esc);
    const subtitle_trim = std.mem.trim(u8, subtitle, " \t\r\n");
    const action_trim = std.mem.trim(u8, action, " \t\r\n");
    const subtitle_esc = if (subtitle_trim.len > 0) try gtk_query.escapeMarkupAlloc(allocator, subtitle_trim) else null;
    defer if (subtitle_esc) |s| allocator.free(s);
    const action_esc = if (showAction(kind, action_trim)) try gtk_query.escapeMarkupAlloc(allocator, action_trim) else null;
    defer if (action_esc) |s| allocator.free(s);

    var body = std.ArrayList(u8).empty;
    defer body.deinit(allocator);
    const w = body.writer(allocator);

    try w.print("<span foreground=\"#7c8498\" weight=\"700\">{s}</span>\n", .{kind_text});
    try w.print("<span foreground=\"#f1f5ff\" weight=\"700\" size=\"large\">{s}</span>", .{title_esc});

    if (subtitle_esc) |sub| {
        try w.print("\n\n<span foreground=\"#9aa1b5\" weight=\"700\">Details</span>\n<span foreground=\"#cdd5e8\">{s}</span>", .{sub});
    }

    if (action_esc) |act| {
        try w.print("\n\n<span foreground=\"#9aa1b5\" weight=\"700\">Action</span>\n<span foreground=\"#b6c2df\" font_family=\"monospace\">{s}</span>", .{act});
    }

    if (kind == .hint and std.mem.startsWith(u8, action_trim, "calc-copy:")) {
        const value = action_trim["calc-copy:".len..];
        const value_esc = try gtk_query.escapeMarkupAlloc(allocator, value);
        defer allocator.free(value_esc);
        try w.print("\n\n<span foreground=\"#7fb0ff\">Enter copies result to clipboard</span>\n<span foreground=\"#f8fbff\" weight=\"700\">{s}</span>", .{value_esc});
    }

    if (kind == .module) {
        try w.print("\n\n<span foreground=\"#7fb0ff\">Enter activates module filter</span>", .{});
    }

    return body.toOwnedSlice(allocator);
}

fn showAction(kind: UiKind, action: []const u8) bool {
    if (action.len == 0) return false;
    return switch (kind) {
        .module => true,
        .hint => std.mem.startsWith(u8, action, "calc-copy:"),
        else => true,
    };
}

fn buildAppPreviewMarkup(
    allocator: std.mem.Allocator,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
) !?[]u8 {
    var row = try lookupAppCacheRow(allocator, title, action) orelse return null;
    defer row.deinit(allocator);

    const name_esc = try gtk_query.escapeMarkupAlloc(allocator, row.name);
    defer allocator.free(name_esc);
    const cat_esc = try gtk_query.escapeMarkupAlloc(allocator, row.category);
    defer allocator.free(cat_esc);
    const exec_esc = try gtk_query.escapeMarkupAlloc(allocator, row.exec_cmd);
    defer allocator.free(exec_esc);
    const icon_esc = try gtk_query.escapeMarkupAlloc(allocator, if (row.icon_name.len > 0) row.icon_name else "(none)");
    defer allocator.free(icon_esc);
    const subtitle_esc = try gtk_query.escapeMarkupAlloc(allocator, subtitle);
    defer allocator.free(subtitle_esc);

    const markup = try std.fmt.allocPrint(
        allocator,
        "<span foreground=\"#7c8498\" weight=\"700\">app</span>\n" ++
            "<span foreground=\"#f1f5ff\" weight=\"700\" size=\"large\">{s}</span>\n\n" ++
            "<span foreground=\"#9aa1b5\" weight=\"700\">Category</span>\n<span foreground=\"#cdd5e8\">{s}</span>\n\n" ++
            "<span foreground=\"#9aa1b5\" weight=\"700\">Exec</span>\n<span foreground=\"#b6c2df\" font_family=\"monospace\">{s}</span>\n\n" ++
            "<span foreground=\"#9aa1b5\" weight=\"700\">Icon</span>\n<span foreground=\"#cdd5e8\">{s}</span>\n\n" ++
            "<span foreground=\"#7fb0ff\">Enter launches app</span>\n" ++
            "<span foreground=\"#7c8498\">List subtitle: {s}</span>",
        .{ name_esc, cat_esc, exec_esc, icon_esc, subtitle_esc },
    );
    return markup;
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

fn buildFilePreviewMarkup(
    allocator: std.mem.Allocator,
    kind: UiKind,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
) !?[]u8 {
    _ = title;
    const parsed = gtk_actions.parseFileAction(action);
    const path = if (kind == .grep) parsed.path else action;
    const line_num = if (kind == .grep) parsed.line else null;

    const data = readFileAnyPath(allocator, path, 256 * 1024) catch return null;
    defer allocator.free(data);
    if (std.mem.indexOfScalar(u8, data, 0) != null) {
        const path_esc = try gtk_query.escapeMarkupAlloc(allocator, path);
        defer allocator.free(path_esc);
        const markup = try std.fmt.allocPrint(
            allocator,
            "<span foreground=\"#7c8498\" weight=\"700\">{s}</span>\n<span foreground=\"#f1f5ff\" weight=\"700\">{s}</span>\n\n<span foreground=\"#e0a46e\">Binary file preview not shown</span>",
            .{ if (kind == .grep) "match" else "file", path_esc },
        );
        return markup;
    }

    const snippet = try buildFileSnippetAlloc(allocator, data, line_num);
    defer allocator.free(snippet);
    const path_esc = try gtk_query.escapeMarkupAlloc(allocator, path);
    defer allocator.free(path_esc);
    const subtitle_esc = try gtk_query.escapeMarkupAlloc(allocator, subtitle);
    defer allocator.free(subtitle_esc);
    const snippet_esc = try gtk_query.escapeMarkupAlloc(allocator, snippet);
    defer allocator.free(snippet_esc);

    const markup = try std.fmt.allocPrint(
        allocator,
        "<span foreground=\"#7c8498\" weight=\"700\">{s}</span>\n" ++
            "<span foreground=\"#f1f5ff\" weight=\"700\">{s}</span>\n\n" ++
            "<span foreground=\"#9aa1b5\" weight=\"700\">Path</span>\n<span foreground=\"#b6c2df\" font_family=\"monospace\">{s}</span>\n\n" ++
            "<span foreground=\"#9aa1b5\" weight=\"700\">Context</span>\n<span foreground=\"#cdd5e8\" font_family=\"monospace\">{s}</span>\n\n" ++
            "<span foreground=\"#7c8498\">{s}</span>",
        .{ if (kind == .grep) "match" else "file", path_esc, path_esc, snippet_esc, subtitle_esc },
    );
    return markup;
}

fn buildFileSnippetAlloc(allocator: std.mem.Allocator, data: []const u8, target_line_opt: ?[]const u8) ![]u8 {
    const target_line_num = if (target_line_opt) |s| std.fmt.parseInt(usize, s, 10) catch null else null;
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var line_idx: usize = 1;
    var shown: usize = 0;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw_line| : (line_idx += 1) {
        const line = std.mem.trimRight(u8, raw_line, "\r");
        if (target_line_num) |target| {
            const start = if (target > 2) target - 2 else 1;
            const stop = target + 2;
            if (line_idx < start or line_idx > stop) continue;
        } else if (shown >= 12) {
            break;
        }

        if (shown > 0) try out.append(allocator, '\n');
        const prefix = if (target_line_num != null and target_line_num.? == line_idx) ">" else " ";
        try std.fmt.format(out.writer(allocator), "{s}{d: >4} | ", .{ prefix, line_idx });
        try appendPreviewLine(out.writer(allocator), line, 180);
        shown += 1;
    }

    if (shown == 0) return allocator.dupe(u8, "(no preview)");
    return out.toOwnedSlice(allocator);
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

fn buildWorkspacePreviewMarkup(
    allocator: std.mem.Allocator,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
) !?[]u8 {
    const ws_id = std.fmt.parseInt(i32, std.mem.trim(u8, action, " \t\r\n"), 10) catch return null;
    const details = readWorkspaceClientPreview(allocator, ws_id) catch return null;
    defer allocator.free(details);

    const title_esc = try gtk_query.escapeMarkupAlloc(allocator, title);
    defer allocator.free(title_esc);
    const subtitle_esc = try gtk_query.escapeMarkupAlloc(allocator, subtitle);
    defer allocator.free(subtitle_esc);
    const details_esc = try gtk_query.escapeMarkupAlloc(allocator, details);
    defer allocator.free(details_esc);

    const markup = try std.fmt.allocPrint(
        allocator,
        "<span foreground=\"#7c8498\" weight=\"700\">workspace</span>\n" ++
            "<span foreground=\"#f1f5ff\" weight=\"700\" size=\"large\">{s}</span>\n\n" ++
            "<span foreground=\"#9aa1b5\" weight=\"700\">Summary</span>\n<span foreground=\"#cdd5e8\">{s}</span>\n\n" ++
            "<span foreground=\"#9aa1b5\" weight=\"700\">Windows</span>\n<span foreground=\"#cdd5e8\" font_family=\"monospace\">{s}</span>\n\n" ++
            "<span foreground=\"#7fb0ff\">Enter switches to this workspace</span>",
        .{ title_esc, subtitle_esc, details_esc },
    );
    return markup;
}

fn readWorkspaceClientPreview(allocator: std.mem.Allocator, ws_id: i32) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "hyprctl", "clients", "-j" },
        .max_output_bytes = 8 * 1024 * 1024,
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
    defer std.testing.allocator.free(snippet);
    try std.testing.expect(std.mem.indexOf(u8, snippet, ">   3 | three") != null);
    try std.testing.expect(std.mem.indexOf(u8, snippet, "    2 | two") != null);
    try std.testing.expect(std.mem.indexOf(u8, snippet, "    4 | four") != null);
}
