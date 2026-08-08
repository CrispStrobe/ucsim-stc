# emu8051 cycle count convention error

## Finding

emu8051's opcode return values use the convention:
- return 0 = 1 tick (correct for NOP)
- return N = 1 + N ticks total

57 opcodes (DJNZ, LJMP, LCALL, RET, SJMP, MOV direct,#, etc.)
return 2 with a comment saying "2 machine cycles". But in the
return-N convention, return 2 = 3 ticks, not 2.

The MCS-51 spec says these are 2 machine cycles. They should
return 1 (= 1 + 1 = 2 ticks), not 2 (= 1 + 2 = 3 ticks).

## Evidence

The first SFR event after reset:
- emu8051: 72,711 ns = ~804 osc clocks
- ucsim:  97,113 ns = ~1074 osc clocks

ucsim uses the correct MCS-51 cycle table (DJNZ = 2 cycles).
The 270-clock gap is exactly the IRAM-clear loop:
256 iterations × (DJNZ overcounted by 1) = 256 extra clocks,
plus ~14 from other overcounted 2-cycle instructions in startup.

## What should change in emu8051

All opcodes currently returning 2 with "2 machine cycles" comment
should return 1. This is 57 opcodes. The 4-cycle opcodes (MUL/DIV)
returning 4 should return 3.

## Source

Intel MCS-51 Microcontroller Family User's Manual, Table A-2.
Not derived from making the diff agree — ucsim's table was
written from the published spec independently.
