const std = @import("std");
const gtk_types = @import("types.zig");
const gtk_widgets = @import("widgets.zig");

const c = gtk_types.c;
const CandidateKind = gtk_types.CandidateKind;
const ScoredCandidate = @import("../../search/mod.zig").ScoredCandidate;
const YaziIconSection = enum { none, dirs, files, exts };

var yazi_icons_mu: std.Thread.Mutex = .{};
var yazi_icons_loaded: bool = false;
var yazi_dir_icons: std.StringHashMapUnmanaged([]const u8) = .{};
var yazi_file_icons: std.StringHashMapUnmanaged([]const u8) = .{};
var yazi_ext_icons: std.StringHashMapUnmanaged([]const u8) = .{};

pub fn invalidateYaziIconCache() void {
    yazi_icons_mu.lock();
    defer yazi_icons_mu.unlock();
    clearYaziIconMapsLocked();
    yazi_icons_loaded = false;
}

pub fn candidateIconWidget(
    allocator: std.mem.Allocator,
    kind: CandidateKind,
    title: []const u8,
    subtitle: []const u8,
    action: []const u8,
    icon: []const u8,
) *c.GtkWidget {
    if (kind == .hint and std.mem.startsWith(u8, action, "nerd-copy:")) {
        const glyph = std.mem.trim(u8, icon, " \t\r\n");
        if (glyph.len > 0) {
            const glyph_z = allocator.dupeZ(u8, glyph) catch null;
            if (glyph_z) |text| {
                defer allocator.free(text);
                const icon_label = c.gtk_label_new(text.ptr);
                c.gtk_widget_add_css_class(icon_label, "gs-kind-icon");
                c.gtk_widget_add_css_class(icon_label, "gs-nerd-glyph-icon");
                return @ptrCast(icon_label);
            }
        }
        const glyph_from_action = std.mem.trim(u8, action["nerd-copy:".len..], " \t\r\n");
        if (glyph_from_action.len > 0) {
            const glyph_z = allocator.dupeZ(u8, glyph_from_action) catch null;
            if (glyph_z) |text| {
                defer allocator.free(text);
                const icon_label = c.gtk_label_new(text.ptr);
                c.gtk_widget_add_css_class(icon_label, "gs-kind-icon");
                c.gtk_widget_add_css_class(icon_label, "gs-nerd-glyph-icon");
                return @ptrCast(icon_label);
            }
        }
    }
    if (kind == .hint and std.mem.startsWith(u8, action, "emoji-copy:")) {
        const glyph = std.mem.trim(u8, icon, " \t\r\n");
        if (glyph.len > 0) {
            const glyph_z = allocator.dupeZ(u8, glyph) catch null;
            if (glyph_z) |text| {
                defer allocator.free(text);
                const icon_label = c.gtk_label_new(text.ptr);
                c.gtk_widget_add_css_class(icon_label, "gs-kind-icon");
                c.gtk_widget_add_css_class(icon_label, "gs-emoji-glyph-icon");
                return @ptrCast(icon_label);
            }
        }
        const glyph_from_action = std.mem.trim(u8, action["emoji-copy:".len..], " \t\r\n");
        if (glyph_from_action.len > 0) {
            const glyph_z = allocator.dupeZ(u8, glyph_from_action) catch null;
            if (glyph_z) |text| {
                defer allocator.free(text);
                const icon_label = c.gtk_label_new(text.ptr);
                c.gtk_widget_add_css_class(icon_label, "gs-kind-icon");
                c.gtk_widget_add_css_class(icon_label, "gs-emoji-glyph-icon");
                return @ptrCast(icon_label);
            }
        }
    }

    if (kind == .web) {
        const explicit = std.mem.trim(u8, icon, " \t\r\n");
        if (explicit.len > 0) {
            if (resolveIconFileForCandidate(allocator, explicit, "")) |icon_path_z| {
                defer allocator.free(icon_path_z);
                const image = c.gtk_image_new_from_file(icon_path_z.ptr);
                c.gtk_image_set_pixel_size(@ptrCast(image), 30);
                c.gtk_widget_add_css_class(image, "gs-kind-icon");
                return @ptrCast(image);
            }
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
    if (kind == .window) {
        if (resolveWindowIconName(allocator, icon, subtitle, title)) |icon_name_z| {
            defer allocator.free(icon_name_z);
            const image = c.gtk_image_new_from_icon_name(icon_name_z.ptr);
            c.gtk_image_set_pixel_size(@ptrCast(image), 30);
            c.gtk_widget_add_css_class(image, "gs-kind-icon");
            return @ptrCast(image);
        }
    }
    if (kind == .notification) {
        if (resolveNotificationIconName(allocator, icon, subtitle)) |icon_name_z| {
            defer allocator.free(icon_name_z);
            const image = c.gtk_image_new_from_icon_name(icon_name_z.ptr);
            c.gtk_image_set_pixel_size(@ptrCast(image), 30);
            c.gtk_widget_add_css_class(image, "gs-kind-icon");
            return @ptrCast(image);
        }
    }
    if (kind == .file) {
        if (resolveIconFileForCandidate(allocator, icon, action)) |icon_path_z| {
            defer allocator.free(icon_path_z);
            const image = c.gtk_image_new_from_file(icon_path_z.ptr);
            c.gtk_image_set_pixel_size(@ptrCast(image), 30);
            c.gtk_widget_add_css_class(image, "gs-kind-icon");
            return @ptrCast(image);
        }
    }
    if (kind == .file or kind == .grep or kind == .dir) {
        if (resolveYaziGlyph(kind, title, subtitle, action)) |glyph| {
            const glyph_z = allocator.dupeZ(u8, glyph) catch null;
            if (glyph_z) |text| {
                defer allocator.free(text);
                const icon_label = c.gtk_label_new(text.ptr);
                c.gtk_widget_add_css_class(icon_label, "gs-kind-icon");
                c.gtk_widget_add_css_class(icon_label, "gs-nerd-glyph-icon");
                return @ptrCast(icon_label);
            }
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

fn resolveWindowIconName(
    allocator: std.mem.Allocator,
    icon: []const u8,
    class_name: []const u8,
    title: []const u8,
) ?[:0]u8 {
    const explicit = std.mem.trim(u8, icon, " \t\r\n\"'");
    if (explicit.len > 0) {
        if (resolveIconVariantWithTransforms(allocator, explicit)) |name| return name;
    }

    const class_trimmed = std.mem.trim(u8, class_name, " \t\r\n\"'");
    if (class_trimmed.len > 0) {
        if (resolveIconVariantWithTransforms(allocator, class_trimmed)) |name| return name;
        if (windowIconAlias(class_trimmed)) |alias| {
            if (resolveIconVariantWithTransforms(allocator, alias)) |name| return name;
        }
    }

    const title_trimmed = std.mem.trim(u8, title, " \t\r\n\"'");
    if (title_trimmed.len > 0) {
        if (resolveIconVariantWithTransforms(allocator, title_trimmed)) |name| return name;
        const first_word_end = std.mem.indexOfAny(u8, title_trimmed, " \t|:-") orelse title_trimmed.len;
        if (first_word_end > 0 and first_word_end < title_trimmed.len) {
            const first_word = title_trimmed[0..first_word_end];
            if (resolveIconVariantWithTransforms(allocator, first_word)) |name| return name;
            if (windowIconAlias(first_word)) |alias| {
                if (resolveIconVariantWithTransforms(allocator, alias)) |name| return name;
            }
        }
    }
    return null;
}

fn resolveNotificationIconName(
    allocator: std.mem.Allocator,
    icon: []const u8,
    subtitle: []const u8,
) ?[:0]u8 {
    const explicit = std.mem.trim(u8, icon, " \t\r\n\"'");
    if (explicit.len > 0) {
        if (resolveIconVariantWithTransforms(allocator, explicit)) |name| return name;
        if (windowIconAlias(explicit)) |alias| {
            if (resolveIconVariantWithTransforms(allocator, alias)) |name| return name;
        }
    }
    if (notificationAppNameFromSubtitle(subtitle)) |app_name| {
        if (resolveIconVariantWithTransforms(allocator, app_name)) |name| return name;
        if (windowIconAlias(app_name)) |alias| {
            if (resolveIconVariantWithTransforms(allocator, alias)) |name| return name;
        }
    }
    return null;
}

fn notificationAppNameFromSubtitle(subtitle: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, subtitle, " \t\r\n");
    if (trimmed.len == 0) return null;
    const sep = std.mem.indexOf(u8, trimmed, " | ") orelse return trimmed;
    if (sep == 0) return null;
    return trimmed[0..sep];
}

fn resolveYaziGlyph(kind: CandidateKind, title: []const u8, subtitle: []const u8, action: []const u8) ?[]const u8 {
    ensureYaziIconsLoaded();
    const path = switch (kind) {
        .file, .dir => std.mem.trim(u8, action, " \t\r\n"),
        .grep => grepPathFromAction(action),
        else => "",
    };

    if (kind == .dir) {
        var dir_name = if (path.len > 0) std.fs.path.basename(path) else "";
        if (dir_name.len == 0) dir_name = std.mem.trim(u8, title, " \t\r\n");
        if (dir_name.len == 0) dir_name = std.mem.trim(u8, subtitle, " \t\r\n");
        if (lookupYaziMap(&yazi_dir_icons, dir_name)) |glyph| return glyph;
    }

    var file_name = if (path.len > 0) std.fs.path.basename(path) else "";
    if (file_name.len == 0) file_name = std.mem.trim(u8, title, " \t\r\n");
    if (file_name.len > 0) {
        if (lookupYaziMap(&yazi_file_icons, file_name)) |glyph| return glyph;
        if (extensionWithoutDot(file_name)) |ext| {
            if (lookupYaziMap(&yazi_ext_icons, ext)) |glyph| return glyph;
        }
    }

    return null;
}

fn grepPathFromAction(action: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, action, " \t\r\n");
    if (trimmed.len == 0) return "";
    if (std.mem.lastIndexOfScalar(u8, trimmed, ':')) |idx| {
        if (idx + 1 < trimmed.len and isDigitsOnly(trimmed[idx + 1 ..])) {
            return trimmed[0..idx];
        }
    }
    return trimmed;
}

fn extensionWithoutDot(name: []const u8) ?[]const u8 {
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return null;
    if (dot + 1 >= name.len) return null;
    return name[dot + 1 ..];
}

fn ensureYaziIconsLoaded() void {
    yazi_icons_mu.lock();
    defer yazi_icons_mu.unlock();
    if (yazi_icons_loaded) return;
    yazi_icons_loaded = true;
    loadYaziIcons() catch |err| {
        std.log.warn("yazi icon map load failed: {s}", .{@errorName(err)});
    };
}

fn clearYaziMapLocked(map: *std.StringHashMapUnmanaged([]const u8)) void {
    var it = map.iterator();
    while (it.next()) |entry| {
        std.heap.page_allocator.free(@constCast(entry.key_ptr.*));
        std.heap.page_allocator.free(@constCast(entry.value_ptr.*));
    }
    map.deinit(std.heap.page_allocator);
    map.* = .{};
}

fn clearYaziIconMapsLocked() void {
    clearYaziMapLocked(&yazi_dir_icons);
    clearYaziMapLocked(&yazi_file_icons);
    clearYaziMapLocked(&yazi_ext_icons);
}

fn loadYaziIcons() !void {
    const allocator = std.heap.page_allocator;
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return;
    defer allocator.free(home);
    const path = try std.fmt.allocPrint(allocator, "{s}/personal/bash_engine/dots/yazi/theme-light.toml", .{home});
    defer allocator.free(path);

    const data = std.fs.openFileAbsolute(path, .{}) catch return;
    defer data.close();
    const content = data.readToEndAlloc(allocator, 16 * 1024 * 1024) catch return;
    defer allocator.free(content);

    var in_icon = false;
    var section: YaziIconSection = .none;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, std.mem.trimRight(u8, line_raw, "\r"), " \t");
        if (line.len == 0 or line[0] == '#') continue;
        if (line[0] == '[' and line[line.len - 1] == ']') {
            in_icon = std.mem.eql(u8, line, "[icon]");
            section = .none;
            continue;
        }
        if (!in_icon) continue;
        if (std.mem.startsWith(u8, line, "dirs") and std.mem.indexOfScalar(u8, line, '[') != null) {
            section = .dirs;
            continue;
        }
        if (std.mem.startsWith(u8, line, "files") and std.mem.indexOfScalar(u8, line, '[') != null) {
            section = .files;
            continue;
        }
        if (std.mem.startsWith(u8, line, "exts") and std.mem.indexOfScalar(u8, line, '[') != null) {
            section = .exts;
            continue;
        }
        if (line.len == 1 and line[0] == ']') {
            section = .none;
            continue;
        }
        if (section == .none or line[0] != '{') continue;

        const name = extractTomlQuotedValue(line, "name") orelse continue;
        const text = extractTomlQuotedValue(line, "text") orelse continue;
        const key = lowerDup(allocator, name) catch continue;
        const value = allocator.dupe(u8, text) catch {
            allocator.free(key);
            continue;
        };
        const target = switch (section) {
            .dirs => &yazi_dir_icons,
            .files => &yazi_file_icons,
            .exts => &yazi_ext_icons,
            .none => unreachable,
        };
        const gop = target.getOrPut(allocator, key) catch {
            allocator.free(value);
            allocator.free(key);
            continue;
        };
        if (gop.found_existing) {
            allocator.free(gop.key_ptr.*);
            allocator.free(value);
        } else {
            gop.key_ptr.* = key;
            gop.value_ptr.* = value;
        }
    }
}

fn lookupYaziMap(map: *std.StringHashMapUnmanaged([]const u8), key_raw: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, key_raw, " \t\r\n");
    if (trimmed.len == 0) return null;
    var lower_buf: [256]u8 = undefined;
    const key = toLowerAscii(trimmed, &lower_buf) orelse return null;
    return map.get(key);
}

