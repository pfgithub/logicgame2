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

        switch (this.instructions[this.active_instruction]) {
            .call => |c| c.component.simulate(this.wire_states, c.args, c.ret),
            .transistor_64 => |t| {
                // (pwr, cond) => (cond ? 0 : pwr)
                // a1: pwr, a2: cond, a3: output
                // pwr & ~cond

                this.wire_states[t.a3] = this.wire_states[t.a1] & ~this.wire_states[t.a2];
            },
        }

        for (owner_outputs, this.outputs) |oi, ti| this.wire_states[ti] = owner_states[oi];
    }
};

const SimulationInstruction = union(enum) {
    call: CallArgs,
    transistor_64: Basic,
    not_64: Basic,
    and_64: Basic,
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
    a1: usize,
    a2: usize,
    a3: usize,
    a4: usize,
    a5: usize,
};

const CallArgs = struct {
    component: *Component,
    args: []usize,
    ret: []usize,
};
