// much of this is borrowed from sphaerophoria https://www.youtube.com/watch?v=fh3i5_61LYk

const std = @import("std");
const Allocator = std.mem.Allocator;

const Attributes = std.builtin.Type.StructField.Attributes;

pub const Error = error{MissingFields};

/// Useful for deserializing structs
pub fn Nullable(comptime T: type) type {
    const ti = @typeInfo(T);
    const si = ti.@"struct";

    var field_names: [si.fields.len][]const u8 = undefined;
    var field_types: [si.fields.len]type = undefined;
    var field_attrs: [si.fields.len]Attributes = undefined;

    for (si.fields, &field_names, &field_types, &field_attrs) |si_field, *fname, *ftype, *fattr| {
        const FType = switch (@typeInfo(si_field.type)) {
            .optional => si_field.type,
            else => ?si_field.type,
        };

        const default: FType = comptime null;

        fname.* = si_field.name;
        ftype.* = FType;
        fattr.* = .{ .default_value_ptr = &default };
    }

    return @Struct(
        .auto,
        null,
        &field_names,
        &field_types,
        &field_attrs,
    );
}

test "Nullable" {
    const X = struct { string: []u8, number: usize, array: [1]usize };
    const NullableX = Nullable(X);
    try std.testing.expect(@alignOf(X) == @alignOf(NullableX));

    const x = NullableX{};
    try std.testing.expect(@TypeOf(x.number) == ?usize);
    try std.testing.expect(@TypeOf(x.string) == ?[]u8);
    try std.testing.expect(@TypeOf(x.array) == ?[1]usize);
}

pub fn deinitOwned(any: anytype, owner: Allocator) void {
    const T = @TypeOf(any);
    const ti = @typeInfo(T);
    switch (ti) {
        .bool, .comptime_int, .int, .null => {},
        .optional => if (any) |_| deinitOwned(any.?, owner),
        .@"struct" => inline for (ti.@"struct".fields) |f| deinitOwned(&@field(any, f.name), owner),
        .array => for (any) |i| deinitOwned(i, owner),
        .pointer => |p| switch (p.size) {
            .slice => {
                if (p.child == u8) return;
                switch (@typeInfo(p.child)) {
                    .bool, .comptime_int, .int, .null => {},
                    .pointer, .array, .@"struct" => for (any) |*i| deinitOwned(i, owner),
                    else => @compileError("Unsupported type '" ++ @typeName(p.child) ++ "'"),
                }

                owner.free(any);
            },
            .one => switch (@typeInfo(p.child)) {
                .bool, .comptime_int, .int, .null => {},
                .optional => deinitOwned(any.*, owner), // TODO: this is wrong
                .pointer => {}, // deinitOwned(any.*, owner), // TODO: this is wrong
                .array => for (any) |*i| deinitOwned(i, owner),
                .@"struct" => |s| inline for (s.fields) |f| deinitOwned(&@field(any.*, f.name), owner),
                else => @compileError("pointer to single '" ++ @typeName(p.child) ++ "' not supported"),
            },
            else => @compileError("Unsupported pointer type '" ++ @typeName(T) ++ "'"),
        },
        else => @compileError("Unsupported type '" ++ @typeName(T) ++ "'"),
    }
}

test "deinitOwned" {
    const X = struct {
        boolean: bool,
        op: ?bool,
        item: struct { a: usize },
        array: [1]usize,
        // ptr: *usize,
        nested: struct {
            boolean: ?bool = null,
            op: ?bool = null,
            item: ?struct { a: usize } = null,
            array: ?[1]usize = null,
            // ptr: *usize,
        },
    };

    const NullableX = Nullable(X);

    var x = try std.testing.allocator.create(NullableX);
    defer std.testing.allocator.destroy(x);
    // const nested = try std.testing.allocator.create(@TypeOf(x.nested));
    //
    // nested.*.?.array = .{1};
    x.boolean = true;
    x.op = true;
    x.item = .{ .a = 10 };
    // x.nested = nested;
    x.nested = .{ .array = .{1} };

    deinitOwned(x, std.testing.allocator);
}

pub fn transfer(t: anytype, n: *Nullable(@TypeOf(t.*))) void {
    const T = @TypeOf(t.*);
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (@typeInfo(field.type) != .optional and @field(n, field.name) == null) {
            return Error.MissingFields;
        }
    }

    inline for (@typeInfo(T).@"struct".fields) |field| {
        @field(t.*, field.name) = switch (@typeInfo(field.type)) {
            .optional => @field(n, field.name) orelse null,
            else => @field(n, field.name) orelse unreachable,
        };
    }
}
