const std = @import("std");

const Simulator = struct {};

const Wire = usize;

pub fn main() !void {
    var arena_alloc = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    const fcontents = try std.fs.cwd().readFileAlloc(arena, "src/example.lg", std.math.maxInt(usize));
    const component = try Component.parse(arena, fcontents);
    _ = component;
}

const Parser = struct {
    const Srcloc = usize;
    components: std.StringArrayHashMapUnmanaged(*ParserCompleteComponent),
    active_component: ?ParserComponent = null,
    arena: std.mem.Allocator,
    has_errors: bool = false,

    const ParserCompleteComponent = struct {
        written: bool,
        loc: Srcloc,
        value: Component,

        expected_inputs: usize,
        expected_outputs: usize,
    };

    const ParserComponent = struct {
        loc: Srcloc,
        name: []const u8,
        wire_states: std.StringArrayHashMapUnmanaged(Srcloc) = .empty,
        instructions: std.ArrayListUnmanaged(SimulationInstruction) = .empty,
        inputs: std.ArrayListUnmanaged(Wire) = .empty,
        arena: std.mem.Allocator,

        fn getWireState(component: *ParserComponent, parser: *Parser, loc: Srcloc, label: []const u8, mode: enum { any, get, add }) !Wire {
            const gpres = try component.wire_states.getOrPut(component.arena, label);
            if (gpres.found_existing) {
                if (mode == .add) return parser.err(loc, "wire state `{s}` already defined\nnote: src/example.lg:{d}: previous definition here", .{ label, gpres.value_ptr.* });
                return gpres.index;
            }
            if (mode == .get) return parser.err(loc, "wire state `{s}` not defined", .{label});
            gpres.value_ptr.* = loc;
            return gpres.index;
        }
    };

    fn getComponent(parser: *Parser, loc: Srcloc, label: []const u8, expected_inputs: usize, expected_outputs: usize) !*ParserCompleteComponent {
        const gpres = try parser.components.getOrPut(parser.arena, label);
        if (gpres.found_existing) {
            if (gpres.value_ptr.*.*.expected_inputs != expected_inputs or gpres.value_ptr.*.*.expected_outputs != expected_outputs) {
                return parser.err(loc, "mismatched args counts\nnote: src/example.lg:{d}: previous here", .{gpres.value_ptr.*.*.loc});
            }
            return gpres.value_ptr.*;
        }
        gpres.value_ptr.* = try parser.arena.create(ParserCompleteComponent);
        gpres.value_ptr.*.* = .{
            .written = false,
            .loc = loc,
            .value = undefined,
            .expected_inputs = expected_inputs,
            .expected_outputs = expected_outputs,
        };
        return gpres.value_ptr.*;
    }

    fn err(parser: *Parser, loc: Srcloc, comptime fmt: []const u8, arg: anytype) error{ParseError} {
        std.log.err("src/example.lg:{d}: " ++ fmt, .{loc} ++ arg);
        parser.has_errors = true;
        return error.ParseError;
    }

    fn parseLine(parser: *Parser, loc: Srcloc, line: []const u8) !void {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) return;

        var space_iter = std.mem.tokenizeScalar(u8, trimmed, ' ');
        const instruction = space_iter.next() orelse return parser.err(loc, "empty line", .{});
        if (std.mem.eql(u8, instruction, "DEFINE")) {
            if (parser.active_component != null) {
                return parser.err(loc, "DEFINE while active component extant\nnote: src/example.lg:{d}: current definition here", .{parser.active_component.?.loc});
            }
            const name = space_iter.next() orelse return parser.err(loc, "missing DEFINE name", .{});
            const arrow = space_iter.next() orelse return parser.err(loc, "missing DEFINE arrow", .{});
            if (!std.mem.eql(u8, arrow, "->")) return parser.err(loc, "bad arrow", .{});

            parser.active_component = .{
                .loc = loc,
                .name = name,
                .arena = parser.arena,
            };
            var component = &parser.active_component.?;

            while (space_iter.next()) |item| {
                try component.inputs.append(parser.arena, try component.getWireState(parser, loc, item, .add));
            }
            return;
        }
        if (parser.active_component == null) return parser.err(loc, "missing active component", .{});
        var component = parser.active_component.?;

        if (std.mem.eql(u8, instruction, "OUTPUT")) {
            defer parser.active_component = null; // end component regardless of if we succeeded or not
            var outputs = std.ArrayListUnmanaged(Wire).empty;
            while (space_iter.next()) |item| {
                try outputs.append(parser.arena, try parser.active_component.?.getWireState(parser, loc, item, .get));
            }

            const wire_states = try parser.arena.alloc(u64, component.wire_states.count());
            @memset(wire_states, 0);
            const default_outputs = try parser.arena.alloc(u64, outputs.items.len);
            @memset(default_outputs, 0);

            const final = try parser.getComponent(loc, component.name, component.inputs.items.len, outputs.items.len);
            if (final.written) return parser.err(loc, "duplicate component definition `{s}`\nnote: src/example.lg:{d}: previous definition here", .{ component.name, component.loc });

            final.loc = loc;
            final.value = .{
                .wire_states = wire_states,
                .instructions = try component.instructions.toOwnedSlice(parser.arena),
                .inputs = try component.inputs.toOwnedSlice(parser.arena),
                .outputs = try outputs.toOwnedSlice(parser.arena),
                .default_outputs = default_outputs,
                .default_outputs_filled = false,
            };
            final.written = true;
        } else return parser.err(loc, "TODO instruction `{s}`\nnote: src/{s}:{d}: implement here", .{ instruction, @src().file, @src().line });
    }
};

