//! One-copy, lazy queries over the small YAML subset emitted by IRSDK.

const std = @import("std");

pub const ParseError = std.mem.Allocator.Error;
pub const ScalarError = error{ TypeMismatch, InvalidScalar, UnsupportedEscape, BufferTooSmall };
pub const QueryError = ScalarError || error{
    InvalidIndentation,
    MalformedMapping,
    UnsupportedConstruct,
    ExpectedScalar,
};

pub const ScalarKind = enum { string, int, float, bool, null };

pub const Scalar = struct {
    raw: []const u8,
    style: Style,

    pub const Style = enum { plain, single_quoted, double_quoted };

    pub fn kind(self: Scalar) ScalarKind {
        if (self.style != .plain) return .string;
        if (isNullText(self.raw)) return .null;
        if (isBoolText(self.raw)) return .bool;
        return numberKind(self.raw) orelse .string;
    }

    pub fn asInt(self: Scalar) ScalarError!i64 {
        if (self.kind() != .int) return error.TypeMismatch;
        return std.fmt.parseInt(i64, self.raw, 10) catch error.InvalidScalar;
    }

    pub fn asFloat(self: Scalar) ScalarError!f64 {
        if (self.kind() != .float) return error.TypeMismatch;
        return std.fmt.parseFloat(f64, self.raw) catch error.InvalidScalar;
    }

    pub fn asBool(self: Scalar) ScalarError!bool {
        if (self.style != .plain) return error.TypeMismatch;
        if (std.ascii.eqlIgnoreCase(self.raw, "true")) return true;
        if (std.ascii.eqlIgnoreCase(self.raw, "false")) return false;
        return error.TypeMismatch;
    }

    pub fn isNull(self: Scalar) bool {
        return self.style == .plain and isNullText(self.raw);
    }

    /// Returns snapshot-owned UTF-8 when possible. Escaped or CP1252 text is
    /// decoded into `buffer`.
    pub fn string(self: Scalar, buffer: []u8) ScalarError![]const u8 {
        if (self.kind() != .string) return error.TypeMismatch;
        if (!needsDecode(self) and std.unicode.utf8ValidateSlice(self.raw)) return self.raw;
        var sink = Sink{ .buffer = buffer };
        try decode(self, &sink);
        return buffer[0..sink.len];
    }
};

pub const PathSegment = union(enum) {
    key: []const u8,
    index: usize,
    select: Selection,
};
pub const Selection = struct { key: []const u8, value: MatchValue };
pub const MatchValue = union(enum) { string: []const u8, int: i64, bool: bool, null };

pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    yaml: []u8,
    version: i32,

    pub fn deinit(self: *Snapshot) void {
        self.allocator.free(self.yaml);
        self.* = undefined;
    }

    /// Performs no allocation. Returned scalar bytes borrow this snapshot.
    pub fn query(self: *const Snapshot, path: []const PathSegment) QueryError!?Scalar {
        var node = try rootNode(self.yaml);
        for (path) |segment| {
            node = (switch (segment) {
                .key => |key| try findKey(node, key),
                .index => |index| try findIndex(node, index),
                .select => |selection| try findSelection(node, selection),
            }) orelse return null;
        }
        return switch (node.kind) {
            .scalar => node.scalar,
            else => error.ExpectedScalar,
        };
    }
};

pub fn parse(allocator: std.mem.Allocator, yaml: []const u8, version: i32) ParseError!Snapshot {
    return .{ .allocator = allocator, .yaml = try allocator.dupe(u8, yaml), .version = version };
}

const NodeKind = enum { map, list, scalar };
const Node = struct {
    kind: NodeKind,
    body: []const u8 = "",
    indent: usize = 0,
    first: ?[]const u8 = null,
    scalar: Scalar = .{ .raw = "", .style = .plain },
};
const Line = struct { indent: usize, text: []const u8, rest: []const u8, source: []const u8 };

fn rootNode(yaml: []const u8) QueryError!Node {
    var body = yaml;
    var line = nextLine(&body) orelse return error.ExpectedScalar;
    if (line.indent == bad_indent) return error.InvalidIndentation;
    if (std.mem.eql(u8, line.text, "---"))
        line = nextLine(&body) orelse return error.ExpectedScalar;
    if (line.indent != 0 or isList(line.text)) return error.InvalidIndentation;
    return .{ .kind = .map, .body = line.source, .indent = 0 };
}

