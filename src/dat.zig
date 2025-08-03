const std = @import("std");
const util = @import("snapshot.zig");
const GenerationalPool = @import("generational_pool.zig").GenerationalPool;

const ivec2 = @Vector(2, i32);

test "dat" {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    var board: Board = .init(gpa);
    defer board.deinit();

    try util.formattedSnapshot(gpa, "{f}", .{board}, @src(),
        \\components:
        \\
    );
    board.onMouseOp(.{ 5, 7 }, .down);
    try util.formattedSnapshot(gpa, "{f}", .{board}, @src(),
        \\components:
        \\- type: wire
        \\  pos: 5,7,1,1
        \\
    );
    board.onMouseOp(.{ 6, 7 }, .drag);
    try util.formattedSnapshot(gpa, "{f}", .{board}, @src(),
        \\components:
        \\- type: wire
        \\  pos: 5,7,2,1
        \\
    );
    board.onMouseOp(.{ 6, 8 }, .drag);
    try util.formattedSnapshot(gpa, "{f}", .{board}, @src(),
        \\components:
        \\- type: wire
        \\  pos: 5,7,1,2
        \\
    );
    board.onMouseOp(.{ 5, 8 }, .drag);
    try util.formattedSnapshot(gpa, "{f}", .{board}, @src(),
        \\components:
        \\- type: wire
        \\  pos: 5,7,1,2
        \\
    );
    board.onMouseOp(.{ 5, 3 }, .drag);
    try util.formattedSnapshot(gpa, "{f}", .{board}, @src(),
        \\components:
        \\- type: wire
        \\  pos: 5,3,1,5
        \\
    );
    board.onMouseOp(.{ 3, 7 }, .drag);
    try util.formattedSnapshot(gpa, "{f}", .{board}, @src(),
        \\components:
        \\- type: wire
        \\  pos: 3,7,3,1
        \\
    );
}

const ComponentID = enum(u32) { _ }; // TODO generational index, maybe in a memory pool
const Board = struct {
    // TODO interactions:
    // - drag existing component (not wire)
    // - delete existing component (right-click?)
    // - box-select (shift left-click?)
    // - add to selection (left-click?)
    // - pan and zoom camera
    // - place new component

    gpa: std.mem.Allocator,
    components: std.ArrayListUnmanaged(Component) = .empty,

    wire_pads: GenerationalPool(WirePad),
    wire_connections: GenerationalPool(WireConnection),

    placing_wire: ?struct {
        component: ComponentID,
        centerpt: ivec2,
    } = null,

    pub fn init(gpa: std.mem.Allocator) Board {
        return .{
            .gpa = gpa,
            .wire_pads = .init(gpa),
            .wire_connections = .init(gpa),
        };
    }
    pub fn deinit(board: *Board) void {
        board.components.deinit(board.gpa);
        board.wire_pads.deinit();
        board.wire_connections.deinit();
    }

    pub fn format(board: *const Board, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.writeAll("components:\n");
        for (board.components.items) |component| {
            try w.print("- type: {s}\n", .{@tagName(component.tag)});
            try w.print("  pos: {d},{d},{d},{d}\n", .{ component.ul[0], component.ul[1], component.size[0], component.size[1] });
        }
    }

    pub fn mutComponent(board: *Board, component: ComponentID) ?*Component {
        return &board.components.items[@intFromEnum(component)];
    }
    pub fn addComponent(board: *Board, data: Component) !ComponentID {
        if (board.components.items.len >= std.math.maxInt(u32)) return error.TooManyComponents;
        try board.components.append(board.gpa, data);
        return @enumFromInt(@as(u32, @intCast(board.components.items.len - 1)));
    }

    pub fn onMouseOp(board: *Board, mpos: ivec2, op: enum { down, drag, hover, up }) void {
        switch (op) {
            .down => {
                const component = board.addComponent(.{
                    .ul = mpos,
                    .size = ivec2{ 1, 1 },
                    .tag = .wire,
                }) catch return;
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
                    mut.size = br - ul;

                    if (op == .up) board.placing_wire = null;
                }
            },
            .hover => {},
        }
    }
};

const WirePad = struct {
    // does not collide with a component if a wire pad has a component at that location
    ul: ivec2,
};
const WireConnection = struct {
    start_wire: ComponentID,
    end_wire: ComponentID,
};
const Component = struct {
    ul: ivec2,
    size: ivec2,
    tag: enum {
        wire,
        custom,

        // transistor_npn,
        not, // changed decision. let's do a not instead of a transistor
        // why? transistor is a bit complicated & prevents you from creating something from nothing
        // if you can't create something from nothing then we can't have you make a nor component unless we add an extra input
        // so it's just unnecessary complication
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

// wire design selection:

//
// a wire connects two wire pads in a horizontal line
// wires can cross over eachother
// if you put a wire pad between two other wire pads, it connects to the wire
// sample
//            _____
//      X    [     ]
// X----+----X NOT X
//      X-X  [_____]
//        |
//        X
//
// components have wire pads on their i/o
//
//
// wires cannot go thru components

// impl changes:
// - we can seperate true components from wires & wire pads
// - when you draw a wire, you place two wire pads and the components connecting them
// - there are no implicit connections (except if you place a wire pad on a wire)
