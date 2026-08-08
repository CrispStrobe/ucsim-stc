# Notes on DEBUG-CONTROL-MODEL.md (boundary D) — before building

Read from `/mnt/volume1/code/stc/docs/DEBUG-CONTROL-MODEL.md`.
These are notes, not proposed changes; the spec is upstream.

## What is clear and right

- The capability matrix (§1) being explicit about what the chip
  cannot do (no code breakpoints, no data watchpoints) is the
  single most important thing in this document.
- §2 Level 1 "three variable reads, no instrumentation" is elegant
  and costs nothing to implement in either emulator.
- §4 defining `over` and `out` in terms of SP is correct — it is
  the only definition that both emulators can implement identically.
- §8 rung 5 (yield breakpoint differential) is where the real value
  is — this is the test that catches the "same program, different
  halt point" bug that free-running traces cannot.

## Questions and potential issues

### step('insn') count=N: atomicity or N individual halts?

§4 lists `count?: number` on `step()`.  Is `step('insn', 10)` "step
10 instructions and halt once at the end" or "halt 10 times, once per
instruction"?  For differential testing (rung 3) it matters: if the
answer is "halt once at the end" then the PC sequence is just start
and end, not the intermediate path.  I'll implement as "step N, halt
once at the end, report final PC" — the intermediate PCs can be
obtained by calling step(kind, 1) N times.

### yield breakpoint: case-label address vs write-watch on state

§5 says both are valid implementations but §8 rung 5 says both must
halt at the same instruction.  This is a contradiction if interpreted
literally: a case-label breakpoint fires when PC reaches the case
address (before the state variable is read), while a write-watch
fires when the state variable is written (which happens earlier, at
the previous yield's `<task>_state = N` assignment).

**Proposed resolution:** both emulators use code breakpoints on the
case-label address.  The address comes from the symbol table, so
both agree.  Write-watch on state is an additional diagnostic, not
the halt mechanism.  Will coordinate with emu8051-stc.

### timeFreezes: true but Timer 0 still accumulated ticks while stepping

When stepping one instruction at a time, `tick_hw` fires per
instruction.  Timer 0 increments.  So `step('insn', 1000)` advances
bw_ms by ~1 ms on the STC12 (1000 clocks at 12T = ~83 timer counts).
Is this "time frozen" or "time advancing"?  The spec says time freezes
while *halted*, not while *stepping*.  Stepping is transient (§3).
This is consistent: time advances during a step, then freezes at the
halt. OK as designed.

### Space 'xram' range: spec says 0x0000-0x03FF but ucsim has 64K

The spec says 1024 B on-chip auxiliary RAM.  ucsim's STC12 model
inherits a 64K xram address space from cl_uc52.  This is correct
for the address space (the CPU can address 64K via MOVX), but only
1024 bytes are backed by real RAM.  Reads beyond 0x03FF would return
whatever the chip's bus floats to.  For now I'll expose the full 64K
and note the discrepancy.

## Implementation plan

1. Add `cl_debug_target` interface to `cl_uc_stc12`
2. Implement capabilities(), state(), run/halt/step/reset
3. Implement code and yield breakpoints
4. Implement readMem/writeMem/regs/setReg
5. Propose symbol table input format (JSON)
6. Extend trace harness for rungs 3-6

## consumes field (§7 decision 5, spec commit e62067d)

For emulators: `consumes: []` (empty array, not null).
An emulator consumes no hardware resources. `null` means "this
target predates the field and is not saying" — which is a different
and weaker claim than "takes nothing".

The case that forced this: a TONE pin uses Timer 1, the on-chip
monitor wants Timer 1 for skewNs, so a buzzer program cannot run
under the monitor. `consumes: ['timer1']` makes this visible.