const Component = struct {
    wire_states: []u64,
    instructions: []SimulationInstruction,
    inputs: []Wire,
    outputs: []Wire,
    default_outputs: []u64, // if we go the route of having 'transistor' be the only base component, this will always be @splat(0) so it's worthless
    default_outputs_filled: bool,
    active_instruction: usize = 0,
    simulating: bool = false,

    fn parse(arena: std.mem.Allocator, src: []const u8) !*Component {
        var parser = Parser{ .arena = arena, .components = .empty };

        var lines_iter = std.mem.splitScalar(u8, src, '\n');
        var loc: Parser.Srcloc = 1;
        while (lines_iter.next()) |line| : (loc += 1) {
            parser.parseLine(loc, line) catch |err| switch (err) {
                error.OutOfMemory => return err,
                error.ParseError => continue,
            };
        }

        if (parser.active_component != null) parser.err(parser.active_component.?.loc, "unfinished component", .{}) catch {};
        for (parser.components.entries.items(.value)) |component| {
            if (!component.written) {
                parser.err(component.loc, "component not defined", .{}) catch {};
            }
        }

        if (parser.components.count() < 1) parser.err(loc, "Must define at least one component", .{}) catch {};
        if (parser.has_errors) return error.ParseError;

        // fill default_outputs for all components, only if there were no errors
        for (parser.components.entries.items(.value)) |component| {
            std.debug.assert(component.written);
            if (component.value.default_outputs_filled) continue;
            const owner_states = try arena.alloc(u64, component.expected_inputs + component.expected_outputs);
            const owner_inputs = try arena.alloc(Wire, component.expected_inputs);
            const owner_outputs = try arena.alloc(Wire, component.expected_outputs);
            for (owner_states) |*a| a.* = 0;
            for (owner_inputs, 0..) |*a, i| a.* = i;
            for (owner_outputs, component.expected_inputs..) |*a, i| a.* = i;
            component.value.simulate(owner_states, owner_inputs, owner_outputs);
            std.debug.assert(component.value.default_outputs_filled);
        }

        return &parser.components.entries.items(.value)[0].value;
    }

    fn simulate(this: *Component, owner_states: []u64, owner_inputs: []Wire, owner_outputs: []Wire) void {
        std.debug.assert(!this.simulating); // recursive call not allowed
        this.simulating = true;
        defer this.simulating = false;

        const inputs_all_zero = for (owner_inputs) |arg| {
            if (owner_states[arg] != 0) break false;
        } else true;
        if (inputs_all_zero and this.default_outputs_filled) {
            for (owner_outputs, this.default_outputs) |oo, do| owner_states[oo] = do;
            return;
        }

        this.active_instruction = 0;
        for (owner_inputs, this.inputs) |oi, ti| this.wire_states[ti] = owner_states[oi];

        while (this.active_instruction < this.instructions.len) {
            switch (this.instructions[this.active_instruction]) {
                .call => |c| c.component.simulate(this.wire_states, c.args, c.ret),
                .transistor_64_1 => |t| {
                    const a: u64 = if (this.wire_states[t.a] & 1 == 1) std.math.maxInt(u64) else 0;
                    this.wire_states[t.c] = a & ~this.wire_states[t.b];
                },
                .transistor_64_64 => |t| this.wire_states[t.c] = this.wire_states[t.a] & ~this.wire_states[t.b],
                .and_64 => |t| this.wire_states[t.c] = this.wire_states[t.a] & this.wire_states[t.b],
                else => @panic(@tagName(this.instructions[this.active_instruction])),
            }
            this.active_instruction += 1;
        }

        for (owner_outputs, this.outputs) |oi, ti| owner_states[oi] = this.wire_states[ti];
        if (inputs_all_zero and !this.default_outputs_filled) {
            for (this.default_outputs, this.outputs) |*oi, ti| {
                oi.* = this.wire_states[ti];
            }
            this.default_outputs_filled = true;
        }
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
    a: Wire,
    b: Wire,
    c: Wire,
    d: Wire,
    e: Wire,
};

const CallArgs = struct {
    component: *Component,
    args: []Wire,
    ret: []Wire,
};
