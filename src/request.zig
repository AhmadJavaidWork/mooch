const std = @import("std");
const utils = @import("utils.zig");

const print = std.debug.print;

pub const Method = enum(u8) {
    get,
    post,
};

method: Method,
uri: []const u8,
version: []const u8,
headers: std.StringHashMap([]const u8),
body: ?[]const u8 = null,

const Self = @This();

pub fn init(allocator: std.mem.Allocator, reader: *std.Io.Reader) !Self {
    const start_line = try reader.takeDelimiter('\r') orelse return error.MalformedRequestStartLine;

    var lf = try reader.takeByte();
    if (lf != '\n') {
        return error.MalformedRequest;
    }

    var start_line_iter = std.mem.splitScalar(u8, start_line, ' ');

    var request = Self{
        .method = parseMethod(start_line_iter.next().?) orelse Method.get,
        .uri = try allocator.dupe(u8, start_line_iter.next().?),
        .version = try allocator.dupe(u8, start_line_iter.next().?),
        .headers = .init(allocator),
    };

    while (try reader.takeDelimiter('\r')) |line| {
        lf = try reader.takeByte();
        if (lf != '\n') {
            return error.MalformedRequest;
        }

        if (line.len == 0) {
            break;
        }

        const colon_idx = std.mem.indexOf(u8, line, ":") orelse return error.MalformedRequestHeader;
        const key = try allocator.dupe(u8, line[0..colon_idx]);
        const value_view = std.mem.trim(u8, line[colon_idx + 1 ..], " ");
        const value = try allocator.dupe(u8, value_view);

        try request.headers.put(key, value);
    }

    request.body = blk: switch (request.method) {
        .get => break :blk null,
        .post => {
            const content_length = try std.fmt.parseInt(usize, request.headers.get("Content-Length").?, 10);
            break :blk try allocator.dupe(u8, try reader.take(content_length));
        },
    };

    return request;
}

fn parseMethod(str: []const u8) ?Method {
    return utils.asciiStringToEnumIgnoreCase(Method, str);
}
