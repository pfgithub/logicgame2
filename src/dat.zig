const std = @import("std");
const util = @import("snapshot.zig");

const ivec2 = @Vector(2, i32);

test {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    var board: Board = .{ .gpa = gpa };
    defer board.deinit();

    try util.formattedSnapshot(gpa, "{f}", .{board}, @src(), null);
}

const ComponentID = enum(u32) { _ }; // TODO generational index, maybe in a memory pool
const Board = struct {
    gpa: std.mem.Allocator,
    components: std.ArrayListUnmanaged(Component) = .empty,

    placing_wire: ?struct {
        component: ComponentID,
        centerpt: ivec2,
    } = null,

    pub fn deinit(board: *Board) void {
        board.components.deinit(board.gpa);
    }

    pub fn format(board: *const Board, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.writeAll("components:\n");
        for (board.components.items) |component| {
            try w.print("- type: {s}\n", .{@tagName(component.tag)});
            try w.print("  pos: {d},{d},{d},{d}\n", .{ component.ul[0], component.ul[1], component.br[0], component.br[1] });
        }
    }

    pub fn mutComponent(board: *Board, component: ComponentID) ?*Component {
        return &board.components.items[component];
    }
    pub fn addComponent(board: *Board, data: Component) !ComponentID {
        if (board.components.items.len >= std.math.maxInt(u32)) return error.TooManyComponents;
        try board.components.append(board.gpa, data);
        return @enumFromInt(@as(u32, @intCast(board.components.items.len - 1)));
    }

    pub fn onMouseOp(board: *Board, mpos: ivec2, op: enum { down, drag, hover }) void {
        switch (op) {
            .down => {
                const component = board.addComponent(.{
                    .ul = mpos,
                    .br = mpos + ivec2{ 1, 1 },
                    .tag = .wire,
                }) catch {};
                board.placing_wire = .{
                    .component = component,
                    .centerpt = mpos,
                };
            },
            .drag, .up => {
                if (board.placing_wire) |pwire| {
                    const mut = board.mutComponent(pwire.component) orelse {
                        // component del-eted while placing
                        board.placing_wire = null;
                        return;
                    };
                    const centerpt = pwire.centerpt;
                    const target = mpos;
                    const diff = target - centerpt;
                    // now choose axis
                    const absdiff = @abs(diff);
                    var finalsize = diff;
                    if (absdiff[0] > absdiff[1]) {
                        finalsize = .{ diff[0], 0 }; // x axis
                    } else {
                        finalsize = .{ 0, diff[1] }; // y axis
                    }
                    const pos1 = centerpt;
                    const pos2 = centerpt + finalsize;
                    const ul = @min(pos1, pos2);
                    const br = @max(pos1, pos2) + ivec2{ 1, 1 };

                    mut.ul = ul;
                    mut.br = br;

                    if (op == .up) board.placing_wire = null;
                }
            },
            .hover => {},
        }
    }
};

const Component = struct {
    ul: ivec2,
    br: ivec2,
    tag: enum {
        wire,
        custom,

        transistor_npn,
        microled,
        buffer,
        wire_1,
        wire_2,
        wire_4,
        wire_8,
        wire_16,
        wire_32,
        wire_64,
    },
};

// what to do?
// for now let's do parts: []Parts
// each part has xywh and data
// each wire piece is a seperate part
// wires connect to any adjacent wire (flood fill)
//
// what to do about wire crosses? not sure

// basic components:
// 1x wire, 2x wire, 4x wire, 8x wire, 16x wire, 32x wire, 64x wire
// n-to-n splitters and mergers for these wires
//    - it would be nice if we didn't need this?
//    - also these are directional unlike wires so there's a difference between
//      a splitter and a merger which isn't ideal?
// bridges
//    - this might not be its own component
//    - alternatives:
//      - o1: two layers where wires automatically make vias
//      - o2: if you drag a wire across another wire it makes a long wire that doesn't connect
// 1-1 npn "transistor" (or not gate, we choose)
// all other components are user components

// instead of electricity it could be water that only goes down
// that would be really funny. but maybe less fun? although it could have crazy graphics up close
// and registers would need to output to the bottom and input from the top which sucks
// can't make a register as a component.
