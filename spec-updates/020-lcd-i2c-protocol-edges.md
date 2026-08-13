# spec-updates/020 — LCD I2C full protocol edge measurement

**Date:** 2026-08-13
**Category:** 3 (single-implementation, ucsim only)
**Test:** `tests/rung_lcd_i2c.sh` (14 pass, 0 fail)
**Decoder:** `tests/decode_i2c_trace.py`

## What was measured

Full I2C protocol on P2.1 (SDA) and P2.2 (SCL) for the LCD driver,
using `stc12_trace -until-ns 500000000` (500 ms simulated).  Three
firmware variants:

| Fixture | Model | i2c_delay loop | SCL freq |
|---|---|---|---|
| `i2c_1t.ihx` (v1) | STC12 1T | 13 | ~117.6 kHz |
| `i2c_1t_v2.ihx` (v2) | STC12 1T | 26 | ~74.4 kHz |
| `i2c_12t.ihx` | STC89 12T | 3 | ~19.3 kHz |

The previous session measured only SCL phase timing (spec-updates/019,
BENCH-I2C).  This measurement adds the full protocol decode:
START/address/data/ACK/STOP structure, HD44780 init sequence, and
per-transaction validation.

## Protocol structure — verified on all three fixtures

Each I2C transaction:
```
START → address byte (0x4E = 0x27<<1, write) → 1 data byte → STOP
```

**Address:** 0x27 (PCF8574 default), all transactions identical across
all three fixtures.  100% address match on every transaction.

**HD44780 4-bit mode init** (first 24 I2C transactions = 12 EN-pulse
pairs = 4 init nibbles + 4 full commands):

| # | PCF8574 byte | EN | Nibble | Meaning |
|---|---|---|---|---|
| 0-5 | 0x3C/0x38 ×3 | 1/0 ×3 | 0x3 ×3 | Function set attempts (8-bit) |
| 6-7 | 0x2C/0x28 | 1/0 | 0x2 | Switch to 4-bit mode |
| 8-13 | 0x2C/0x28, 0x8C/0x88 | | 0x28 | Function set: 4-bit, 2-line, 5×8 |
| 14-17 | 0x0C/0x08, 0xCC/0xC8 | | 0x0C | Display on, cursor off |
| 18-21 | 0x0C/0x08, 0x6C/0x68 | | 0x06 | Entry mode: increment, no shift |
| 22-23 | 0x0C/0x08, 0x1C/0x18 | | 0x01 | Clear display |

This sequence is byte-identical across all four fixtures (including
`lcd_i2c.ihx`).

PCF8574 bit layout: `D7 D6 D5 D4 BL EN RW RS` (P7..P0).
Backlight (BL, bit 3) is always 1.  RW is always 0 (write).

## SCL timing — data clock pulses only

Measured excluding START/STOP setup edges (which have different I2C spec
limits).  "Dominant" is the most-common value (>70% of all pulses).

| Fixture | t_HIGH (dom) | t_LOW (dom) | Spec t_HIGH≥4000 | Spec t_LOW≥4700 |
|---|---|---|---|---|
| v1 1T (loop=13) | **3255 ns** | 5064 ns | **FAIL** | OK |
| v2 1T (loop=26) | 5606 ns | 7415 ns | OK | OK |
| 12T (loop=3) | 15191 ns | 36892 ns | OK | OK |

v1 is confirmed out-of-spec (t_HIGH 3255 < 4000 ns minimum).
v2 and 12T both pass NXP I2C standard-mode minimums.

v2 timing confirms the handoff's numbers: t_HIGH = 5.61 µs (vs handoff
5.61 µs), t_LOW = 7.41 µs (vs handoff 7.26 µs — the 150 ns difference
is likely a different edge-counting method in the previous session).

## ACK behavior

All transactions show NACK on both address and data bytes.  This is
expected: ucsim does not simulate an I2C slave device, so the open-drain
SDA line stays high during the ACK clock pulse.  A real PCF8574 would
pull SDA low.  This does not affect the protocol structure or timing
measurement.

## What this does not verify

- That a real PCF8574 + HD44780 LCD would display correctly (needs
  silicon or a slave-aware I2C model)
- That the data bytes after init produce meaningful display output
  (they depend on the Scratch program that generated the firmware)
- Setup and hold times (t_SU:DAT, t_HD:DAT, t_SU:STA, t_HD:STA) —
  these require measuring SDA-to-SCL edge relationships, not just
  SCL phase timing
- Repeated-START (the driver doesn't use it)

## Promotion path

**Cat 3 → cat 2b:** Run the same firmware on emu8051 (requires
emu8051 to emit P2 pin events with ns timestamps — it currently has
port tracing for P1 only).

**Cat 3 → cat 1:** Logic analyser on SCL/SDA of a real STC12 running
`i2c_1t_v2.ihx` driving a PCF8574 + LCD.  BENCH-I2C in
spec-updates/019 covers this.
