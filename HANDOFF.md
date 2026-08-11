# ucsim-stc handoff

For the next session. Read CLOSE-OUT.md for the full campaign; this is the delta.

## Completed since the close-out

- **Servo 0°/90°/180°** measured: 499.1 / 1499.6 / 2500.0 µs, frame 20.0 ms exact. Category 3. STC89 produces 0 edges (no PCA) — bw-blocks added compile-time refusal (sb3-creator `6b0e6f6`).
- **I2C SCL timing** measured: v1 (loop=13) HIGH=3.25 µs — **below 4.0 µs spec**. v2 (loop=26) HIGH=5.61 µs, LOW=7.26 µs — both in spec. bw-blocks fixed in `222b2ab`.
- **NeoPixel 4/4 windows** with runnable test (`tests/rung_neopixel.sh`). T0H=362, T1H=814, T0L=814, T1L=452, all in WS2812 spec. Category 3.
- **Motor duty** 33/50/75% at P1.4: 32.83% / 50.05% / 75.07%.
- **HC-SR04 trigger** measured: 4.7 µs (below 10 µs min), fixed to 10.4 µs (1T) / 20.6 µs (12T).
- **-inject TIME_NS,BYTE** flag in stc12_trace: schedules timed byte delivery to UART RX. RI rises after ~83 µs at 115200. Root cause of bw-board's INCONCLUSIVE: `-inject` requires `-until-ns`, not `-e 'run ...'` (spec-updates/017).
- **PCA interrupt dispatch** at 0x003B with per-module enable (CCAPMn.ECCF0, not IE.EC). IE.6 = ELVD (LVD), not EC — named trap in the peripheral model.
- **PCA CL-wrap fix**: CH must increment before the 16-bit compare, not after. Was causing 256-count (278 µs) systematic error.
- **UART TX bit-timing**: BRT model feeds serial baud clock. Bit period 86.8 µs exact. Naive STC15 port = 5 baud (23040× wrong).
- **CLR/SETB/CPL cycle audit**: ucsim = 1 MC (correct per MCS-51 spec). emu8051 had 3 MC (fixed in `6cb9bc7`). JBC is 1 MC in ucsim (should be 2, no driver uses it).
- **347-image sweep re-run** against fixed emu8051: 2 images reclassified, 0 genuine disagreements. Category 1.
- **steveschnepp/emu8051 fork audit**: bit-addressing fixes are logically equivalent to our code. No ledger impact.
- **Path sweep**: 0 `/mnt/volume1` in tracked files. 22 configure-generated Makefiles untracked.
- **README rewritten**: 4 parts, 8 suites, measurements with categories, what is NOT done.
- **Spec-update convention adopted** (session start scan, not every task).
- **NeoPixel cross-emu**: ran `neo_v3.ihx` through both `stc12_trace` and `emu_trace` (post-CLR/SETB fix `6cb9bc7`). 144 edges compared, max diff 1 ns (clock rounding), all 4 timing windows pass on both. Category 2b → **category 1**. Test: `tests/rung_neopixel_cross.sh`.
- **AVR oracle (in progress)**: ucsim_avr binary works and executes the hand-assembled 6-word blink from `bw-board/test/avr8js-adapter.test.js`. Cycle counts match avr8js exactly: SBI=2, DEC=1, BRNE-taken=2, LDI=1, RJMP=2. Toggle period = 769 cycles = 48062.5 ns at 16 MHz, confirmed 1540 ticks for 2 complete toggles. Test: `tests/rung_avr_blink.sh`. Compiled blink from AVR endpoint loads and toggles PORTB correctly. **Not yet done**: full PORTB trace comparison (word-0 clobber bug requires manual patch), compiled blink cycle-count comparison, disassembler register-name bugs (r24 shown as r0/r5), AT90S vs ATmega328P IO register map difference (IO addresses differ, names wrong, but execution is correct).

## In flight

- **LCD I2C full protocol**: SCL timing is done (v2 in spec). The full I2C START/address/data/STOP edge measurement was blocked by SDCC init taking >100ms. Next step: use `-until-ns 500000000` or longer, or set a breakpoint past init.

## Learned but not in a spec-update

- **stc12_trace build rule**: `Makefile.in` has the `stc12_trace` target but `./configure`'s generated `Makefile` does not propagate it. Must append the rule manually or use `make -f Makefile.in stc12_trace`. This has bitten three people.
- **Bit-write trace visibility**: bit-addressable SFR writes (SETB/CLR on port pins) DO change the byte-level SFR value and ARE visible in the trace shadow comparison — but only if `trace_check_sfr()` runs after the write. The trace sees them fine; the earlier "zero output" on the LCD was SDCC init time, not a trace bug.
- **`-inject` and `-e` are incompatible**: `-e 'run ...'` runs ucsim's internal command loop; `-inject` fires in stc12_trace's own `for(;;) { do_inst(); }` loop controlled by `-until-ns`. spec-updates/017 documents this.

## Blocked

- **Resync e2e**: bw-board owns the test. Unblocked by spec-updates/017 (use `-until-ns` not `-e`). They have the corrected invocation.
- **LCD I2C protocol edges**: needs longer `-until-ns` to get past SDCC init (~100ms). Not architecturally blocked.
- **JBC cycle count**: 1 MC in ucsim, should be 2 per MCS-51 spec. No driver uses JBC. Fix is one `tick(1)` call in `jmp.cc instruction_10`.

## Key files

- `CLOSE-OUT.md` — full campaign results, defects, bench IDs
- `PARITY-GAPS.md` — emitter vs model matrix (11/13 modelled, 31 BW_STUB)
- `RESULTS.md` — detailed methodology and numbers
- `tests/rung_neopixel.sh` — runnable WS2812 spec-window test
- `tests/classify_divergences.sh` — 347-image corpus classifier
- `spec-updates/017-inject-requires-until-ns.md` — the `-inject` / `-e` incompatibility
