# Oracle Corpus Cross-Check — ucsim vs emu8051

**Date:** 2026-08-17
**Baseline:** ucsim `421505a`, emu8051 `83b35ef`

## Method

Each program compiled from source (SDCC via stc-compiler API), then the
SAME hex run through both emu_trace (emu8051) and stc12_trace (ucsim) for
2 simulated seconds at FOSC=11059200. PIN event streams compared.

## mogoreanu/8x16 (STC15F2K60S2)

Real-world 8×16 LED matrix pixel editor. Timer 0 ISR-driven display
refresh, 6-button input, P0–P5 push-pull port config.
Source: github mogoreanu/8x16 (MIT).

| Metric | emu8051 | ucsim | Status |
|--------|---------|-------|--------|
| Hex bytes | 4554 | 4554 | same hex |
| Boot | clean | clean | MATCH |
| PIN events | 986 | 973 | explained |
| SFR+TF events | 2248 | 2256 | TCON init divergence |

### PIN event analysis

- **15 mode-change events**: emu8051 emits PIN events when PxM0 registers
  set push-pull mode. ucsim does not. These are at init time (events 38-52
  in emu8051 stream). Same convention difference as boot census.
- **2 boundary timing events**: ucsim produces 2 extra events at the tail
  (`PIN 2.1 Q H`, `PIN 4.2 Q L`) — one more timer ISR fires before the
  2-second cutoff. Boundary timing, not a core divergence.
- **After removing mode events**: first 971 PIN events are **identical**.

### SFR event analysis (diagnostic)

SFR stream diverges at init:
1. ucsim emits `SFR C8 00` (P5) and `SFR CA 10` (P5M0) — P5 init writes
   that emu8051 does not trace.
2. TCON values differ: ucsim shows 0x0A (IE1+IT1 bits set), emu8051 shows
   0x00. The IE1/IT1 edge flags may be initialized differently on the two
   models. **Root cause: under investigation.**

### Verdict: **PASS** (PIN-equivalent, no core divergence)

---

## rainbowpeee/空程序 (STC15F2K60S2)

Minimal program: writes P0=0, P2=0xFF in a tight loop.

| Metric | emu8051 | ucsim | Status |
|--------|---------|-------|--------|
| Hex bytes | 388 | 388 | same hex |
| Boot | clean | clean | MATCH |
| PIN events | 8 | 8 | **EXACT MATCH** |

---

## rainbowpeee/流水灯 (STC15F2K60S2)

LED chaser: rotates a bit pattern across P1 with delay loop.

| Metric | emu8051 | ucsim | Status |
|--------|---------|-------|--------|
| Hex bytes | 1586 | 1586 | same hex |
| Boot | clean | clean | MATCH |
| PIN events | 219 | 219 | **EXACT MATCH** |

---

## Summary

| Program | PIN match | Boot | Notes |
|---------|-----------|------|-------|
| mogoreanu/8x16 | 971/971 prefix | clean | +15 mode events (emu), +2 boundary (ucsim) |
| rainbowpeee/空程序 | 8/8 exact | clean | |
| rainbowpeee/流水灯 | 219/219 exact | clean | |

**Zero unexplained divergences. Zero wedges.**
All PIN event differences are fully explained by the mode-event counting
convention (documented in BOOT-CENSUS-CROSSCHECK.md) and boundary timing.

## Open investigation

- **TCON IE1/IT1 init**: ucsim initializes TCON with IE1+IT1 bits set (0x0A),
  emu8051 does not. These are external interrupt edge flags. Does not affect
  PIN behavior but shows in SFR trace. Root cause TBD.
