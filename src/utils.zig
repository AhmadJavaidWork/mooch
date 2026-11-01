const std = @import("std");

pub fn iStringToEnum(comptime T: type, s: []const u8) ?T {
    inline for (std.meta.fields(T)) |f| {
        if (std.ascii.eqlIgnoreCase(s, f.name)) {
            return @enumFromInt(f.value);
        }
    }

    return null;
}

pub fn capitalizeByHyphen(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    var convert_to_upper = true;
    var out: []u8 = try allocator.dupe(u8, s);

    for (out, 0..) |c, i| {
        var char = c;
        if (convert_to_upper) {
            char = std.ascii.toUpper(c);
            convert_to_upper = false;
        } else if (c == '-') {
            convert_to_upper = true;
        }
        out[i] = char;
    }
    return out;
}
