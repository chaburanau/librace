//! IRSDK session-info (YAML) access by path and section.
//!
//! Full session info is a large YAML document in shared memory. This module provides
//! lightweight path/section lookup without a full YAML parser.
//!
//! Path format: `Section/Key` for top-level keys, or `Section/Nested/.../Key` for nested
//! maps. Array/list items are matched by key name (first occurrence in the section).

const std = @import("std");

/// Fetch a scalar value using a slash-separated path (`WeekendInfo/TrackName`).
///
/// The first segment is always a top-level section name. Remaining segments walk nested
/// YAML maps; a single remaining segment uses first-match key lookup within the section.
pub fn getByPath(yaml: []const u8, path: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, path, '/')) |slash| {
        const section = path[0..slash];
        const rest = path[slash + 1 ..];
        const section_yaml = extractSection(yaml, section) orelse return null;
        if (std.mem.indexOfScalar(u8, rest, '/')) |_| {
            return extractNestedKey(section_yaml, rest);
        }
        return extractKey(section_yaml, rest);
    }
    return extractKey(yaml, path);
}

/// Extract a top-level YAML section body (e.g. `WeekendInfo`, `DriverInfo`).
pub fn extractSection(yaml: []const u8, section: []const u8) ?[]const u8 {
    var needle_buf: [128]u8 = undefined;
    if (section.len + 3 > needle_buf.len) return null;

    const needle_nl = std.fmt.bufPrint(&needle_buf, "\n{s}:\n", .{section}) catch return null;
    const start = blk: {
        if (std.mem.indexOf(u8, yaml, needle_nl)) |idx| break :blk idx + 1;
        const prefix = std.fmt.bufPrint(&needle_buf, "{s}:\n", .{section}) catch return null;
        if (std.mem.startsWith(u8, yaml, prefix)) break :blk 0;
        return null;
    };

    const body_start = start + section.len + 1; // skip "Section:"
    if (body_start >= yaml.len) return null;

    const rest = yaml[body_start..];
    const end = std.mem.indexOf(u8, rest, "\n\n") orelse yaml.len - body_start;
    return std.mem.trim(u8, rest[0..end], "\n");
}

/// Within a YAML fragment, locate the list under `list_key:` and return the raw text of the
/// first item whose `match_key:` equals `match_value`.
///
/// List items are blocks introduced by a `-` marker (iRacing uses `Section/List` of maps,
/// e.g. `DriverInfo/Drivers`). An item extends until the next sibling marker or a dedent out
/// of the list. The returned slice can be passed to `extractKey` to read a field from it.
pub fn listItemMatching(
    yaml: []const u8,
    list_key: []const u8,
    match_key: []const u8,
    match_value: []const u8,
) ?[]const u8 {
    const list = findListBody(yaml, list_key) orelse return null;
    const body = list.body;

    var item_start: ?usize = null;
    var line_start: usize = 0;
    while (line_start <= body.len) {
        const nl = std.mem.indexOfScalarPos(u8, body, line_start, '\n') orelse body.len;
        const line = body[line_start..nl];
        const indent = leadingSpaces(line);
        const is_marker = indent == list.marker_indent and indent < line.len and line[indent] == '-';
        if (is_marker) {
            if (item_start) |s| {
                const item = std.mem.trimEnd(u8, body[s..line_start], "\n");
                if (itemMatches(item, match_key, match_value)) return item;
            }
            item_start = line_start;
        }
        if (nl == body.len) break;
        line_start = nl + 1;
    }
    if (item_start) |s| {
        const item = std.mem.trimEnd(u8, body[s..], "\n");
        if (itemMatches(item, match_key, match_value)) return item;
    }
    return null;
}

fn itemMatches(item: []const u8, match_key: []const u8, match_value: []const u8) bool {
    const value = extractKey(item, match_key) orelse return false;
    return std.mem.eql(u8, value, match_value);
}

