# emu8051 cycle count convention — RETRACTED

## Original claim (retracted)

Claimed that emu8051's 2-cycle opcodes returning 2 gave 3 ticks
instead of 2. This was wrong.

## What actually happened

emu8051's convention: return N = N ticks total (return 0 = 1 tick,
return 2 = 2 ticks). The N=0 case works because after execution
with mTickDelay=0, the next tick also has mTickDelay=0 and executes
immediately. Empirically verified by emu8051 agent with test_cycles.c.

The 25% timing gap was caused by **ucsim double-counting**: the base
ucsim instruction handlers already call `tick(N)` internally for
multi-cycle instructions (jmp.cc, bit.cc, arith.cc), and `tickt()`
adds `tick(1)` when tick_tab returns NULL. My tick_tab override
added `tick(2)` for 2-cycle instructions ON TOP of the handler's
`tick(1)`, giving 3 ticks instead of 2.

## Resolution

Removed the tick_tab override. The base ucsim instruction handlers
are correct. The stc12_cycle_tab array is retained as documentation
but not used.

After fix: timing gap is 0.1% (1 clock), down from 25% (269 clocks).
