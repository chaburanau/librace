//! Per-session IRSDK variable catalog (owned name index + metadata).

const std = @import("std");
const protocol = @import("protocol.zig");
const testing = @import("testing.zig");

pub const VarEntry = struct {
    name: []u8,
    description: []u8,
    unit: []u8,
    var_type: protocol.VarType,
    count: i32,
    offset: i32,
};

pub const Catalog = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(VarEntry),
    by_name: std.StringHashMap(usize),
    /// Maps IRSDK catalog index (0 .. num_vars-1) to `entries` index, or null when skipped.
    by_irsdk_index: std.ArrayListUnmanaged(?usize),
    source_session_info_update: i32 = -1,
    source_num_vars: i32 = 0,
    /// Bumped on every successful rebuild; used to invalidate cached variable handles.
    version: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) Catalog {
        return .{
            .allocator = allocator,
            .entries = .empty,
            .by_name = std.StringHashMap(usize).init(allocator),
            .by_irsdk_index = .empty,
        };
    }

    pub fn deinit(self: *Catalog) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.description);
            self.allocator.free(entry.unit);
        }
        self.entries.deinit(self.allocator);
        self.by_irsdk_index.deinit(self.allocator);
        self.by_name.deinit();
        self.* = .{
            .allocator = self.allocator,
            .entries = .empty,
            .by_name = std.StringHashMap(usize).init(self.allocator),
            .by_irsdk_index = .empty,
        };
    }

    pub fn needsRebuild(self: *const Catalog, hdr: *const protocol.Header) bool {
        return self.source_session_info_update != hdr.session_info_update or
            self.source_num_vars != hdr.num_vars;
    }

    pub fn rebuild(self: *Catalog, mem: []const u8, hdr: *const protocol.Header) !void {
        self.clearEntries();

        const num_vars: usize = @intCast(hdr.num_vars);
        try self.by_irsdk_index.resize(self.allocator, num_vars);
        @memset(self.by_irsdk_index.items, null);

        var i: usize = 0;
        while (i < num_vars) : (i += 1) {
            const var_header = protocol.readVarHeader(mem, hdr, i) orelse continue;
            const name = var_header.nameSlice();
            if (name.len == 0) continue;
            const var_type = var_header.varType() orelse continue;

            const entry = VarEntry{
                .name = try self.allocator.dupe(u8, name),
                .description = try self.allocator.dupe(u8, std.mem.sliceTo(&var_header.desc, 0)),
                .unit = try self.allocator.dupe(u8, std.mem.sliceTo(&var_header.unit, 0)),
                .var_type = var_type,
                .count = var_header.count,
                .offset = var_header.offset,
            };
            errdefer {
                self.allocator.free(entry.name);
                self.allocator.free(entry.description);
                self.allocator.free(entry.unit);
            }

            const entry_index = self.entries.items.len;
            try self.entries.append(self.allocator, entry);
            try self.by_name.put(self.entries.items[entry_index].name, entry_index);
            self.by_irsdk_index.items[i] = entry_index;
        }

        self.source_session_info_update = hdr.session_info_update;
        self.source_num_vars = hdr.num_vars;
        self.version +%= 1;
    }

    pub fn len(self: *const Catalog) usize {
        return self.entries.items.len;
    }

    pub fn get(self: *const Catalog, name: []const u8) ?*const VarEntry {
        const idx = self.by_name.get(name) orelse return null;
        return &self.entries.items[idx];
    }

    /// Index into `entries` for `name`, or null when unknown. Pairs with `entryAt`.
    pub fn getIndex(self: *const Catalog, name: []const u8) ?usize {
        return self.by_name.get(name);
    }

    /// Entry at an `entries` index (as returned by `getIndex`).
    pub fn entryAt(self: *const Catalog, index: usize) ?*const VarEntry {
        if (index >= self.entries.items.len) return null;
        return &self.entries.items[index];
    }

    pub fn entryAtIrSdkIndex(self: *const Catalog, index: usize) ?*const VarEntry {
        if (index >= self.by_irsdk_index.items.len) return null;
        const entry_index = self.by_irsdk_index.items[index] orelse return null;
        return &self.entries.items[entry_index];
    }

    pub const NameIterator = struct {
        catalog: *const Catalog,
        index: usize = 0,

        pub fn next(self: *NameIterator) ?[]const u8 {
            if (self.index >= self.catalog.entries.items.len) return null;
            const name = self.catalog.entries.items[self.index].name;
            self.index += 1;
            return name;
        }
    };

    pub fn nameIterator(self: *const Catalog) NameIterator {
        return .{ .catalog = self };
    }

    fn clearEntries(self: *Catalog) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.description);
            self.allocator.free(entry.unit);
        }
        self.entries.clearRetainingCapacity();
        self.by_name.clearRetainingCapacity();
        self.by_irsdk_index.clearRetainingCapacity();
    }
};