fn leadingSpaces(line: []const u8) usize {
    var n: usize = 0;
    while (n < line.len and line[n] == ' ') : (n += 1) {}
    return n;
}

const ListBody = struct {
    body: []const u8,
    marker_indent: usize,
};

/// Return the body of a YAML block list under `key:`, spanning all `-` items.
///
/// iRacing places list markers at the same indentation as the parent key's siblings, so the
/// list is terminated by a line at or above the key's indent that is *not* a `-` marker.
fn findListBody(yaml: []const u8, key: []const u8) ?ListBody {
    var needle_buf: [128]u8 = undefined;
    if (key.len + 2 > needle_buf.len) return null;
    const needle = std.fmt.bufPrint(&needle_buf, "{s}:", .{key}) catch return null;

    var search_start: usize = 0;
    while (search_start < yaml.len) {
        const rel = std.mem.indexOfPos(u8, yaml, search_start, needle) orelse return null;
        const line_start = blk: {
            var i = rel;
            while (i > 0 and yaml[i - 1] != '\n') : (i -= 1) {}
            break :blk i;
        };
        // Only spaces may precede the key on its line (otherwise it's a substring match).
        if (!isAllSpaces(yaml[line_start..rel])) {
            search_start = rel + needle.len;
            continue;
        }
        const parent_indent = rel - line_start;

        const key_line_end = std.mem.indexOfScalarPos(u8, yaml, rel, '\n') orelse return null;
        const body_start = key_line_end + 1;
        if (body_start >= yaml.len) return null;

        var marker_indent: ?usize = null;
        var body_end = yaml.len;
        var ls = body_start;
        while (ls < yaml.len) {
            const nl = std.mem.indexOfScalarPos(u8, yaml, ls, '\n') orelse yaml.len;
            const line = yaml[ls..nl];
            const indent = leadingSpaces(line);
            const is_blank = indent == line.len;
            if (!is_blank) {
                const is_marker = indent < line.len and line[indent] == '-';
                if (!is_marker and indent <= parent_indent) {
                    body_end = ls;
                    break;
                }
                if (is_marker and marker_indent == null) marker_indent = indent;
            }
            if (nl == yaml.len) break;
            ls = nl + 1;
        }

        const mi = marker_indent orelse return null;
        return .{
            .body = std.mem.trimEnd(u8, yaml[body_start..body_end], "\n"),
            .marker_indent = mi,
        };
    }
    return null;
}

fn isAllSpaces(s: []const u8) bool {
    for (s) |c| {
        if (c != ' ') return false;
    }
    return true;
}

/// Scan a YAML fragment for `key: value` (first match).
pub fn extractKey(yaml: []const u8, key: []const u8) ?[]const u8 {
    var needle_buf: [128]u8 = undefined;
    if (key.len + 2 > needle_buf.len) return null;
    const needle = std.fmt.bufPrint(&needle_buf, "{s}:", .{key}) catch return null;

    var search_start: usize = 0;
    while (search_start < yaml.len) {
        const rel = std.mem.indexOfPos(u8, yaml, search_start, needle) orelse return null;
        if (rel > 0 and yaml[rel - 1] != '\n' and yaml[rel - 1] != ' ' and yaml[rel - 1] != '-') {
            search_start = rel + needle.len;
            continue;
        }

        const after_key = rel + needle.len;
        if (after_key >= yaml.len) return null;

        var value_start = after_key;
        while (value_start < yaml.len and yaml[value_start] == ' ') : (value_start += 1) {}

        const rest = yaml[value_start..];
        const line_end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
        const raw = std.mem.trim(u8, rest[0..line_end], " \t\r");
        if (raw.len == 0) return null;

        return parseScalar(raw);
    }

    return null;
}

fn parseScalar(raw: []const u8) ?[]const u8 {
    if (raw.len == 0) return null;
    if (raw[0] == '"') {
        if (raw.len >= 2 and raw[raw.len - 1] == '"') return raw[1 .. raw.len - 1];
        return raw;
    }
    return raw;
}

