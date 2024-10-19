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

        back: u64,

        fn from(arg: []const u8) FlagError!Self {
            if (arg.len < 2) {
                return FlagError.NoExistingFlag;
            }

            if (arg[0] == '-' and arg[1] == '-') {
                inline for (s.fields, 0..) |field, i| {
                    const name = @field(opts, field.name).long;
                    if (std.mem.eql(u8, name, arg[2..])) {
                        return Self{ .back = i };
                    }
                }
            } else if (arg.len == 2) {
                inline for (s.fields, 0..) |field, i| {
                    const short = @field(opts, field.name).short;
                    if (short == arg[1]) {
                        return Self{ .back = i };
                    }
                }
            }

            return FlagError.NoExistingFlag;
        }

        fn setup(self: Self, args: *T, arg: []const u8) void {
            inline for (s.fields, 0..) |field, i| {
                if (i == self.back) {
                    const name = field.name;

                    @field(args, name) = arg;
                }
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
            }

            while (self.iter.next()) |arg| {
                if (std.mem.eql(u8, arg, "--")) {
                    skip_processing = true;
                    continue;
                }

                if (skip_processing) {} else {
                    if (current_flag) |flag| {
                        flag.setup(&args, arg);
                        current_flag = null;
                    } else {
                        current_flag = try Flag.from(arg);
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