fn lowerDup(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, input.len);
    for (input, 0..) |ch, idx| out[idx] = std.ascii.toLower(ch);
    return out;
}

fn extractTomlQuotedValue(line: []const u8, field: []const u8) ?[]const u8 {
    var marker_buf: [64]u8 = undefined;
    const marker = std.fmt.bufPrint(&marker_buf, "{s} = \"", .{field}) catch return null;
    const idx = std.mem.indexOf(u8, line, marker) orelse return null;
    const start = idx + marker.len;
    const rest = line[start..];
    const end_rel = std.mem.indexOfScalar(u8, rest, '"') orelse return null;
    return rest[0..end_rel];
}

fn isDigitsOnly(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |ch| {
        if (!std.ascii.isDigit(ch)) return false;
    }
    return true;
}

fn resolveIconVariantWithTransforms(allocator: std.mem.Allocator, token: []const u8) ?[:0]u8 {
    if (resolveIconVariant(allocator, token)) |name| return name;

    var lower_buf: [256]u8 = undefined;
    if (toLowerAscii(token, &lower_buf)) |lower| {
        if (resolveIconVariant(allocator, lower)) |name| return name;

        var dash_buf: [256]u8 = undefined;
        if (replaceSpacesWith(lower, '-', &dash_buf)) |dashed| {
            if (resolveIconVariant(allocator, dashed)) |name| return name;
        }
        var underscore_buf: [256]u8 = undefined;
        if (replaceSpacesWith(lower, '_', &underscore_buf)) |underscored| {
            if (resolveIconVariant(allocator, underscored)) |name| return name;
        }
    }

    return null;
}

