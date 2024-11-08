const std = @import("std");
const ArgIter = @import("./args.zig").ArgIter;
const Options = @import("./opts.zig").Options;

pub const FlagError = std.fmt.ParseIntError || std.fmt.ParseFloatError || std.process.GetEnvVarOwnedError || error{
    NoExistingFlag,
    MissingRequired,
    InvalidEnum,
    InvalidParse,
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

                    if (name) |n| {
                        if (std.mem.eql(u8, n, arg[2..])) {
                            return Self{
                                .back = i,
                                .is_flag = field.type == bool,
                                .is_optional = is_optional,
                            };
                        }
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

        fn setup(self: Self, args: *T, arg: []const u8) FlagError!void {
            inline for (s.fields, 0..) |field, i| {
                if (i == self.back) {
                    @field(args, field.name) = try parseArg(field.type, arg);
                }
            }
        }

        fn set_flag(self: Self, args: *T) FlagError!void {
            inline for (s.fields, 0..) |field, i| {
                if (i == self.back and field.type == bool) {
                    @field(args, field.name) = true;
                }
            }
        }
    };
}

fn parseArg(T: type, arg: []const u8) FlagError!T {
    switch (@typeInfo(T)) {
        .Bool => {
            unreachable; // handled by other code path
        },

        .Int => {
            return try std.fmt.parseInt(T, arg, 10);
        },

        .Float => {
            return try std.fmt.parseFloat(T, arg);
        },

        .Optional => |opt| {
            return try parseArg(opt.child, arg);
        },

        .Enum => |enumeration| {
            if (@hasDecl(T, "parse_opt")) {
                return try T.parse_opt(arg);
            } else {
                inline for (enumeration.fields) |field| {
                    if (std.ascii.eqlIgnoreCase(arg, field.name)) {
                        return @enumFromInt(field.value);
                    }
                }

                return FlagError.InvalidEnum;
            }
        },

        .Struct, .Union => {
            if (@hasDecl(T, "parse_opt")) {
                return try T.parse_opt(arg);
            } else {
                @compileLog("Parsing zlap does not support arguements with type " ++ @typeName(T), @typeInfo(T));
            }
        },

        .Pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) { // string!
                return arg;
            } else {
                @compileLog("Parsing zlap does not support arguements with type " ++ @typeName(T), @typeInfo(T));
            }
        },

        else => {
            @compileLog("Parsing zlap does not support arguements with type " ++ @typeName(T), @typeInfo(T));
        },
    }
}

fn AppDesc(T: type) type {
    return struct {
        name: []const u8,
        description: []const u8,
        options: Options(T),
    };
}

pub fn Builder(T: type, desc: AppDesc(T)) type {
    const s = switch (@typeInfo(T)) {
        .Struct => |s| s,
        else => @compileError("Flags may only be made out of structs"),
    };

    return struct {
        const Self = @This();
        const Flag = CreateFlags(T, desc.options);

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

        pub fn try_parse(self: *@This()) FlagError!T {
            var skip_processing = false;
            var current_flag: ?Flag = null;
            var args: T = undefined;

            const scratch = self.scratch.allocator();
            var required: u64 = 0;
            inline for (s.fields, 0..) |field, i| {
                comptime var req = true;

                if (comptime @field(desc.options, field.name).default) |def| {
                    @field(args, field.name) = def;
                    req = false;
                }

                if (comptime @field(desc.options, field.name).env) |evar| {
                    const env = try std.process.getEnvVarOwned(scratch, evar);
                    @field(args, field.name) = try parseArg(field.type, env);

                    req = false;
                }

                switch (@typeInfo(field.type)) {
                    .Optional => {
                        @field(args, field.name) = null;
                        req = false;
                    },
                    .Bool => {
                        @field(args, field.name) = false;
                        req = false;
                    },
                    else => {},
                }

                if (req) {
                    required |= 1 << i;
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
                        required &= ~std.math.shl(u64, 1, flag.back);
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

            if (required != 0) {
                return FlagError.MissingRequired;
            }

            return args;
        }

        pub fn help(_: *@This()) []const u8 {
            comptime var help_desc: []const u8 = desc.name ++ " - " ++ desc.description ++ "\n";

            inline for (@typeInfo(@TypeOf(desc.options)).Struct.fields) |field| {
                comptime var line: []const u8 = "\t";
                const opt = @field(desc.options, field.name);

                if (opt.short) |short| {
                    line = line ++ std.fmt.comptimePrint("-{c}", .{short});
                }

                if (opt.long) |long| {
                    if (opt.short != null) {
                        line = line ++ ", ";
                    }
                    line = line ++ std.fmt.comptimePrint("--{s}", .{long});
                }

                line = line ++ "\t";

                if (@field(desc.options, field.name).help) |help_text| {
                    line = line ++ help_text;
                }

                help_desc = help_desc ++ line ++ "\n";
            }

            return help_desc;
        }
    };
}
