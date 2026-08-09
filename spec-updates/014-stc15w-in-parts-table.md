# Proposed: add STC15W408AS to STC_PARTS and TARGETS

From ucsim-stc. For stc-compiler (TARGETS) and sb3-creator/bw-blocks (STC_PARTS).

## The gap

Both emulators now model STC15W408AS (`-t STC15W` / `-part STC15W`).
Neither the compile chain nor the block surface knows this part:

- `stc_pseudocode.py` TARGETS: no `stc15w408as` entry
- `sb3Creator.js` STC_PARTS: no `stc15w408as` entry

A user can run firmware on STC15W but cannot compile for it or select it
in the block editor.

## What the entry should be

```python
# stc_pseudocode.py
"stc15w408as": _stc("stc15w408as", "STC15W408AS", "stc12.h", True, True, True),
```

```javascript
// sb3Creator.js
stc15w408as: { header: 'stc12.h', portModes: true, aux1T: true, adc: true },
```

Same as `stc15f2k60s2` — the STC15W408AS uses the same SFR addresses for
all peripherals the emitter touches (AUXR, PxM0/PxM1, Timer 0, P1ASF, ADC).

## What is different and why it doesn't change the entry

The STC15W408AS lacks Timer 1, P4, P5, and UART2. But:
- The emitter never writes Timer 1 SFRs (baud comes from BRT/Timer 2)
- The emitter never touches P4/P5 (only P0-P3)
- The emitter never writes UART2

The `TONE` pin feature uses Timer 1, which the STC15W doesn't have.
The right behavior: warn at compile time, same as `adc: false` on STC89.
Suggest adding `timer1: false` to the entry (new field, default true),
and let the emitter warn: "TONE pins need Timer 1, and the STC15W408AS
has none."

## What NOT to do

Do not add `stc15w408as` entries pointing at `8052.h` — it is NOT a
standard 8052. It has port modes, AUXR, ADC, PCA. It is an STC15
variant with fewer peripherals, not an STC89.
