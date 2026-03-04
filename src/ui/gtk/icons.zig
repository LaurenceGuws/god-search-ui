const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_widgets = @import("widgets.zig");

const c = gtk_types.c;
const CandidateKind = gtk_types.CandidateKind;
const ScoredCandidate = @import("../../search/mod.zig").ScoredCandidate;

pub fn candidateIconWidget(allocator: std.mem.Allocator, kind: CandidateKind, action: []const u8, icon: []const u8) *c.GtkWidget {
    if (kind == .web) {
        const explicit = std.mem.trim(u8, icon, " \t\r\n");
        if (explicit.len > 0) {
            const icon_name_z = allocator.dupeZ(u8, explicit) catch null;
            if (icon_name_z) |name| {
                defer allocator.free(name);
                const image = c.gtk_image_new_from_icon_name(name.ptr);
                c.gtk_image_set_pixel_size(@ptrCast(image), 30);
                c.gtk_widget_add_css_class(image, "gs-kind-icon");
                return @ptrCast(image);
            }
        }
    }
    if (kind == .app) {
        if (resolveAppIconFilePath(allocator, icon)) |icon_path_z| {
            defer allocator.free(icon_path_z);
            const image = c.gtk_image_new_from_file(icon_path_z.ptr);
            c.gtk_image_set_pixel_size(@ptrCast(image), 30);
            c.gtk_widget_add_css_class(image, "gs-kind-icon");
            return @ptrCast(image);
        }
        if (resolveAppIconName(allocator, icon, action)) |icon_name_z| {
            defer allocator.free(icon_name_z);
            const image = c.gtk_image_new_from_icon_name(icon_name_z.ptr);
            c.gtk_image_set_pixel_size(@ptrCast(image), 30);
            c.gtk_widget_add_css_class(image, "gs-kind-icon");
            return @ptrCast(image);
        }
    }
    if ((kind == .action or kind == .hint) and isPackageAction(action)) {
        if (resolvePackageIconName(allocator, icon, action)) |icon_name_z| {
            defer allocator.free(icon_name_z);
            const image = c.gtk_image_new_from_icon_name(icon_name_z.ptr);
            c.gtk_image_set_pixel_size(@ptrCast(image), 30);
            c.gtk_widget_add_css_class(image, "gs-kind-icon");
            return @ptrCast(image);
        }
        const fallback = c.gtk_image_new_from_icon_name("system-software-install-symbolic");
        c.gtk_image_set_pixel_size(@ptrCast(fallback), 30);
        c.gtk_widget_add_css_class(fallback, "gs-kind-icon");
        return @ptrCast(fallback);
    }

    const fallback_icon_z = allocator.dupeZ(u8, gtk_widgets.kindIcon(kind)) catch return c.gtk_label_new(null);
    defer allocator.free(fallback_icon_z);
    const icon_label = c.gtk_label_new(fallback_icon_z.ptr);
    c.gtk_widget_add_css_class(icon_label, "gs-kind-icon");
    return @ptrCast(icon_label);
}

fn isPackageAction(action: []const u8) bool {
    return std.mem.startsWith(u8, action, "pkg-install:") or
        std.mem.startsWith(u8, action, "pkg-update:") or
        std.mem.startsWith(u8, action, "pkg-remove:");
}

fn parsePackageNameFromAction(action: []const u8) []const u8 {
    if (std.mem.startsWith(u8, action, "pkg-install:")) return action["pkg-install:".len..];
    if (std.mem.startsWith(u8, action, "pkg-update:")) return action["pkg-update:".len..];
    if (std.mem.startsWith(u8, action, "pkg-remove:")) return action["pkg-remove:".len..];
    return "";
}

fn resolvePackageIconName(allocator: std.mem.Allocator, icon: []const u8, action: []const u8) ?[:0]u8 {
    const explicit = std.mem.trim(u8, icon, " \t\r\n");
    if (explicit.len > 0) {
        if (resolveIconVariant(allocator, explicit)) |name| return name;
    }

    const package_name = std.mem.trim(u8, parsePackageNameFromAction(action), " \t\r\n");
    if (package_name.len == 0) return null;

    var candidates: [8][]const u8 = undefined;
    var count: usize = 0;
    candidates[count] = package_name;
    count += 1;

    if (std.mem.endsWith(u8, package_name, "-bin") and package_name.len > "-bin".len) {
        candidates[count] = package_name[0 .. package_name.len - "-bin".len];
        count += 1;
    }
    if (std.mem.endsWith(u8, package_name, "-git") and package_name.len > "-git".len) {
        candidates[count] = package_name[0 .. package_name.len - "-git".len];
        count += 1;
    }
    if (std.mem.indexOfScalar(u8, package_name, '-')) |dash| {
        if (dash > 0) {
            candidates[count] = package_name[0..dash];
            count += 1;
        }
    }

    var idx: usize = 0;
    while (idx < count) : (idx += 1) {
        const name = candidates[idx];
        if (name.len == 0) continue;
        if (resolveIconVariant(allocator, name)) |resolved| return resolved;
    }
    return null;
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
    if (steamGameIconNameFromAction(allocator, action)) |steam_icon_name| {
        defer allocator.free(steam_icon_name);
        if (resolveIconVariant(allocator, steam_icon_name)) |name| return name;
    }
    if (appIconNameFromAction(allocator, action)) |token_name| {
        defer allocator.free(token_name);
        if (resolveIconVariant(allocator, token_name)) |name| return name;
    }
    return null;
}

