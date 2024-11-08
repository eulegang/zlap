const std = @import("std");

const NULL_OPT: ?[]const u8 = null;

fn Option(comptime name: []const u8) type {
    if (name.len == 0) {
        @compileError("invalid field name " ++ name ++ " used to create option");
    }

    return @Type(.{
        .Struct = .{
            .layout = .auto,
            .is_tuple = false,
            .decls = &[_]std.builtin.Type.Declaration{},
            .fields = &[_]std.builtin.Type.StructField{
                .{
                    .type = u8,
                    .name = "short",
                    .default_value = &name[0],
                    .is_comptime = false,
                    .alignment = 8,
                },
                .{
                    .type = []const u8,
                    .name = "long",
                    .default_value = @ptrCast(&name),
                    .is_comptime = false,
                    .alignment = 8,
                },
                .{
                    .type = ?[]const u8,
                    .name = "env",
                    .default_value = &NULL_OPT,
                    .is_comptime = false,
                    .alignment = 8,
                },
                .{
                    .type = ?[]const u8,
                    .name = "default",
                    .default_value = &NULL_OPT,
                    .is_comptime = false,
                    .alignment = 8,
                },
                .{
                    .type = ?[]const u8,
                    .name = "help",
                    .is_comptime = false,
                    .default_value = &NULL_OPT,
                    .alignment = 8,
                },
            },
        },
    });
}

pub fn Options(T: type) type {
    const t = @typeInfo(T);
    switch (t) {
        .Struct => |s| {
            var fields: [s.fields.len]std.builtin.Type.StructField = undefined;

            for (s.fields, 0..) |field, i| {
                fields[i] = field;
                fields[i].type = Option(field.name);

                //field.name
            }

            return @Type(.{
                .Struct = .{
                    .layout = .auto,
                    .is_tuple = false,
                    .fields = &fields,
                    .decls = &[_]std.builtin.Type.Declaration{},
                },
            });
        },

        else => @compileError("Options must be a struct"),
    }
}
