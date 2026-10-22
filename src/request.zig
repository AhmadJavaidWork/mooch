const std = @import("std");
const print = std.debug.print;

pub const Method = enum(u8) {
    get,
    post,
};

method: Method,
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

    const request = Self{
        .method = std.meta.stringToEnum(Method, start_line_iter.next().?) orelse Method.get,
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

        const space_idx = std.mem.indexOf(u8, line, " ") orelse return error.MalformedRequestHeader;
        const line_iter = std.mem.splitScalar(u8, line, ':');
        const key = try allocator.dupe(u8, line[0 .. space_idx + 1].?);
        const value = try allocator.dupe(u8, line_iter.next().?);

        request.headers.put(key, value);
    }

    return request;
}
