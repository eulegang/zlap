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

    pub fn reader(self: @This()) !std.io.Reader {
        switch (self) {
            .std => {
                return std.io.getStdIn().reader();
            },

            .file => |f| {
                const file = try std.fs.cwd().openFile(f);
                return file.reader();
            },
        }
    }

    pub fn writer(self: @This()) !std.io.Writer {
        switch (self) {
            .std => {
                return std.io.getStdOut().writer();
            },

            .file => |f| {
                const file = try std.fs.cwd().openFile(f, .{
                    .mode = .write_only,
                });

                return file.writer();
            },
        }
    }
};