test "catalog rebuild indexes variables by name and irsdk index" {
    var mem: [512]u8 = undefined;
    @memset(&mem, 0);

    const hdr: *protocol.Header = @ptrCast(@alignCast(&mem));
    hdr.* = testing.initHeader(.{
        .session_info_update = 1,
        .num_vars = 2,
    });

    const vh0: *protocol.VarHeader = @ptrCast(@alignCast(&mem[@sizeOf(protocol.Header)]));
    vh0.* = testing.initVarHeader(.{ .type = @intFromEnum(protocol.VarType.int), .name = "Gear" });

    const vh1: *protocol.VarHeader = @ptrCast(@alignCast(&mem[@sizeOf(protocol.Header) + protocol.var_header_stride]));
    vh1.* = testing.initVarHeader(.{
        .type = @intFromEnum(protocol.VarType.float),
        .offset = 4,
        .name = "Speed",
    });

    var catalog = Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    try catalog.rebuild(&mem, hdr);
    try std.testing.expectEqual(@as(usize, 2), catalog.len());
    try std.testing.expect(catalog.get("Gear") != null);
    try std.testing.expect(catalog.get("Speed") != null);
    try std.testing.expectEqualStrings("Gear", catalog.entryAtIrSdkIndex(0).?.name);
    try std.testing.expectEqualStrings("Speed", catalog.entryAtIrSdkIndex(1).?.name);
}

test "catalog rebuild picks up new variables after session change" {
    var mem: [512]u8 = undefined;
    @memset(&mem, 0);

    const hdr: *protocol.Header = @ptrCast(@alignCast(&mem));
    hdr.* = testing.initHeader(.{
        .session_info_update = 1,
        .num_vars = 1,
    });

    const vh0: *protocol.VarHeader = @ptrCast(@alignCast(&mem[@sizeOf(protocol.Header)]));
    vh0.* = testing.initVarHeader(.{ .type = @intFromEnum(protocol.VarType.int), .name = "Gear" });

    var catalog = Catalog.init(std.testing.allocator);
    defer catalog.deinit();

    try catalog.rebuild(&mem, hdr);
    try std.testing.expectEqual(@as(usize, 1), catalog.len());
    try std.testing.expect(catalog.get("RPM") == null);

    hdr.session_info_update = 2;
    hdr.num_vars = 2;

    const vh1: *protocol.VarHeader = @ptrCast(@alignCast(&mem[@sizeOf(protocol.Header) + protocol.var_header_stride]));
    vh1.* = testing.initVarHeader(.{
        .type = @intFromEnum(protocol.VarType.float),
        .offset = 4,
        .name = "RPM",
    });

    try std.testing.expect(catalog.needsRebuild(hdr));
    try catalog.rebuild(&mem, hdr);
    try std.testing.expectEqual(@as(usize, 2), catalog.len());
    try std.testing.expect(catalog.get("RPM") != null);
}

test "catalog name iterator visits all entries" {
    var mem: [512]u8 = undefined;
    @memset(&mem, 0);

    const hdr: *protocol.Header = @ptrCast(@alignCast(&mem));
    hdr.* = testing.initHeader(.{
        .session_info_update = 1,
        .num_vars = 2,
    });

    const vh0: *protocol.VarHeader = @ptrCast(@alignCast(&mem[@sizeOf(protocol.Header)]));
    vh0.* = testing.initVarHeader(.{ .type = @intFromEnum(protocol.VarType.int), .name = "A" });

    const vh1: *protocol.VarHeader = @ptrCast(@alignCast(&mem[@sizeOf(protocol.Header) + protocol.var_header_stride]));
    vh1.* = testing.initVarHeader(.{
        .type = @intFromEnum(protocol.VarType.int),
        .offset = 4,
        .name = "B",
    });

    var catalog = Catalog.init(std.testing.allocator);
    defer catalog.deinit();
    try catalog.rebuild(&mem, hdr);

    var it = catalog.nameIterator();
    try std.testing.expectEqualStrings("A", it.next().?);
    try std.testing.expectEqualStrings("B", it.next().?);
    try std.testing.expect(it.next() == null);
}