/// Walk nested map keys (`Parent/Child/Leaf`) within a YAML fragment.
fn extractNestedKey(yaml: []const u8, key_path: []const u8) ?[]const u8 {
    var rest = key_path;
    var fragment = yaml;
    while (true) {
        const slash = std.mem.indexOfScalar(u8, rest, '/');
        if (slash) |s| {
            const segment = rest[0..s];
            fragment = extractKeyBlock(fragment, segment) orelse return null;
            rest = rest[s + 1 ..];
        } else {
            return extractKey(fragment, rest);
        }
    }
}

/// Return the indented block body under `key:` within a YAML fragment.
fn extractKeyBlock(yaml: []const u8, key: []const u8) ?[]const u8 {
    var needle_buf: [128]u8 = undefined;
    if (key.len + 2 > needle_buf.len) return null;
    const needle = std.fmt.bufPrint(&needle_buf, "{s}:", .{key}) catch return null;

    var search_start: usize = 0;
    while (search_start < yaml.len) {
        const rel = std.mem.indexOfPos(u8, yaml, search_start, needle) orelse return null;
        if (rel > 0 and yaml[rel - 1] != '\n' and yaml[rel - 1] != ' ' and yaml[rel - 1] != '-') {
            search_start = rel + needle.len;
            continue;
        }

        const line_start = blk: {
            var i = rel;
            while (i > 0 and yaml[i - 1] != '\n') : (i -= 1) {}
            break :blk i;
        };
        const parent_indent = rel - line_start;

        const after_key = rel + needle.len;
        if (after_key >= yaml.len) return null;

        var value_start = after_key;
        while (value_start < yaml.len and yaml[value_start] == ' ') : (value_start += 1) {}

        if (value_start < yaml.len and yaml[value_start] != '\n') {
            const rest = yaml[value_start..];
            const line_end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
            const raw = std.mem.trim(u8, rest[0..line_end], " \t\r");
            if (raw.len == 0) return null;
            return parseScalar(raw);
        }

        var i = value_start;
        while (i < yaml.len and (yaml[i] == '\n' or yaml[i] == '\r')) i += 1;
        if (i >= yaml.len) return null;

        const block_start = i;
        while (i < yaml.len) {
            if (yaml[i] == '\n') {
                i += 1;
                if (i >= yaml.len) break;
                if (yaml[i] == '\n' or yaml[i] == '\r') break;
                const line_end = std.mem.indexOfScalar(u8, yaml[i..], '\n') orelse yaml.len - i;
                const line = yaml[i .. i + line_end];
                if (line.len == 0) continue;
                if (line[0] != ' ' and line[0] != '\t' and line[0] != '-') break;
                var indent: usize = 0;
                while (indent < line.len and line[indent] == ' ') : (indent += 1) {}
                if (indent <= parent_indent) break;
            } else {
                i += 1;
            }
        }
        return std.mem.trim(u8, yaml[block_start..i], "\n");
    }

    return null;
}

pub const SectionIterator = struct {
    yaml: []const u8,
    pos: usize = 0,

    pub fn next(self: *SectionIterator) ?[]const u8 {
        if (std.mem.startsWith(u8, self.yaml[self.pos..], "---")) {
            if (std.mem.indexOfScalar(u8, self.yaml[self.pos..], '\n')) |nl| {
                self.pos += nl + 1;
            }
        }

        while (self.pos < self.yaml.len) {
            while (self.pos < self.yaml.len and (self.yaml[self.pos] == '\n' or self.yaml[self.pos] == '\r')) {
                self.pos += 1;
            }
            if (self.pos >= self.yaml.len) return null;

            const line_end = std.mem.indexOfScalar(u8, self.yaml[self.pos..], '\n') orelse self.yaml.len - self.pos;
            const line = self.yaml[self.pos .. self.pos + line_end];
            self.pos += line_end + 1;

            if (line.len == 0 or line[0] == ' ' or line[0] == '-') continue;
            if (std.mem.indexOfScalar(u8, line, ':')) |colon| {
                const name = std.mem.trim(u8, line[0..colon], " \t");
                if (name.len > 0) return name;
            }
        }
        return null;
    }
};