fn findKey(node: Node, wanted: []const u8) QueryError!?Node {
    if (node.kind != .map) return error.TypeMismatch;
    if (node.first) |first| {
        const parts = try mapping(first);
        if (std.mem.eql(u8, parts.key, wanted)) return try scalarNode(parts.value);
    }

    var body = node.body;
    while (nextLine(&body)) |line| {
        if (line.indent == bad_indent) return error.InvalidIndentation;
        if (line.indent < node.indent or isEnd(line.text)) break;
        if (line.indent != node.indent or isList(line.text)) continue;
        const parts = try mapping(line.text);
        if (!std.mem.eql(u8, parts.key, wanted)) continue;
        if (parts.value.len != 0) return try scalarNode(parts.value);

        var following = line.rest;
        const child = nextLine(&following) orelse return nullNode();
        if (child.indent == bad_indent) return error.InvalidIndentation;
        if (child.indent < line.indent) return nullNode();
        if (child.indent == line.indent) {
            // IRSDK places list markers at their key's indentation.
            if (isList(child.text))
                return .{ .kind = .list, .body = line.rest, .indent = child.indent };
            return nullNode();
        }
        return .{
            .kind = if (isList(child.text)) .list else .map,
            .body = line.rest,
            .indent = child.indent,
        };
    }
    return null;
}

fn findIndex(node: Node, wanted: usize) QueryError!?Node {
    if (node.kind != .list) return error.TypeMismatch;
    var body = node.body;
    var index: usize = 0;
    while (nextLine(&body)) |line| {
        if (line.indent == bad_indent) return error.InvalidIndentation;
        if (line.indent < node.indent or (line.indent == node.indent and !isList(line.text))) break;
        if (line.indent != node.indent) continue;
        if (index == wanted) return try listItem(line);
        index += 1;
    }
    return null;
}

fn findSelection(node: Node, selection: Selection) QueryError!?Node {
    if (node.kind != .list) return error.TypeMismatch;
    var body = node.body;
    while (nextLine(&body)) |line| {
        if (line.indent == bad_indent) return error.InvalidIndentation;
        if (line.indent < node.indent or (line.indent == node.indent and !isList(line.text))) break;
        if (line.indent != node.indent) continue;
        const item = try listItem(line);
        const field = (try findKey(item, selection.key)) orelse continue;
        if (field.kind == .scalar and try matches(field.scalar, selection.value)) return item;
    }
    return null;
}

fn listItem(line: Line) QueryError!Node {
    const text = std.mem.trim(u8, line.text[1..], " ");
    if (text.len == 0) {
        var body = line.rest;
        const child = nextLine(&body) orelse return nullNode();
        if (child.indent <= line.indent) return nullNode();
        return .{
            .kind = if (isList(child.text)) .list else .map,
            .body = line.rest,
            .indent = child.indent,
        };
    }
    if (mappingColon(text) != null) return .{
        .kind = .map,
        .body = line.rest,
        .indent = line.indent + 2,
        .first = text,
    };
    return scalarNode(text);
}

const Parts = struct { key: []const u8, value: []const u8 };

fn mapping(text: []const u8) QueryError!Parts {
    const colon = mappingColon(text) orelse return error.MalformedMapping;
    const key = std.mem.trim(u8, text[0..colon], " ");
    if (key.len == 0) return error.MalformedMapping;
    return .{ .key = key, .value = std.mem.trim(u8, text[colon + 1 ..], " ") };
}

fn mappingColon(text: []const u8) ?usize {
    var quote: ?u8 = null;
    var escaped = false;
    for (text, 0..) |byte, index| {
        if (escaped) {
            escaped = false;
        } else if (quote == '"' and byte == '\\') {
            escaped = true;
        } else if (byte == '"' or byte == '\'') {
            if (quote == byte) quote = null else if (quote == null) quote = byte;
        } else if (quote == null and byte == ':' and
            (index + 1 == text.len or text[index + 1] == ' ')) return index;
    }
    return null;
}

fn scalarNode(input: []const u8) QueryError!Node {
    const raw = std.mem.trim(u8, input, " ");
    if (raw.len == 0) return nullNode();
    if (raw[0] == '"' or raw[0] == '\'') {
        if (raw.len < 2 or raw[raw.len - 1] != raw[0]) return error.InvalidScalar;
        return .{ .kind = .scalar, .scalar = .{
            .raw = raw[1 .. raw.len - 1],
            .style = if (raw[0] == '"') .double_quoted else .single_quoted,
        } };
    }
    if (std.mem.indexOfScalar(u8, "[{&*!|>@", raw[0]) != null)
        return error.UnsupportedConstruct;
    return .{ .kind = .scalar, .scalar = .{ .raw = raw, .style = .plain } };
}