fn resolveAppIconFilePath(allocator: std.mem.Allocator, icon: []const u8) ?[:0]u8 {
    const raw = std.mem.trim(u8, icon, " \t\r\n\"'");
    if (raw.len == 0) return null;
    const path = expandHomePath(allocator, raw) catch return null;
    defer allocator.free(path);
    if (!fileExistsAnyPath(path)) return null;
    return allocator.dupeZ(u8, path) catch null;
}

fn resolveIconVariant(allocator: std.mem.Allocator, raw_name: []const u8) ?[:0]u8 {
    var name = std.mem.trim(u8, raw_name, " \t\r\n\"'");
    if (name.len == 0) return null;

    var candidates: [12][]const u8 = undefined;
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
    if (std.mem.endsWith(u8, name, ".png") and name.len > ".png".len) {
        candidates[count] = name[0 .. name.len - ".png".len];
        count += 1;
    }
    if (std.mem.endsWith(u8, name, ".svg") and name.len > ".svg".len) {
        candidates[count] = name[0 .. name.len - ".svg".len];
        count += 1;
    }
    if (std.mem.endsWith(u8, name, ".xpm") and name.len > ".xpm".len) {
        candidates[count] = name[0 .. name.len - ".xpm".len];
        count += 1;
    }

    var idx: usize = 0;
    while (idx < count) : (idx += 1) {
        const candidate = candidates[idx];
        if (candidate.len == 0) continue;
        if (std.mem.indexOfScalar(u8, candidate, ' ') != null) {
            var dashed_buf: [256]u8 = undefined;
            const dashed = replaceSpacesWith(candidate, '-', &dashed_buf) orelse candidate;
            if (iconExists(dashed)) {
                return allocator.dupeZ(u8, dashed) catch null;
            }
        }
        if (iconExists(candidate)) {
            return allocator.dupeZ(u8, candidate) catch null;
        }
    }

    return null;
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

fn steamGameIconNameFromAction(allocator: std.mem.Allocator, action: []const u8) ?[:0]u8 {
    const marker = "steam://rungameid/";
    const idx = std.mem.indexOf(u8, action, marker) orelse return null;
    const rest = action[idx + marker.len ..];
    var end: usize = 0;
    while (end < rest.len and std.ascii.isDigit(rest[end])) : (end += 1) {}
    if (end == 0) return null;
    const name = std.fmt.allocPrint(allocator, "steam_icon_{s}", .{rest[0..end]}) catch return null;
    defer allocator.free(name);
    return allocator.dupeZ(u8, name) catch null;
}

fn expandHomePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (!std.mem.startsWith(u8, path, "~/")) return allocator.dupe(u8, path);
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return allocator.dupe(u8, path);
    defer allocator.free(home);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ home, path[2..] });
}

fn fileExistsAnyPath(path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) {
        std.fs.accessAbsolute(path, .{}) catch return false;
        return true;
    }
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn replaceSpacesWith(input: []const u8, replacement: u8, buf: []u8) ?[]const u8 {
    if (input.len > buf.len) return null;
    @memcpy(buf[0..input.len], input);
    for (buf[0..input.len]) |*ch| {
        if (ch.* == ' ') ch.* = replacement;
    }
    return buf[0..input.len];
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

test "actionCommandToken extracts executable token from shell-like actions" {
    try std.testing.expectEqualStrings("kitty", actionCommandToken("env TERM=xterm /usr/bin/kitty --single-instance"));
    try std.testing.expectEqualStrings("run.sh", actionCommandToken("./scripts/run.sh --dry-run"));
    try std.testing.expectEqualStrings("firefox", actionCommandToken("  'firefox'  "));
}

test "actionCommandToken ignores placeholders flags and assignments" {
    try std.testing.expectEqualStrings("", actionCommandToken("%f --arg"));
    try std.testing.expectEqualStrings("", actionCommandToken("FOO=bar --flag"));
}

test "appIconNameFromAction follows token parsing heuristics" {
    var allocator = std.testing.allocator;
    const name = appIconNameFromAction(allocator, "env WAYLAND_DISPLAY=wayland-1 /usr/bin/wezterm start") orelse {
        return std.testing.expect(false);
    };
    defer allocator.free(name);
    try std.testing.expectEqualStrings("wezterm", name);
}

test "steamGameIconNameFromAction extracts rungameid icon name" {
    var allocator = std.testing.allocator;
    const icon_name = steamGameIconNameFromAction(allocator, "steam steam://rungameid/570") orelse {
        return std.testing.expect(false);
    };
    defer allocator.free(icon_name);
    try std.testing.expectEqualStrings("steam_icon_570", icon_name);
    try std.testing.expect(steamGameIconNameFromAction(allocator, "steam steam://open/friends") == null);
}

test "hasAppGlyphFallback only triggers for app rows without icon and token" {
    const rows_with_fallback = [_]ScoredCandidate{
        .{
            .candidate = .{
                .kind = .app,
                .title = "Broken desktop entry",
                .subtitle = "",
                .action = "--flag-only",
                .icon = "",
            },
            .score = 1,
        },
    };
    try std.testing.expect(hasAppGlyphFallback(&rows_with_fallback));

    const rows_without_fallback = [_]ScoredCandidate{
        .{
            .candidate = .{
                .kind = .app,
                .title = "Has icon name",
                .subtitle = "",
                .action = "--flag-only",
                .icon = "org.example.App",
            },
            .score = 1,
        },
        .{
            .candidate = .{
                .kind = .window,
                .title = "Window row",
                .subtitle = "",
                .action = "",
                .icon = "",
            },
            .score = 1,
        },
    };
    try std.testing.expect(!hasAppGlyphFallback(&rows_without_fallback));
}
