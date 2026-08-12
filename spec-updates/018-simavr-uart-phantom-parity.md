# spec-update 018: simavr UART phantom parity bit

**Date:** 2026-08-12
**Emulators:** simavr 1.6 (Debian) vs avr8js
**Target:** ATmega328P @ 16 MHz, 9600 baud 8N1 (UBRR=103)

## Observation

Back-to-back UART TX bytes drift by exactly **1 bit-time (1664 cycles)** per
byte between simavr and avr8js. First byte timing agrees; subsequent bytes
accumulate one extra bit-time of delay in simavr per byte transmitted.

| Byte # | simavr (cy) | avr8js (cy) | drift (cy) |
|--------|------------|------------|-----------|
| 1 (H)  | 152        | 152        | 0         |
| 2 (e)  | 18464      | 16799      | 1665      |
| 3 (l)  | 36776      | 33446      | 3330      |
| 4 (l)  | 55088      | 50093      | 4995      |

Drift per byte = 1665 ≈ (UBRR+1) × 16 = 1664 cycles = 1 bit time.

## Root cause

In `avr_uart.c` (`avr_uart_baud_write`), simavr computes
`cycles_per_byte = cycles_per_bit × word_size` where:

```c
int word_size = 1 /* start */ + db /* data bits */
              + 1 /* parity */ + sb /* stops */;
```

The `+ 1 /* parity */` is unconditional — it is included even when parity
is disabled (8N1 mode). For 8N1 this gives `1 + 8 + 1 + 1 = 11` bits per
frame instead of the correct `1 + 8 + 0 + 1 = 10`.

## Datasheet (judge)

ATmega328P datasheet, section 24.6 "Data Transfer":

> "A serial frame is defined to be one character of data bits with
> synchronization bits (start and stop bits), and optionally a parity bit
> for error checking."

Table 24-1 frame formats: 8N1 = start(1) + data(8) + stop(1) = **10 bits**.
Parity is 0 bits when UPM[1:0] = 00 (disabled).

**Verdict: avr8js is correct. simavr overcounts by 1 bit per frame in 8N1.**

## Impact on oracle use

- **Pin-edge timing**: unaffected. All blink/GPIO tests agree exactly.
- **ADC completion timing**: unaffected. First-byte cycle matches.
- **UART byte values and order**: unaffected. All bytes match.
- **UART timing**: each byte after the first drifts by N × 1664 cycles.
  For a 10-byte message at 9600 baud, the last byte arrives 9 × 1664 =
  14976 cycles (~0.94 ms) late — a 10% timing error.

For the oracle role: simavr is reliable for **instruction cycle counts,
pin edges, and ADC behavior**. For UART-dependent timing comparisons,
use avr8js as the reference and note the known 1-bit/byte drift in simavr.

## Upstream

This is a known simavr issue. The fix would be to conditionally add the
parity bit only when UPM != 0. We do not patch simavr (LGPL, used as a
system library); we document the discrepancy and work around it.

## Test

`tests/rung_avr_oracle.sh` — test 3 flags this as KNOWN.