fn nullNode() Node {
    return .{ .kind = .scalar };
}

const bad_indent = std.math.maxInt(usize);

fn nextLine(body: *[]const u8) ?Line {
    while (body.*.len != 0) {
        const source = body.*;
        const end = std.mem.indexOfScalar(u8, body.*, '\n') orelse body.*.len;
        var raw = body.*[0..end];
        const rest = if (end < body.*.len) body.*[end + 1 ..] else body.*[end..];
        body.* = rest;
        if (raw.len != 0 and raw[raw.len - 1] == '\r') raw = raw[0 .. raw.len - 1];
        var indent: usize = 0;
        while (indent < raw.len and raw[indent] == ' ') : (indent += 1) {}
        if (indent == raw.len) continue;
        if (raw[indent] == '\t') indent = bad_indent;
        return .{ .indent = indent, .text = if (indent == bad_indent) raw else raw[indent..], .rest = rest, .source = source };
    }
    return null;
}

fn isList(text: []const u8) bool {
    return text.len != 0 and text[0] == '-' and (text.len == 1 or text[1] == ' ');
}
fn isEnd(text: []const u8) bool {
    return std.mem.eql(u8, text, "...") or std.mem.eql(u8, text, "---");
}
fn isNullText(raw: []const u8) bool {
    return raw.len == 0 or std.mem.eql(u8, raw, "~") or std.ascii.eqlIgnoreCase(raw, "null");
}
fn isBoolText(raw: []const u8) bool {
    return std.ascii.eqlIgnoreCase(raw, "true") or std.ascii.eqlIgnoreCase(raw, "false");
}

fn numberKind(raw: []const u8) ?ScalarKind {
    var float = false;
    for (raw) |byte| switch (byte) {
        '0'...'9', '+', '-' => {},
        '.', 'e', 'E' => float = true,
        else => return null,
    };
    if (raw.len == 0) return null;
    if (float) {
        _ = std.fmt.parseFloat(f64, raw) catch return null;
        return .float;
    }
    _ = std.fmt.parseInt(i64, raw, 10) catch return null;
    return .int;
}

fn matches(scalar: Scalar, expected: MatchValue) ScalarError!bool {
    return switch (expected) {
        .int => |value| (scalar.asInt() catch return false) == value,
        .bool => |value| (scalar.asBool() catch return false) == value,
        .null => scalar.isNull(),
        .string => |value| blk: {
            if (scalar.kind() != .string) break :blk false;
            var sink = Sink{ .expected = value };
            try decode(scalar, &sink);
            break :blk sink.matches and sink.len == value.len;
        },
    };
}

fn needsDecode(scalar: Scalar) bool {
    return switch (scalar.style) {
        .plain => false,
        .single_quoted => std.mem.indexOf(u8, scalar.raw, "''") != null,
        .double_quoted => std.mem.indexOfScalar(u8, scalar.raw, '\\') != null,
    };
}

const Sink = struct {
    buffer: ?[]u8 = null,
    expected: ?[]const u8 = null,
    len: usize = 0,
    matches: bool = true,

    fn put(self: *Sink, byte: u8) ScalarError!void {
        if (self.buffer) |buffer| {
            if (self.len == buffer.len) return error.BufferTooSmall;
            buffer[self.len] = byte;
        }
        if (self.expected) |expected|
            if (self.len >= expected.len or expected[self.len] != byte) {
                self.matches = false;
            };
        self.len += 1;
    }

    fn codepoint(self: *Sink, cp: u21) ScalarError!void {
        var bytes: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &bytes) catch return error.InvalidScalar;
        for (bytes[0..len]) |byte| try self.put(byte);
    }
};

fn decode(scalar: Scalar, sink: *Sink) ScalarError!void {
    const utf8 = std.unicode.utf8ValidateSlice(scalar.raw);
    var i: usize = 0;
    while (i < scalar.raw.len) : (i += 1) {
        const byte = scalar.raw[i];
        if (scalar.style == .single_quoted and byte == '\'') {
            if (i + 1 >= scalar.raw.len or scalar.raw[i + 1] != '\'') return error.InvalidScalar;
            i += 1;
            try sink.put('\'');
        } else if (scalar.style == .double_quoted and byte == '\\') {
            if (i + 1 >= scalar.raw.len) return error.InvalidScalar;
            i += 1;
            try sink.put(switch (scalar.raw[i]) {
                '"' => '"',
                '\\' => '\\',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                else => return error.UnsupportedEscape,
            });
        } else if (utf8 or byte < 0x80) {
            try sink.put(byte);
        } else {
            try sink.codepoint(cp1252(byte));
        }
    }
}

