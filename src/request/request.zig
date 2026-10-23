const std = @import("std");
const utils = @import("../utils.zig");
const RequestLine = @import("request_line.zig");

const print = std.debug.print;

request_line: RequestLine,
headers: std.StringHashMapUnmanaged([]const u8),
body: ?[]const u8 = null,

const Self = @This();

pub fn init(allocator: std.mem.Allocator, reader: *std.Io.Reader) !Self {
    const start_line = try reader.takeDelimiter('\r') orelse return error.MalformedStartLine;

    var lf = try reader.takeByte();
    if (lf != '\n') {
        return error.MalformedRequest;
    }

    const request_line = try RequestLine.init(allocator, start_line);

    var request = Self{
        .request_line = request_line,
        .headers = .empty,
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

        try request.headers.put(allocator, key, value);
    }

    request.body = blk: switch (request.request_line.method) {
        .get => break :blk null,
        .post => {
            const val = request.headers.get("Content-Length") orelse return error.NoContentLength;
            const content_length = std.fmt.parseInt(usize, val, 10) catch return error.InvalidContentLength;
            break :blk try allocator.dupe(u8, try reader.take(content_length));
        },
    };

    return request;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.request_line.deinit(allocator);
    if (self.body) |body| {
        allocator.free(body);
    }
}
