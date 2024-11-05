const std = @import("std");
const ArgIter = @import("./args.zig").ArgIter;
const Options = @import("./opts.zig").Options;

const FlagError = error{
    NoExistingFlag,
};

fn CreateFlags(T: type, opts: Options(T)) type {
    const t = @typeInfo(T);
    const s = switch (t) {
        .Struct => |s| s,
        else => @compileError("Flags may only be made out of structs"),
    };

    return struct {
        const Self = @This();

        is_optional: bool,
        is_flag: bool,
        back: u64,

        fn from(arg: []const u8) FlagError!Self {
            if (arg.len < 2) {
                return FlagError.NoExistingFlag;
            }

            if (arg[0] == '-' and arg[1] == '-') {
                inline for (s.fields, 0..) |field, i| {
                    const name = @field(opts, field.name).long;
                    const is_optional = switch (@typeInfo(field.type)) {
                        .Optional => true,
                        else => false,
                    };

                    if (std.mem.eql(u8, name, arg[2..])) {
                        return Self{
                            .back = i,
                            .is_flag = field.type == bool,
                            .is_optional = is_optional,
                        };
                    }
                }
            } else if (arg.len == 2) {
                inline for (s.fields, 0..) |field, i| {
                    const short = @field(opts, field.name).short;
                    const is_optional = switch (@typeInfo(field.type)) {
                        .Optional => true,
                        else => false,
                    };

                    if (short == arg[1]) {
                        return Self{
                            .back = i,
                            .is_flag = field.type == bool,
                            .is_optional = is_optional,
                        };
                    }
                }
            }

            return FlagError.NoExistingFlag;
        }

        fn setup(self: Self, args: *T, arg: []const u8) !void {
            inline for (s.fields, 0..) |field, i| {
                if (i == self.back) {
                    try self.set(args, field, arg);
                }
            }
        }

        fn set_flag(self: Self, args: *T) !void {
            inline for (s.fields, 0..) |field, i| {
                if (i == self.back and field.type == bool) {
                    @field(args, field.name) = true;
                }
            }
        }

        fn set(_: Self, args: *T, field: std.builtin.Type.StructField, arg: []const u8) !void {
            switch (@typeInfo(field.type)) {
                .Bool => {
                    unreachable; // handled by other code path
                },

                .Int => {
                    @field(args, field.name) = try std.fmt.parseInt(field.type, arg, 10);
                },

                .Float => {
                    @field(args, field.name) = try std.fmt.parseFloat(field.type, arg);
                },

                .Pointer => |ptr| {
                    if (ptr.size == .Slice and ptr.child == u8) { // string!
                        @field(args, field.name) = arg;
                    } else {}
                },

                .Optional => |opt| {
                    switch (@typeInfo(opt.child)) {
                        .Bool => {
                            unreachable; // handled by other code path
                        },

                        .Int => {
                            @field(args, field.name) = try std.fmt.parseInt(opt.child, arg, 10);
                        },

                        .Float => {
                            @field(args, field.name) = try std.fmt.parseFloat(opt.child, arg);
                        },

                        .Pointer => |ptr| {
                            if (ptr.size == .Slice and ptr.child == u8) { // string!
                                @field(args, field.name) = arg;
                            } else {}
                        },

                        else => {
                            @compileLog("Parsing zlap does not support arguements with type", @typeInfo(field.type));
                        },
                    }
                },

                else => {
                    @compileLog("Parsing zlap does not support arguements with type", @typeInfo(field.type));
                },
            }
        }
    };
}

pub fn Builder(T: type, opts: Options(T)) type {
    const s = switch (@typeInfo(T)) {
        .Struct => |s| s,
        else => @compileError("Flags may only be made out of structs"),
    };

    return struct {
        const Self = @This();
        const Flag = CreateFlags(T, opts);

        alloc: std.mem.Allocator,
        iter: ArgIter,
        scratch: std.heap.ArenaAllocator,

        pub fn init(alloc: std.mem.Allocator) !Self {
            const iter = try ArgIter.os(alloc);

            const scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            return Self{
                .alloc = alloc,
                .iter = iter,
                .scratch = scratch,
            };
        }

        pub fn static(alloc: std.mem.Allocator, args: []const []const u8) !Self {
            const iter = try ArgIter.static(alloc, args);

            const scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);

            return Self{
                .alloc = alloc,
                .iter = iter,
                .scratch = scratch,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.iter.deinit(self.alloc);
        }

        pub fn try_parse(self: *@This()) !T {
            var skip_processing = false;
            var current_flag: ?Flag = null;
            var args: T = undefined;

            const scratch = self.scratch.allocator();
            inline for (s.fields) |field| {
                if (comptime @field(opts, field.name).default) |def| {
                    @field(args, field.name) = def;
                }

                if (comptime @field(opts, field.name).env) |evar| {
                    @field(args, field.name) = try std.process.getEnvVarOwned(scratch, evar);
                }

                switch (@typeInfo(field.type)) {
                    .Optional => {
                        @field(args, field.name) = null;
                    },
                    else => {},
                }
            }

            while (self.iter.next()) |arg| {
                if (std.mem.eql(u8, arg, "--")) {
                    skip_processing = true;
                    continue;
                }

                if (!skip_processing) {
                    if (current_flag) |flag| {
                        try flag.setup(&args, arg);
                        current_flag = null;
                    } else {
                        const flag = try Flag.from(arg);

                        if (flag.is_flag) {
                            try flag.set_flag(&args);
                        } else {
                            current_flag = flag;
                        }
                    }
                }
            }

            return args;
        }
    };
}

