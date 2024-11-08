const std = @import("std");

pub const File = union(enum) {
    std: void,
    file: []const u8,

    pub fn parse_opt(arg: []const u8) !File {
        if (std.mem.eql(u8, arg, "-")) {
            return File{ .std = @as(void, undefined) };
        } else {
            return File{ .file = arg };
        }
    }
};
