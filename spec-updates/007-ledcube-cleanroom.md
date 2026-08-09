# ledcube444: cleanroom rewrite needed, not a port

## The problem

rgm3/ledcube444 is a port of unlicensed vendor firmware (icstation
4681.zip). The rgm3 repo carries MIT but cannot grant rights on
code it did not write. We cannot integrate it into any MIT repo.

## The cleanroom approach

1. **Write a hardware spec** from the circuit diagram and kit docs
   (not from the code). The hardware is public: 4x4x4 two-color
   LED cube, P0 drives columns, P2 selects layers via scan,
   STC12C5A60S2 on a PCB from icstation kit #4682.

2. **Hand the spec to a fresh agent** who has NOT read either the
   icstation source or the rgm3 port. The spec describes what the
   hardware does, not how the code is structured.

3. **The agent writes new code** from the spec. The result is
   independently authored and can carry MIT.

## Who is contaminated

- ucsim-stc agent: READ both sources in this session. Cannot write.
- emu8051-stc agent: may have read the hex. Check before assigning.

## What goes in the spec (hardware facts, not code)

- 4x4x4 LED matrix, two colors (red/blue), common-anode layers
- P0[7:0] drives 8 column lines (4 red + 4 blue per layer)
- P2[7:0] selects layers (active-low, one at a time, 8 scan lines
  for the 4 physical layers × 2 colors)
- Scan rate must exceed ~100 Hz to avoid flicker
- Pattern data is in code flash (read-only lookup tables)
- delay_ms is a software busy-loop (the kit has no timer-based delay)

## Where the result lives

stc/src/ or stc/examples/ — MIT, part of the project's own firmware.
NOT in ucsim-stc (GPL) or stc-research (unlicensed).