test "basic builder" {
    const Args = struct {
        input: []const u8,
        output: []const u8,
    };

    const B = Builder(Args, .{
        .input = .{
            .short = 'i',
            .long = "input",
        },
        .output = .{
            .short = 'o',
            .long = "output",
        },
    });

    var builder = try B.static(std.testing.allocator, &.{ "-o", "out.txt", "-i", "input.txt" });
    defer builder.deinit();

    const args = try builder.try_parse();

    try std.testing.expectEqualStrings(args.output, "out.txt");
    try std.testing.expectEqualStrings(args.input, "input.txt");
}

test "default option in builder" {
    const Args = struct {
        config: []const u8,
    };

    const B = Builder(Args, .{
        .config = .{
            .short = 'c',
            .long = "config",
            .default = "/etc/some.conf",
        },
    });

    {
        var builder = try B.static(std.testing.allocator, &.{});
        defer builder.deinit();

        const args = try builder.try_parse();

        try std.testing.expectEqualStrings(args.config, "/etc/some.conf");
    }

    {
        var builder = try B.static(std.testing.allocator, &.{ "-c", "/usr/etc/some.conf" });
        defer builder.deinit();

        const args = try builder.try_parse();

        try std.testing.expectEqualStrings(args.config, "/usr/etc/some.conf");
    }
}

test "env option in builder" {
    const Args = struct {
        user: []const u8,
    };

    const B = Builder(Args, .{
        .user = .{
            .short = 'u',
            .long = "user",
            .env = "USER",
        },
    });

    {
        var builder = try B.static(std.testing.allocator, &.{});
        defer builder.deinit();

        const args = try builder.try_parse();

        const x = try std.process.getEnvVarOwned(std.testing.allocator, "USER");
        defer std.testing.allocator.free(x);

        try std.testing.expectEqualStrings(args.user, x);
    }

    {
        var builder = try B.static(std.testing.allocator, &.{ "--user", "mel" });
        defer builder.deinit();

        const args = try builder.try_parse();

        try std.testing.expectEqualStrings(args.user, "mel");
    }
}

test "int option parsed" {
    const Args = struct {
        level: u32,
    };

    const B = Builder(Args, .{
        .level = .{
            .short = 'l',
            .long = "level",
        },
    });

    var builder = try B.static(std.testing.allocator, &.{ "-l", "42" });
    defer builder.deinit();

    const args = try builder.try_parse();

    try std.testing.expectEqual(args.level, 42);
}

test "float option parsed" {
    const Args = struct {
        level: f32,
    };

    const B = Builder(Args, .{
        .level = .{
            .short = 'l',
            .long = "level",
        },
    });

    var builder = try B.static(std.testing.allocator, &.{ "-l", "3.5" });
    defer builder.deinit();

    const args = try builder.try_parse();

    try std.testing.expectApproxEqRel(args.level, 3.5, 0.0003);
}

test "boolean option parsed" {
    const Args = struct {
        verbose: bool,
    };

    const B = Builder(Args, .{
        .verbose = .{
            .short = 'v',
            .long = "verbose",
        },
    });

    {
        var builder = try B.static(std.testing.allocator, &.{"-v"});
        defer builder.deinit();

        const args = try builder.try_parse();

        try std.testing.expect(args.verbose);
    }
    {
        var builder = try B.static(std.testing.allocator, &.{});
        defer builder.deinit();

        const args = try builder.try_parse();

        try std.testing.expect(!args.verbose);
    }
}

test "optional option parsed" {
    const Args = struct {
        level: ?u32,
    };

    const B = Builder(Args, .{
        .level = .{
            .short = 'l',
            .long = "level",
        },
    });

    {
        var builder = try B.static(std.testing.allocator, &.{});
        defer builder.deinit();

        const args = try builder.try_parse();

        try std.testing.expectEqual(null, args.level);
    }

    {
        var builder = try B.static(std.testing.allocator, &.{ "-l", "42" });
        defer builder.deinit();

        const args = try builder.try_parse();

        try std.testing.expectEqual(42, args.level);
    }
}
