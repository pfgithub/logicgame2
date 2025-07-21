const Component = struct {
    ul: @Vector(2, i32),
    br: @Vector(2, i32),
    base_scale: i32, // 1,2,4,8,16,32

    data: []PlacedComponent,
};
const PlacedComponent = struct {
    ul: @Vector(2, i32),
};

// basic components:
// 1x wire, 2x wire, 4x wire, 8x wire, 16x wire, 32x wire, 64x wire
// n-to-n splitters and mergers for these wires
//    - it would be nice if we didn't need this?
// bridges
//    - this might not be its own component
//    - alternatives:
//      - o1: two layers where wires automatically make vias
//      - o2: if you drag a wire across another wire it makes a long wire that doesn't connect
// 1-1 npn "transistor" (or not gate, we choose)
// all other components are user components
