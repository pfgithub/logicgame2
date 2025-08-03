const std = @import("std");
const snapshot_zig = @import("snapshot.zig");
pub const snapshot = snapshot_zig.snapshot;
pub const formattedSnapshot = snapshot_zig.formattedSnapshot;

const Cyclic = std.AutoArrayHashMap(*const anyopaque, usize);
const PrintCtx = struct {
    cyclic: *Cyclic,
    w: *std.Io.Writer,
};
inline fn prettyPrintAnytype(obj: anytype, ctx: *const PrintCtx) error{WriteFailed}!void {
    switch (@typeInfo(@TypeOf(obj))) {
        .comptime_int, .int, .float => {
            try ctx.w.print("{d}", .{obj});
        },
        else => {
            try ctx.w.print("[todo {s}]", .{@tagName(@typeInfo(@TypeOf(obj)))});
        },
    }
}
fn FmtAny(comptime V: type) type {
    return struct {
        gpa: std.mem.Allocator,
        v: V,
        pub inline fn format(obj: @This(), w: *std.Io.Writer) error{WriteFailed}!void {
            var cyclic = Cyclic.init(obj.gpa);
            defer cyclic.deinit();
            try prettyPrintAnytype(obj.v, &.{ .cyclic = &cyclic, .w = w });
        }
    };
}
fn fmtAny(gpa: std.mem.Allocator, v: anytype) FmtAny(@TypeOf(v)) {
    return .{ .v = v, .gpa = gpa };
}

test "fmtAny" {
    const gpa = std.testing.allocator;
    try formattedSnapshot(gpa, "{f}", .{fmtAny(gpa, 25)}, @src(),
        \\25
    );
}
