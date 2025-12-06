# Nullable

Useful for deserializing structs. The way it works is by making a new struct type with the same alignment as your input type but everything is optional. This way, you can store the deserialized data temporarily and populate your struct deserialization is complete.

This can only be used with structs at the top level. Slices, arrays etc. are not allowed.

```zig
const std = @import("std");
const nullable = @import("nullable");
const Nullable = nullable.Nullable;

// etc.

fn deserialize(t: anytype, owner: std.mem.Allocator) !void {
    const T = @TypeOf(t.*)
    const NullableThing = Nullable(T);
    var nt = NullableThing{};
    errdefer nullable.deinitOwned(&nt, owner);

    // deserialization implementation here

    nullable.transfer(&nt, &t);
};

const MyThing = struct {
    a: []u8,
    b: usize,
    c: []u8,
};

var t: MyThing = undefined;
try deserialize(&t, allocator);
```
