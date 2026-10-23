const std = @import("std");
const utils = @import("utils.zig");

const print = std.debug.print;

pub const Method = enum(u8) {
    get,
    post,
};

pub const RequestLine = struct {
    method: Method,
    uri: []const u8,
    version: []const u8,
};

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

    const request_line = try parseRequestLine(allocator, start_line);

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

fn parseRequestLine(allocator: std.mem.Allocator, line: []const u8) !RequestLine {
    var line_iter = std.mem.splitScalar(u8, line, ' ');

    const method_str: []const u8 = line_iter.next() orelse return error.NoMethodInRequestLine;
    const method_enum: Method = parseMethod(method_str) orelse return error.MethodNotSupported;

    const uri_view: []const u8 = line_iter.next() orelse return error.NoURIInRequestLine;

    const version_view: []const u8 = line_iter.next() orelse return error.NoHttpVersionInRequestLine;

    var version_view_iter = std.mem.splitScalar(u8, version_view, '/');
    _ = version_view_iter.next() orelse return error.NoHTTPInVersionInRequestLine;
    const version_num_view: []const u8 = version_view_iter.next() orelse return error.NoHttpVersionNumInRequestLine;

    return RequestLine{
        .method = method_enum,
        .uri = try allocator.dupe(u8, uri_view),
        .version = try allocator.dupe(u8, version_num_view),
    };
}

fn parseMethod(str: []const u8) ?Method {
    return utils.iStringToEnum(Method, str);
}