pub fn sectionIterator(yaml: []const u8) SectionIterator {
    return .{ .yaml = yaml };
}

test "get by path" {
    const yaml =
        \\---
        \\WeekendInfo:
        \\ TrackName: lemans
        \\ TrackDisplayName: Circuit de la Sarthe
        \\
        \\DriverInfo:
        \\ Drivers:
        \\ - CarScreenName: Ferrari 499P
        \\   CarPath: ferrari499p
    ;

    try std.testing.expectEqualStrings("lemans", getByPath(yaml, "WeekendInfo/TrackName").?);
    try std.testing.expectEqualStrings("Circuit de la Sarthe", getByPath(yaml, "WeekendInfo/TrackDisplayName").?);
    try std.testing.expectEqualStrings("Ferrari 499P", getByPath(yaml, "DriverInfo/CarScreenName").?);
}

test "get by nested path" {
    const yaml =
        \\---
        \\WeekendInfo:
        \\ Track:
        \\  City: Le Mans
        \\  Country: France
    ;

    try std.testing.expectEqualStrings("Le Mans", getByPath(yaml, "WeekendInfo/Track/City").?);
    try std.testing.expectEqualStrings("France", getByPath(yaml, "WeekendInfo/Track/Country").?);
}

test "extract key handles quoted values with spaces" {
    const yaml =
        \\---
        \\WeekendInfo:
        \\ TrackDisplayName: "Circuit de la Sarthe"
    ;

    try std.testing.expectEqualStrings(
        "Circuit de la Sarthe",
        getByPath(yaml, "WeekendInfo/TrackDisplayName").?,
    );
}

test "list item matching selects the correct driver by CarIdx" {
    const yaml =
        \\---
        \\DriverInfo:
        \\ DriverCarIdx: 1
        \\ Drivers:
        \\ - CarIdx: 0
        \\   UserName: Alice
        \\   CarScreenName: Ferrari 499P
        \\ - CarIdx: 1
        \\   UserName: Bob
        \\   CarScreenName: Porsche 963
        \\ - CarIdx: 2
        \\   UserName: Carol
        \\   CarScreenName: BMW M Hybrid V8
    ;

    const section = extractSection(yaml, "DriverInfo").?;
    const item = listItemMatching(section, "Drivers", "CarIdx", "1").?;
    try std.testing.expectEqualStrings("Bob", extractKey(item, "UserName").?);
    try std.testing.expectEqualStrings("Porsche 963", extractKey(item, "CarScreenName").?);

    const first = listItemMatching(section, "Drivers", "CarIdx", "0").?;
    try std.testing.expectEqualStrings("Ferrari 499P", extractKey(first, "CarScreenName").?);

    const last = listItemMatching(section, "Drivers", "CarIdx", "2").?;
    try std.testing.expectEqualStrings("Carol", extractKey(last, "UserName").?);

    try std.testing.expect(listItemMatching(section, "Drivers", "CarIdx", "9") == null);
}

test "extract section returns null for missing section" {
    const yaml =
        \\---
        \\WeekendInfo:
        \\ TrackName: lemans
    ;

    try std.testing.expect(extractSection(yaml, "DriverInfo") == null);
}

test "section iterator yields top-level sections" {
    const yaml =
        \\---
        \\WeekendInfo:
        \\ TrackName: lemans
        \\
        \\DriverInfo:
        \\ DriverCarIdx: 0
    ;

    var it = sectionIterator(yaml);
    try std.testing.expectEqualStrings("WeekendInfo", it.next().?);
    try std.testing.expectEqualStrings("DriverInfo", it.next().?);
    try std.testing.expect(it.next() == null);
}
