const std = @import("std");

const Self = @This();

headers: std.StringHashMapUnmanaged([]const u8) = .empty,

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    var it = self.headers.iterator();

    while (it.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.*);
    }
    self.headers.deinit(allocator);
}

pub fn get(self: *const Self, allocator: std.mem.Allocator, key: []const u8) !?[]const u8 {
    const l_key = try std.ascii.allocLowerString(allocator, key);
    defer allocator.free(l_key);
    return self.headers.get(l_key);
}

pub fn put(self: *Self, allocator: std.mem.Allocator, k: []const u8, v: []const u8) !void {
    const key = try std.ascii.allocLowerString(allocator, k);
    const val = try allocator.dupe(u8, v);
    try self.headers.put(allocator, key, val);
}

pub fn format(self: *const Self, writer: *std.Io.Writer) !void {
    var it = self.headers.iterator();
    try writer.print("Headers: {{", .{});
    while (it.next()) |entry| {
        try writer.print(" {s}: {s}", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
    try writer.print(" }}", .{});
}