fn toLowerAscii(input: []const u8, buf: []u8) ?[]const u8 {
    if (input.len > buf.len) return null;
    for (input, 0..) |ch, idx| {
        buf[idx] = std.ascii.toLower(ch);
    }
    return buf[0..input.len];
}

fn windowIconAlias(token: []const u8) ?[]const u8 {
    if (std.ascii.eqlIgnoreCase(token, "zen")) return "zen-browser";
    if (std.ascii.eqlIgnoreCase(token, "discover")) return "org.kde.discover";
    if (std.ascii.eqlIgnoreCase(token, "archos")) return "archlinux-logo";
    return null;
}

fn resolveIconFileForCandidate(allocator: std.mem.Allocator, icon: []const u8, action: []const u8) ?[:0]u8 {
    const icon_trimmed = std.mem.trim(u8, icon, " \t\r\n\"'");
    if (icon_trimmed.len > 0 and looksLikeImageFile(icon_trimmed)) {
        const resolved = expandHomePath(allocator, icon_trimmed) catch return null;
        defer allocator.free(resolved);
        if (fileExistsAnyPath(resolved)) return allocator.dupeZ(u8, resolved) catch null;
    }
    const action_trimmed = std.mem.trim(u8, action, " \t\r\n\"'");
    if (action_trimmed.len > 0 and looksLikeImageFile(action_trimmed)) {
        const resolved = expandHomePath(allocator, action_trimmed) catch return null;
        defer allocator.free(resolved);
        if (fileExistsAnyPath(resolved)) return allocator.dupeZ(u8, resolved) catch null;
    }
    return null;
}

fn looksLikeImageFile(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".png") or
        std.mem.endsWith(u8, path, ".ico") or
        std.mem.endsWith(u8, path, ".svg") or
        std.mem.endsWith(u8, path, ".xpm") or
        std.mem.endsWith(u8, path, ".PNG") or
        std.mem.endsWith(u8, path, ".ICO") or
        std.mem.endsWith(u8, path, ".SVG") or
        std.mem.endsWith(u8, path, ".XPM");
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

test "windowIconAlias maps known desktop classes" {
    try std.testing.expectEqualStrings("zen-browser", windowIconAlias("zen") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqualStrings("org.kde.discover", windowIconAlias("discover") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqualStrings("archlinux-logo", windowIconAlias("archos") orelse return error.TestUnexpectedResult);
    try std.testing.expect(windowIconAlias("unknown") == null);
}

test "notificationAppNameFromSubtitle extracts app segment" {
    try std.testing.expectEqualStrings("notify-send", notificationAppNameFromSubtitle("notify-send | 2s ago") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqualStrings("zen-browser", notificationAppNameFromSubtitle("zen-browser") orelse return error.TestUnexpectedResult);
}
