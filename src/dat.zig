const Component = struct {
    ul: @Vector(2, i32),
    br: @Vector(2, i32),
    base_scale: i32, // 1,2,4,8,16,32

    octree: QuadtreeEntry,
};

const QuadtreeEntry = struct {
    parts: []Part,
    subtree: ?*[4]QuadtreeEntry,
    average: u32, // average color of the 8 children
};
const Part = struct {};

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
