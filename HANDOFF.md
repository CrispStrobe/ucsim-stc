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

## In flight

- **NeoPixel cross-emu**: the ledger (`stc 844966a`) notes this is the cheapest open move — emu8051's CLR/SETB fix means the two emulators should now agree on WS2812 timing. Was about to start when context saturated. Next step: compile `neo_v3.ihx` equivalent for emu8051, run through `emu_trace`, compare T0H/T1H/T0L/T1L. If they agree, row moves from cat 3 to cat 1.
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
