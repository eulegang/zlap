const std = @import("std");

const Test = struct {
    alloc: std.mem.Allocator,
    cur: usize,
    args: []const []const u8,

    fn init(alloc: std.mem.Allocator, args: []const []const u8) !*Test {
        var self = try alloc.create(Test);
        errdefer alloc.destroy(self);

        self.cur = 0;
        var sargs = try alloc.alloc([]const u8, args.len);
        errdefer alloc.free(sargs);

        var err: usize = 0;
        errdefer {
            for (0..err) |i| {
                alloc.free(sargs[i]);
            }
        }

        for (args, 0..) |arg, i| {
            err = i;
            sargs[i] = try alloc.dupe(u8, arg);
        }

        self.args = sargs;
        self.alloc = alloc;

        return self;
    }

    fn next(self: *@This()) ?[]const u8 {
        if (self.cur < self.args.len) {
            const res = self.args[self.cur];

            self.cur += 1;

            return res;
        } else {
            return null;
        }
    }

    fn deinit(self: *@This()) void {
        for (self.args) |arg| {
            self.alloc.free(arg);
        }

        self.alloc.free(self.args);
    }
};

const Os = struct {
    iter: std.process.ArgIterator,

    fn init(alloc: std.mem.Allocator) !*Os {
        var os = try alloc.create(Os);
        os.iter = std.process.argsWithAllocator(alloc);
        return os;
    }

    fn next(self: *@This()) ?[]const u8 {
        return self.iter.next();
    }

    fn deinit(self: *@This()) void {
        self.iter.deinit();
    }
};

pub const ArgIter = union(enum) {
    const Self = @This();

    Os: *Os,
    Test: *Test,

    pub fn next(self: *@This()) ?[]const u8 {
        switch (self.*) {
            ArgIter.Os => |x| return x.next(),
            ArgIter.Test => |t| return t.next(),
        }
    }

    pub fn os(alloc: std.mem.Allocator) !Self {
        const x = try Os.init(alloc);

        return ArgIter{
            .Os = x,
        };
    }

    pub fn static(alloc: std.mem.Allocator, args: []const []const u8) !Self {
        const t = try Test.init(alloc, args);
        return ArgIter{
            .Test = t,
        };
    }

    pub fn deinit(self: @This(), alloc: std.mem.Allocator) void {
        switch (self) {
            .Test => |t| {
                t.deinit();
                alloc.destroy(t);
            },
            .Os => |o| {
                o.deinit();
                alloc.destroy(o);
            },
        }
    }
};
