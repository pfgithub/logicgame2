const std = @import("std");

const Encoder = struct {
    rem: []u8,
    fn InputType(comptime T: type) type {
        return *const T;
    }
    pub const OutputType = void;
    fn int(xc: *Encoder, comptime T: type, intval: *const T) !void {
        std.mem.writeInt(u64, xc.rem[0..@sizeOf(T)], intval.*, .little);
        xc.rem = xc.rem[@sizeOf(T)..];
    }
    fn sizedSlice(xs: *Encoder, len: usize, txt: *const []const u8) !void {
        std.debug.assert(len == txt.len);
        @memcpy(xs.rem[0..txt.len], txt.*);
        xs.rem = xs.rem[txt.len..];
    }

    fn result(_: *Encoder) void {
        return {};
    }
};
const EncoderCounter = struct {
    count: usize,
    fn InputType(comptime T: type) type {
        return *const T;
    }
    pub const OutputType = usize;
    inline fn int(xc: *EncoderCounter, comptime T: type, _: *const T) !void {
        xc.count += @sizeOf(T);
    }
    inline fn sizedSlice(xc: *EncoderCounter, len: usize, txt: *const []const u8) !void {
        std.debug.assert(len == txt.len);
        xc.count += txt.len;
    }

    inline fn result(xc: *EncoderCounter) usize {
        return xc.count;
    }
};
const Decoder = struct {
    rem: []const u8,
    slen: usize,
    fn InputType(comptime T: type) type {
        return *T;
    }
    pub const OutputType = error{Decode}!usize;
    fn result(xc: *Decoder) usize {
        return xc.slen - xc.rem.len;
    }
};

fn XS(comptime Backing: type) type {
    return struct {
        backing: *Backing,
        const XSelf = @This();
        inline fn int(xc: XSelf, comptime T: type, intval: Backing.InputType(T)) !void {
            try xc.backing.int(T, intval);
        }
        inline fn sizedSlice(xs: XSelf, len: usize, txt: Backing.InputType([]const u8)) !void {
            try xs.backing.sizedSlice(len, txt);
        }
        fn slice(xc: XSelf, txt: Backing.InputType([]const u8)) !void {
            var len: usize = txt.len;
            try xc.int(u64, &len);
            try xc.sizedSlice(len, txt);
        }
        inline fn result(xc: XSelf) Backing.OutputType {
            return xc.backing.result();
        }
    };
}

const Src = struct {
    module: []const u8,
    file: []const u8,
    fn_name: []const u8,
    actual: []const u8,
    line: u64,
    column: u64,
};
fn xcodeSrc(
    comptime T: type,
    xc: XS(T),
    value: T.InputType(Src),
) T.OutputType {
    try xc.slice(&value.module);
    try xc.slice(&value.file);
    try xc.slice(&value.fn_name);
    try xc.slice(&value.actual);
    try xc.int(u64, &value.line);
    try xc.int(u64, &value.column);

    return xc.result();
}

pub fn main() !u8 {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len < 2) return error.NoArgs;

    var proc = std.process.Child.init(args[1..], gpa);
    var env_map = try std.process.getEnvMap(gpa);
    defer env_map.deinit();
    var rd: [16]u8 = undefined;
    var dprng = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp()));
    dprng.fill(&rd);
    const path = try std.fmt.allocPrint(gpa, ".zig-cache/znapshot_{x}", .{&rd});
    defer gpa.free(path);
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = "" });
    defer std.fs.cwd().deleteFile(path) catch {};
    try env_map.put("ZIG_ZNAPSHOT_FILE", path);
    proc.env_map = &env_map;
    const term = try proc.spawnAndWait();
    // const fcont = try std.fs.cwd().readFileAlloc(gpa, path, std.math.maxInt(usize));
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

            const srcval: Src = .{
                .module = src.module,
                .file = src.file,
                .fn_name = src.fn_name,
                .actual = actual,
                .line = src.line,
                .column = src.column,
            };
            var ec: EncoderCounter = .{ .count = 0 };
            const count = xcodeSrc(EncoderCounter, .{ .backing = &ec }, &srcval);
            const buf = try std.heap.smp_allocator.alloc(u8, count);
            defer std.heap.smp_allocator.free(buf);
            var ew: Encoder = .{ .rem = buf };
            xcodeSrc(Encoder, .{ .backing = &ew }, &srcval);

            try f.writeAll(buf);

            return; // success (s'posedly)
        }
    }
    const EMPTY_SNAPSHOT = "[empty_snapshot]";
    try std.testing.expectEqualStrings(expected orelse if (std.mem.eql(u8, actual, EMPTY_SNAPSHOT)) EMPTY_SNAPSHOT ++ "_" else EMPTY_SNAPSHOT, actual);
}
