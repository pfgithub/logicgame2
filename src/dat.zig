const Component = struct {
    ul: @Vector(2, i32),
    br: @Vector(2, i32),
    base_scale: i32, // 1,2,4,8,16,32

    data: []PlacedComponent,
};
const PlacedComponent = struct {
    ul: @Vector(2, i32),
};