fn cp1252(byte: u8) u21 {
    if (byte < 0x80 or byte >= 0xa0) return byte;
    const special = [_]u21{
        0x20ac, 0xfffd, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021,
        0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0xfffd, 0x017d, 0xfffd,
        0xfffd, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
        0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0xfffd, 0x017e, 0x0178,
    };
    return special[byte - 0x80];
}

test "nested keys scalar decoding and ownership" {
    var source = "Info:\n Track: Spa\n Int: -7\n Float: 1.25e3\n Yes: TRUE\n Empty:\n".*;
    var snapshot = try parse(std.testing.allocator, &source, 9);
    defer snapshot.deinit();
    @memset(&source, 'x');
    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("Spa", try (try snapshot.query(&.{ .{ .key = "Info" }, .{ .key = "Track" } })).?.string(&buffer));
    try std.testing.expectEqual(@as(i64, -7), try (try snapshot.query(&.{ .{ .key = "Info" }, .{ .key = "Int" } })).?.asInt());
    try std.testing.expectEqual(@as(f64, 1250), try (try snapshot.query(&.{ .{ .key = "Info" }, .{ .key = "Float" } })).?.asFloat());
    try std.testing.expect(try (try snapshot.query(&.{ .{ .key = "Info" }, .{ .key = "Yes" } })).?.asBool());
    try std.testing.expect((try snapshot.query(&.{ .{ .key = "Info" }, .{ .key = "Empty" } })).?.isNull());
    try std.testing.expectEqual(@as(i32, 9), snapshot.version);
}

test "same-indent lists support index and typed selection" {
    const yaml =
        \\DriverInfo:
        \\ DriverCarIdx: 1
        \\ Drivers:
        \\ - CarIdx: 0
        \\   UserName: Alice
        \\ - CarIdx: 1
        \\   UserName: Bob
    ;
    var snapshot = try parse(std.testing.allocator, yaml, 1);
    defer snapshot.deinit();
    var buffer: [16]u8 = undefined;
    const indexed = (try snapshot.query(&.{ .{ .key = "DriverInfo" }, .{ .key = "Drivers" }, .{ .index = 0 }, .{ .key = "UserName" } })).?;
    try std.testing.expectEqualStrings("Alice", try indexed.string(&buffer));
    const selected = (try snapshot.query(&.{
        .{ .key = "DriverInfo" },
        .{ .key = "Drivers" },
        .{ .select = .{ .key = "CarIdx", .value = .{ .int = 1 } } },
        .{ .key = "UserName" },
    })).?;
    try std.testing.expectEqualStrings("Bob", try selected.string(&buffer));
}

test "quoted strings unescape and CP1252 falls back to UTF-8" {
    const yaml = "---\r\nText:\r\n Double: \"line\\n\\\"ok\\\"\"\r\n Single: 'driver''s'\r\n Legacy: Montr\xe9al \x96 GP\r\n...\r\n";
    var snapshot = try parse(std.testing.allocator, yaml, 1);
    defer snapshot.deinit();
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("line\n\"ok\"", try (try snapshot.query(&.{ .{ .key = "Text" }, .{ .key = "Double" } })).?.string(&buffer));
    try std.testing.expectEqualStrings("driver's", try (try snapshot.query(&.{ .{ .key = "Text" }, .{ .key = "Single" } })).?.string(&buffer));
    try std.testing.expectEqualStrings("Montréal – GP", try (try snapshot.query(&.{ .{ .key = "Text" }, .{ .key = "Legacy" } })).?.string(&buffer));
}

test "missing paths and wrong container types" {
    var snapshot = try parse(std.testing.allocator, "Root:\n Value: one\n", 1);
    defer snapshot.deinit();
    try std.testing.expect((try snapshot.query(&.{.{ .key = "Missing" }})) == null);
    try std.testing.expectError(error.TypeMismatch, snapshot.query(&.{ .{ .key = "Root" }, .{ .key = "Value" }, .{ .key = "Bad" } }));
}
