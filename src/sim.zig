const std = @import("std");

const Simulator = struct {};

const Component = struct {
    wire_states: []u64,
    instructions: []SimulationInstruction,
    inputs: []usize,
    outputs: []usize,
    default_outputs: []u64, // what this component outputs for input 0,0
    active_instruction: usize,
    simulating: bool = false,

    fn simulate(this: *Component, owner_states: []u64, owner_inputs: []u64, owner_outputs: []u64) void {
        std.debug.assert(!this.simulating); // recursive call not allowed
        this.simulating = true;
        defer this.simulating = false;

        if (for (owner_inputs) |arg| {
            if (owner_states[arg] != 0) break false;
        } else true) {
            for (owner_outputs, this.default_outputs) |oo, do| owner_states[oo] = do;
            return;
        }

        this.active_instruction = 0;
        for (owner_inputs, this.inputs) |oi, ti| this.wire_states[ti] = owner_states[oi];

        while (this.active_instruction < this.instructions.len) {
            switch (this.instructions[this.active_instruction]) {
                .call => |c| c.component.simulate(this.wire_states, c.args, c.ret),
                .transistor_1_64 => |t| {
                    const a: u64 = if (this.wire_states[t.a] & 1 == 1) std.math.maxInt(u64) else 0;
                    this.wire_states[t.c] = a & ~this.wire_states[t.b];
                },
                .transistor_64_64 => |t| this.wire_states[t.c] = this.wire_states[t.a] & ~this.wire_states[t.b],
                .and_64 => |t| this.wire_states[t.c] = this.wire_states[t.a] & this.wire_states[t.b],
                else => @panic(@tagName(this.instructions[this.active_instruction])),
            }
            this.active_instruction += 1;
        }

        for (owner_outputs, this.outputs) |oi, ti| this.wire_states[ti] = owner_states[oi];
    }
};

const SimulationInstruction = union(enum) {
    call: CallArgs,
    transistor_64_1: Basic, // a1: pwr, b64: cond, c64: output
    transistor_64_64: Basic, // a64: pwr, b64: cond, c64: output
    and_64: Basic, // a64: lhs, b64: rhs => c64: out
    or_64: Basic,
    xor_64: Basic,
    add_1: Basic,
    add_2: Basic,
    add_4: Basic,
    add_8: Basic,
    add_16: Basic,
    add_32: Basic,
    add_64: Basic,
};

const Basic = struct {
    a: usize,
    b: usize,
    c: usize,
    d: usize,
    e: usize,
};

const CallArgs = struct {
    component: *Component,
    args: []usize,
    ret: []usize,
};
