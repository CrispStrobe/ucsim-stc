# PLAN — STC12C5A60S2 model for ucsim

## Status (2026-08-08)

**Phases 0-5 implemented and committed.** The STC12 model builds, runs, and
passes smoke tests:
- `-t STC12` or `-t STC12C5A60S2` selects the model
- Timer 0 in 12T mode: 922 counts = 11064 osc clocks → TF0 set (correct)
- Timer 0 in 1T mode: 12x faster (12 counts per 12 osc clocks)
- 01-blink compiled image runs: board_init sets P1M0=0x03 (push-pull),
  delay_init configures Timer 0 mode 1, LED pattern toggles on P1

**Phase 6 (PCA):** PCA subclassed with 1T prescaler. FOSC/12 and FOSC/2
sources verified.

**Phase 7 (integration):**
- 01-blink compiled image: runs correctly, LED pattern toggles on P1
- 02-adc compiled image: ADC_CONTR power/start/flag sequence works,
  synthetic mid-scale result (0x200) returned, P1ASF gating functional
- Differential execution: SFR map correctly different from C52 (P5 at
  0xC8 instead of T2CON, all STC12 registers named and accessible)
- PCA counter counts at FOSC/12 (12 osc ticks = 1 count) and FOSC/2
  (10 osc ticks = 5 counts)
- Cooperative-scheduler test (Timer 0 ISR + bw_ms counter): interrupt
  vector works, ISR fires and returns correctly, volatile ms counter
  increments. This is the same pattern generateC emits.

## Phase 0: Baseline
1. Fetch SDCC 4.5.0 orig tarball from Debian (SourceForge is 403 here).
2. Unpack **only** `sim/ucsim/` into this repo.
3. Get `s51` building and running (`./configure && make` in ucsim/).
4. Commit the unmodified baseline so every later diff is against stock ucsim.

## Phase 1: Scaffold the STC12 model
5. Study how existing derived models work (Silabs, Atmel variants under `s51.src/`).
6. Create a new `sstc12.src/` directory (or extend `s51.src/` with a new processor class)
   following the existing pattern — class hierarchy, Makefile, processor registration.
7. Register the new `STC12C5A60S2` processor type so `ucsim -t stc12` loads it.
8. Commit the empty scaffold (builds, selects the new type, does nothing new yet).

## Phase 2: SFR set
9. Add all STC12-specific SFRs from the table in CLAUDE.md / stc_disasm.py:
   - Port-mode registers: P0M0/P0M1, P1M0/P1M1, P2M0/P2M1, P3M0/P3M1, P4M0/P4M1, P5M0/P5M1
   - AUXR (0x8E), AUXR1 (0xA2), CLK_DIV (0x97)
   - P4 (0xC0), P5 (0xC8), P4SW (0xBB)
   - P1ASF (0x9D)
   - ADC registers: ADC_CONTR (0xBC), ADC_RES (0xBD), ADC_RESL (0xBE)
   - PCA registers: CCON (0xD8), CMOD (0xD9), CCAPM0 (0xDA), CCAPM1 (0xDB),
     CL (0xE9), CH (0xF9), CCAP0H (0xFA), CCAP1H (0xFB), PCA_PWM0 (0xF2), PCA_PWM1 (0xF3)
10. Commit SFR additions.

## Phase 3: Timer 0 + AUXR.7 (1T timing)
11. Hook AUXR.7 write so Timer 0 prescaler switches between FOSC/12 and FOSC.
12. Test: with FOSC=11059200, T0 mode 1, reload 65536−FOSC/12/1000 → 1 ms tick in both
    AUXR.7 states (12T default, 1T when set).
13. Commit.

## Phase 4: Port modes
14. Implement PxM1/PxM0 write callbacks so port pin behaviour changes:
    00=quasi-bidir, 01=push-pull, 10=input-only, 11=open-drain.
15. Commit.

## Phase 5: ADC
16. Implement ADC_CONTR write (power-on, start, channel select, speed bits).
17. ADC_FLAG (bit 4 of ADC_CONTR) set on conversion complete; cleared by software.
18. ADC_RES/ADC_RESL hold a 10-bit result.
19. P1ASF selects analog function on P1 pins.
20. Commit. Note: untested on silicon — register *sequence* consistency only.

## Phase 6: PCA / PWM
21. Implement PCA counter (CL/CH), module registers, basic 8-bit PWM mode.
22. Commit.

## Phase 7: Integration test
23. Build `01-blink` image (from /mnt/volume1/code/stc/src/01-blink or via the hosted
    compiler) and run under the new model.
24. Compare against s51 — differential execution.
25. Document what works and what doesn't.

## Decision points (stop and check in)
- After Phase 0: confirm baseline builds.
- After Phase 1: confirm scaffold approach before filling in behaviour.
- After Phase 3: confirm timer correctness before moving on.
- After Phase 5: discuss ADC fidelity expectations.
