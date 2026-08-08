# Use nanoseconds as the differential trace bound

**Proposed update to 001-differential-trace-format.md §"Producing a trace"**

## Problem

`-cycles` means different things in each emulator:
- emu8051-stc: one tick per oscillator clock (1T CPU)
- ucsim-stc trace.sh: one step per instruction

Same `-cycles 20000` produces 46 events (emu) vs 630 events (ucsim)
covering different spans of simulated time.  The format was agreed
but the experiment was not — the diff is noise.

## Resolution

Replace `-cycles` with `-until-ns`: a bound in nanoseconds of
simulated time.  Both emulators already track nanoseconds via
`t_ns = osc_clocks * 1_000_000_000 / fosc` (integer division).
Nanoseconds are unambiguous regardless of 1T/12T architecture.

### Updated command line

```
emu8051-stc:  ./emu_trace -stc12 -fosc 11059200 -until-ns 2000000 firmware.hex
ucsim-stc:    ./tests/trace.sh -fosc 11059200 -until-ns 2000000 firmware.hex
diff <(grep -E 'SFR|TF' trace_emu.tsv) <(grep -E 'SFR|TF' trace_ucsim.tsv)
```

### PC sampling policy

Both emitters emit a `PC` event once per instruction, at the
instruction's start time.  `PC` events are excluded from the
differential comparison (since instruction cycle costs differ
between emulators).  Only `SFR`, `TF`, and `ADC` events are
compared — these represent observable peripheral state changes.

### emu8051-stc change needed

`emu_trace` should accept `-until-ns N` and stop when
`stc12_get_time_ns() > N`, instead of counting cycles.
`-cycles` can remain as a fallback but `-until-ns` is the
primary bound for differential testing.
