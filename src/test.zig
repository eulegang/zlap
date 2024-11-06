const std = @import("std");
const zlap = @import("zlap");

test "basic builder" {
    const Args = struct {
        input: []const u8,
        output: []const u8,
    };

    const B = zlap.Builder(Args, .{
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

    const B = zlap.Builder(Args, .{
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

    const B = zlap.Builder(Args, .{
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

    const B = zlap.Builder(Args, .{
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

    const B = zlap.Builder(Args, .{
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

    const B = zlap.Builder(Args, .{
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

    const B = zlap.Builder(Args, .{
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

test "required option fails" {
    const Args = struct {
        level: u32,
    };

    const B = zlap.Builder(Args, .{
        .level = .{
            .short = 'l',
            .long = "level",
        },
    });

    var builder = try B.static(std.testing.allocator, &.{});
    defer builder.deinit();

    try std.testing.expectError(zlap.FlagError.MissingRequired, builder.try_parse());
}

test "enum option" {
    const Status = enum {
        On,
        Off,
    };

    const Args = struct {
        status: Status,
    };

    const B = zlap.Builder(Args, .{
        .status = .{
            .short = 's',
            .long = "status",
        },
    });

    var builder = try B.static(std.testing.allocator, &.{ "-s", "on" });
    defer builder.deinit();

    const args = try builder.try_parse();

    try std.testing.expectEqual(.On, args.status);
}

test "custom parse option" {
    const Duration = struct {
        secs: u32,

        pub fn parse_opt(_: []const u8) zlap.FlagError!@This() {
            return @This(){
                .secs = 30,
            };
        }
    };

    const Args = struct {
        duration: Duration,
    };

    const B = zlap.Builder(Args, .{ .duration = .{} });

    var builder = try B.static(std.testing.allocator, &.{ "-d", "30m" });
    defer builder.deinit();

    const args = try builder.try_parse();

    try std.testing.expectEqual(Duration{ .secs = 30 }, args.duration);
}
