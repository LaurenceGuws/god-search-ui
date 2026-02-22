const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_widgets = @import("widgets.zig");

const c = gtk_types.c;
const CandidateKind = gtk_types.CandidateKind;
const ScoredCandidate = @import("../../search/mod.zig").ScoredCandidate;

pub fn candidateIconWidget(allocator: std.mem.Allocator, kind: CandidateKind, action: []const u8, icon: []const u8) *c.GtkWidget {
    if (kind == .app) {
        if (resolveAppIconName(allocator, icon, action)) |icon_name_z| {
            defer allocator.free(icon_name_z);
            const image = c.gtk_image_new_from_icon_name(icon_name_z.ptr);
            c.gtk_image_set_pixel_size(@ptrCast(image), 30);
            c.gtk_widget_add_css_class(image, "gs-kind-icon");
            return @ptrCast(image);
        }
    }

    const fallback_icon_z = allocator.dupeZ(u8, gtk_widgets.kindIcon(kind)) catch return c.gtk_label_new(null);
    defer allocator.free(fallback_icon_z);
    const icon_label = c.gtk_label_new(fallback_icon_z.ptr);
    c.gtk_widget_add_css_class(icon_label, "gs-kind-icon");
    return @ptrCast(icon_label);
}

pub fn hasAppGlyphFallback(rows: []const ScoredCandidate) bool {
    for (rows) |row| {
        if (row.candidate.kind != .app) continue;
        if (std.mem.trim(u8, row.candidate.icon, " \t\r\n").len > 0) continue;
        if (actionCommandToken(row.candidate.action).len == 0) return true;
    }
    return false;
}

fn appIconNameFromAction(allocator: std.mem.Allocator, action: []const u8) ?[:0]u8 {
    const token = actionCommandToken(action);
    if (token.len == 0) return null;
    return allocator.dupeZ(u8, token) catch null;
}

fn resolveAppIconName(allocator: std.mem.Allocator, icon: []const u8, action: []const u8) ?[:0]u8 {
    const explicit = std.mem.trim(u8, icon, " \t\r\n");
    if (explicit.len > 0) {
        if (resolveIconVariant(allocator, explicit)) |name| return name;
    }
    if (appIconNameFromAction(allocator, action)) |token_name| {
        defer allocator.free(token_name);
        if (resolveIconVariant(allocator, token_name)) |name| return name;
    }
    return null;
}

fn resolveIconVariant(allocator: std.mem.Allocator, raw_name: []const u8) ?[:0]u8 {
    var name = std.mem.trim(u8, raw_name, " \t\r\n\"'");
    if (name.len == 0) return null;

    var candidates: [6][]const u8 = undefined;
    var count: usize = 0;
    candidates[count] = name;
    count += 1;

    if (std.mem.lastIndexOfScalar(u8, name, '/')) |slash_idx| {
        if (slash_idx + 1 < name.len) {
            const base = name[slash_idx + 1 ..];
            candidates[count] = base;
            count += 1;
            name = base;
        }
    }

    if (std.mem.endsWith(u8, name, ".desktop") and name.len > ".desktop".len) {
        candidates[count] = name[0 .. name.len - ".desktop".len];
        count += 1;
    }
    if (std.mem.endsWith(u8, name, "-desktop") and name.len > "-desktop".len) {
        candidates[count] = name[0 .. name.len - "-desktop".len];
        count += 1;
    }

    if (count > 1 and std.mem.endsWith(u8, candidates[count - 1], ".desktop") and candidates[count - 1].len > ".desktop".len) {
        candidates[count] = candidates[count - 1][0 .. candidates[count - 1].len - ".desktop".len];
        count += 1;
    }

    var idx: usize = 0;
    while (idx < count) : (idx += 1) {
        const candidate = candidates[idx];
        if (candidate.len == 0) continue;
        if (iconExists(candidate)) {
            return allocator.dupeZ(u8, candidate) catch null;
        }
    }

    return allocator.dupeZ(u8, candidates[0]) catch null;
}

fn iconExists(name: []const u8) bool {
    const display = c.gdk_display_get_default();
    if (display == null) return false;
    const theme = c.gtk_icon_theme_get_for_display(display);
    if (theme == null) return false;
    const name_z = std.heap.page_allocator.dupeZ(u8, name) catch return false;
    defer std.heap.page_allocator.free(name_z);
    return c.gtk_icon_theme_has_icon(theme, name_z.ptr) != 0;
}

fn actionCommandToken(action: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, action, " \t\r\n");
    if (trimmed.len == 0) return "";

    var words = std.mem.tokenizeAny(u8, trimmed, " \t\r\n");
    while (words.next()) |word_raw| {
        var word = std.mem.trim(u8, word_raw, "\"'");
        if (word.len == 0) continue;
        if (std.mem.eql(u8, word, "env")) continue;
        if (word[0] == '%') continue;
        if (word[0] == '-') continue;
        if (std.mem.indexOfScalar(u8, word, '=') != null and word[0] != '/' and !std.mem.startsWith(u8, word, "./")) continue;

        if (std.mem.lastIndexOfScalar(u8, word, '/')) |slash_idx| {
            if (slash_idx + 1 < word.len) word = word[slash_idx + 1 ..];
        }
        return word;
    }
    return "";
}
