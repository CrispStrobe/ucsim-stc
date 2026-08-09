# Hardware specification: 4x4x4 two-color LED cube

**Purpose:** cleanroom implementation brief for a fresh agent.
This document describes the HARDWARE — what the cube is electrically
and what it must do visually. It does NOT describe any existing
firmware. The implementing agent must NOT read the icstation 4681
source, the rgm3/ledcube444 port, or any derivative.

**Licence of the result:** MIT, committed to `stc/src/` or
`stc/examples/`.

---

## 1. The hardware

A 4×4×4 LED cube with two colors (red and blue) per position.
64 LEDs total: 4 layers × 4 columns × 4 rows, each position
having one red and one blue LED sharing a common anode.

Microcontroller: **STC12C5A60S2** (PDIP-40), FOSC = 11,059,200 Hz.

## 2. Wiring

The cube uses **multiplexed scanning**: one layer is lit at a time,
cycling fast enough that persistence of vision makes all layers
appear lit simultaneously.

### Port P0 — column data (accent LEDs per layer)

P0[7:0] drives 8 LED cathode lines per layer. For a 4×4 grid with
two colors, the 8 bits map to 4 positions × 2 colors:

    P0.0 = column 0 red     P0.4 = column 0 blue
    P0.1 = column 1 red     P0.5 = column 1 blue
    P0.2 = column 2 red     P0.6 = column 2 blue
    P0.3 = column 3 red     P0.7 = column 3 blue

A LOW bit lights the corresponding LED (active-low cathode drive
through current-limiting resistors on the PCB). P0 = 0x00 lights
all LEDs in the selected layer; P0 = 0xFF lights none.

### Port P2 — layer select (active-low scan)

P2[7:0] selects which layer's anodes are connected to VCC through
PNP transistor switches. One bit LOW at a time; the rest HIGH.

    P2 = 0xFE  →  layer 0 (bottom)
    P2 = 0xFD  →  layer 1
    P2 = 0xFB  →  layer 2
    P2 = 0xF7  →  layer 3 (top)

The 8 scan values for a two-color 4-layer cube use all 8 bits of
P2, scanning through the layers with separate passes for each
color group. The full scan table (active-low, one bit at a time):

    0xFE, 0xFD, 0xFB, 0xF7, 0xEF, 0xDF, 0xBF, 0x7F

## 3. Scan algorithm

Repeat forever:
1. For each scan line (0..7):
   a. Set P0 = column data for this layer/color from the current
      animation frame.
   b. Set P2 = scan table value (activate one layer).
   c. Wait a short time (the "dwell" — long enough for the LEDs
      to be visible, short enough that the full scan is > 100 Hz).
   d. Set P2 = 0xFF (all layers off — prevents ghosting between
      layers).
2. After completing all 8 scan lines, advance to the next animation
   frame (or stay on the current frame if the pattern holds).

### Timing constraints

- Full scan of 8 lines must complete in < 10 ms for flicker-free
  display (> 100 Hz refresh).
- Each scan line dwell: ~1 ms is typical.
- Animation frame rate: 10–50 fps depending on the pattern.

## 4. Animation patterns

The cube should display at least these patterns (in order):

1. **All on** — every LED lit, steady. The simplest test.
2. **Layer sweep** — one layer at a time, bottom to top, then top
   to bottom.
3. **Rain** — random LEDs light in the top layer and "fall" down
   one layer per frame.
4. **Spiral** — LEDs light in a spiral pattern around the outside
   edges of each layer.

Each pattern runs for a few seconds before advancing to the next.
The sequence repeats forever.

Pattern data should be stored in code flash (`__code` arrays) to
save RAM.

## 5. Software delay

Use a software busy-loop for timing. Do NOT use Timer 0 (which
the BrickWright toolchain reserves for the millisecond tick).

```c
void delay_ms(unsigned int ms) {
    /* Calibrate this loop for the target FOSC.
     * On a 1T STC12 at 11.0592 MHz, approximately:
     *   for (i = 0; i < 120; i++) for (j = 0; j < ms; j++);
     * gives roughly 1 ms per unit of ms.
     * The exact count does not matter for a display —
     * flicker-free is the only constraint. */
}
```

## 6. Initialisation

```c
void main(void) {
    P0 = 0xFF;   /* all LEDs off */
    P2 = 0xFF;   /* all layers off */
    /* No port mode changes needed — quasi-bidirectional default
     * can sink enough current through the resistors on the PCB.
     * Push-pull on P0 and P2 would be slightly cleaner but the
     * kit works without it. */
    while (1) {
        /* run animation patterns */
    }
}
```

## 7. What NOT to do

- Do NOT read or reference the icstation 4681 source code, the
  rgm3/ledcube444 port, or any derivative. This is a cleanroom spec.
- Do NOT use Timer 0 or Timer 1 for the delay (reserved).
- Do NOT use interrupts (not needed for a simple display driver).
- Do NOT use the ADC, PCA, or UART (not connected on this PCB).

## 8. Deliverable

One C file, compilable with `sdcc -mmcs51 --model-small`, that
drives the LED cube through the animation patterns above. Include
`<stc12.h>` for the SFR definitions. The file should be self-contained
(no external headers beyond stc12.h and stdint.h).

Test it by running under ucsim (`ucsim_51 -t STC12`) and checking
that P0 and P2 change in the expected scan pattern.
