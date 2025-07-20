base components:

- transistor (pwr, cond) => (cond ? 0 : pwr)

optimized components:

- and(2), or(2), nor(2), xor(2), add(1,1,1,1), add(2,2,2,1), add(4, 4, 4, 1), ...

components have designated inputs and outputs. when there are subcomponents, the 'call' instruction is used to call a subcomponent


still needed for optimization:

- should we go back to front instead of front to back? that way we can ignore unused things?
- either way we need to be able to skip simulating unneeded things

do we want?

- do we want to disallow making something from nothing?
- if we do this, then 'energy usage' metric makes sense



histograms:

- cycle time (worst-case distance from input to output)
- area
- energy usage (number of on state wires cells each frame)
  - alternatively: each component which has any inputs on uses energy based on its area
  - to reduce energy usage, make sure components have all their inputs off
  - this matches up with real cpu usage so maybe this makes more sense





levels:
0-0 not (built-in gate)
0-1 or (connect wires together)
0-2 nor (not or)
0-9 and (not (not a or not b))




game:

- square
- touching wires connect