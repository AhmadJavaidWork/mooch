const std = @import("std");

pub fn iStringToEnum(comptime T: type, s: []const u8) ?T {
    inline for (std.meta.fields(T)) |f| {
        if (std.ascii.eqlIgnoreCase(s, f.name)) {
            return @enumFromInt(f.value);
        }
    }

    return null;
}
