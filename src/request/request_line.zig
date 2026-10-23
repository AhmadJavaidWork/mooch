const std = @import("std");
const utils = @import("../utils.zig");

pub const Method = enum(u8) {
    get,
    post,
};

method: Method,
path: []const u8,
version: []const u8,

const Self = @This();

pub fn init(allocator: std.mem.Allocator, line: []const u8) !Self {
    var line_iter = std.mem.splitScalar(u8, line, ' ');

    const method_str: []const u8 = line_iter.next() orelse return error.NoMethodInRequestLine;
    const method: Method = try parseMethod(method_str);

    const path_view: []const u8 = line_iter.next() orelse return error.NoURIInRequestLine;

    const version_view: []const u8 = line_iter.next() orelse return error.NoHttpVersionInRequestLine;

    var version_view_iter = std.mem.splitScalar(u8, version_view, '/');
    _ = version_view_iter.next() orelse return error.NoHTTPInVersionInRequestLine;
    const version_num_view: []const u8 = version_view_iter.next() orelse return error.NoHttpVersionNumInRequestLine;

    return .{
        .method = method,
        .path = try allocator.dupe(u8, path_view),
        .version = try allocator.dupe(u8, version_num_view),
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.path);
    allocator.free(self.version);
}

fn parseMethod(str: []const u8) !Method {
    return utils.iStringToEnum(Method, str) orelse error.MethodNotSupported;
}
