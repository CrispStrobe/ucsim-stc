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

**P0 polarity — UNVERIFIED, assumed active-low.**

This spec assumes a LOW bit on P0 lights the corresponding LED
(cathode drive through current-limiting resistors, common-anode
layers).  Under this convention:
- P0 = 0x00 lights all LEDs in the selected layer.
- P0 = 0xFF lights none (blank).
- `fb_clear()` should fill with 0xFF; setters clear bits.

`probe.c` in `stc/src/20-ledcube/` assumes the **opposite**
(active-high: a HIGH bit lights the LED, P0=0x00 is blank).
The two are both internally consistent; only a real cube settles
which is correct.

**All implementations must isolate this assumption in one named
constant** so flipping it is a one-line change:

```c
#define P0_LED_ON  0   /* active-low: 0 lights, 1 blanks */
/* OR: #define P0_LED_ON  1   active-high: 1 lights, 0 blanks */
#define P0_ALL_OFF (P0_LED_ON ? 0x00 : 0xFF)
```

This is the second unmeasured fact (after the voxel map) that only
a real cube can answer.

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

### Implementation note: framebuffer

A practical approach is an 8-byte array (one byte per scan line).
The animation code fills this buffer; the scan loop reads it.
This separates "what to display" from "how to scan".

## 4. Animation patterns

The cube should display at least these patterns (in order):

1. **All on** — every LED lit (P0 = 0x00 on all scan lines), steady
   for ~3 seconds.  Both colors.
2. **Layer sweep** — one layer at a time, bottom to top then top to
   bottom (bounce: layers 0,1,2,3,2,1,0,1,...).  Use red LEDs
   (P0 bits 0–3).  Each layer visible for ~200 ms.
3. **Rain** — LEDs appear in the top layer and fall down one layer
   per step.  Use blue LEDs (P0 bits 4–7).  4 drops at staggered
   positions, cycling through 4 column rotations.  ~100 ms per step.
4. **Spiral** — one column lit at a time, sweeping through all 4
   columns on each layer, bottom to top.  Both colors.  ~100 ms
   per position.

Each pattern runs for ~3 seconds before advancing to the next.
The sequence repeats forever.

Pattern data should be stored in code flash (`__code` arrays) to
save RAM.  The implementer chooses the exact patterns; these
descriptions are goals, not pixel-level prescriptions.

## 5. Timing

Use **Timer 0 at FOSC/12, mode 1** for the dwell delay —
the same technique `stc/src/20-ledcube/probe.c` uses and the
same mode the BrickWright toolchain uses.  A 12T and a 1T part
count Timer 0 at FOSC/12 identically, so the dwell is correct
on both.  Do NOT use a software busy-loop: the STC12 is a 1T
part and a loop calibrated for 12T runs ~12× too fast, making
the LEDs too dim to see.

```c
/* Timer 0 polled delay — same pattern as delay.h in this repo */
static void delay_ms(unsigned int ms) {
    AUXR &= ~0x80;  /* T0 at FOSC/12 */
    TMOD = (TMOD & 0xF0) | 0x01;  /* mode 1, 16-bit */
    while (ms--) {
        TL0 = 0x67;  /* reload for 1 ms at 11059200/12 */
        TH0 = 0xFC;
        TF0 = 0;
        TR0 = 1;
        while (!TF0) ;
        TR0 = 0;
        TF0 = 0;
    }
}
```

Each scan line dwell should be ~1 ms.  Full 8-line scan < 10 ms
for > 100 Hz refresh.

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

## 7. Cleanroom boundary

**Permitted reading** (measurements and hardware facts):
- This specification (008-ledcube-hardware-spec.md).
- `stc/src/20-ledcube/README.md` — measurement notes, observed
  hardware behavior, timing data.  These are facts, not expression.
- The kit product page, circuit diagram, welding guide PDF.
- `stc/include/stc12.h`, `board.h` — SFR definitions.

**Forbidden reading** (firmware source code):
- `stc-research/corpus/icstation_4681/Code/main.c`
- `stc-research/corpus/rgm3_ledcube444/ledcube444.c`
- `bw-cfront/sb3-creator/corpus/ledcube444/`
- Any `.c` or `.h` file containing LED cube driver logic from
  any third party.
- The hex files from either build (they are compiled expression).

**Other constraints:**
- Timer 0 is used for the dwell delay (polled, not ISR-driven).
  Timer 1 is available but not needed.
- Do NOT use interrupts (not needed for a simple display driver).
- Do NOT use the ADC, PCA, or UART (not connected on this PCB).

## 8. Deliverable

One C file at `stc/src/20-ledcube/main.c`, compilable with
`sdcc -mmcs51 --model-small`.  Include `<stc12.h>` for the SFR
definitions.  Self-contained (no external headers beyond stc12.h
and stdint.h).

The file header must state that it was written from this hardware
specification.  The cleanroom claim is a statement about the author;
it must be written by the implementing agent, not by the spec author.

Test by running under ucsim (`ucsim_51 -t STC12`) and checking
that P0 and P2 change in the expected scan pattern.
