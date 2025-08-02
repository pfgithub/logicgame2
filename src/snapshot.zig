const std = @import("std");

pub fn main() !u8 {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len < 2) return error.NoArgs;

    var proc = std.process.Child.init(args[1..], gpa);
    const term = try proc.spawnAndWait();
    if (term != .Exited or term.Exited != 0) return 1;

    return 0;
}

fn getSnapfile() ?[]const u8 {
    const static = struct {
        var _snapfile_written = false;
        var _snapfile: ?[]const u8 = null;
    };
    if (!static._snapfile_written) {
        const snapupd = std.process.getEnvMap(std.heap.smp_allocator) catch return null;
        static._snapfile = snapupd.get("ZIG_ZNAPSHOT_FILE");
        static._snapfile_written = true;
    }
    return static._snapfile;
}

pub fn formattedSnapshot(gpa: std.mem.Allocator, comptime fmt: []const u8, args: anytype, src: std.builtin.SourceLocation, expected: ?[]const u8) !void {
    var buf = std.ArrayList(u8).init(gpa);
    defer buf.deinit();
    try buf.writer().print(fmt, args);
    try snapshot(buf.items, src, expected);
}

pub fn snapshot(actual: []const u8, src: std.builtin.SourceLocation, expected: ?[]const u8) !void {
    if (getSnapfile()) |snapfile| {
        if (expected == null or !std.mem.eql(u8, expected.?, actual)) {
            // waiting on https://github.com/ziglang/zig/issues/14375
            // temporary workaround until then
            var f = try std.fs.cwd().openFile(snapfile, .{ .mode = .read_write });
            defer f.close();
            try f.seekFromEnd(0);

            var wbuf: [2048]u8 = undefined;
            var writer = f.writer(&wbuf);
            try writer.interface.writeInt(u64, src.module.len, .little);
            try writer.interface.writeInt(u64, src.file.len, .little);
            try writer.interface.writeInt(u64, src.fn_name.len, .little);
            try writer.interface.writeInt(u64, actual.len, .little);
            try writer.interface.writeInt(u64, src.line, .little);
            try writer.interface.writeInt(u64, src.column, .little);
            try writer.interface.writeAll(src.module);
            try writer.interface.writeAll(src.file);
            try writer.interface.writeAll(src.fn_name);
            try writer.interface.writeAll(actual);
            try writer.interface.flush();

            return; // success (s'posedly)
        }
    }
    const EMPTY_SNAPSHOT = "[empty_snapshot]";
    try std.testing.expectEqualStrings(expected orelse if (std.mem.eql(u8, actual, EMPTY_SNAPSHOT)) EMPTY_SNAPSHOT ++ "_" else EMPTY_SNAPSHOT, actual);
}
