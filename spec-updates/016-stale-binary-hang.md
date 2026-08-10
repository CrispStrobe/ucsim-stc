# Bug report: stale stc12_trace binary hung for 3 hours on STC89 model

Filed by ucsim-stc against itself.

## The bug

A 347-image corpus sweep launched as a background task ran for 3+ hours
and had to be killed. The hung image was a UART-polling program
(`appleOHseed serial9600`) running under the STC89 (12T) model.

## Root cause

The background task (`bt3p0c893`) was launched BEFORE commit `f42a1fd`
which fixed `tick_hw()` to multiply by `clock_per_cycle()`. The stale
binary accumulated machine cycles instead of oscillator clocks in
`trace_osc_clocks`:

```cpp
// OLD (before f42a1fd):
trace_osc_clocks += cycles;           // wrong on 12T: adds MC, not osc

// FIXED:
trace_osc_clocks += (unsigned long long)cycles * clock_per_cycle();
```

On STC89 (12T), this meant the time check `t_ns > trace_until_ns`
advanced 12× slower, so reaching 2 ms of simulated time required
12× more instructions. For a tight `while(!RI)` polling loop, that
turned seconds into hours.

## Why it looked like a different bug

The process was killed and attributed to "an image that makes the
emulator spin forever." After the binary was rebuilt, the same image
completes in **49 ms**. The real bug was running a stale binary, and
the root cause was the missing `clock_per_cycle()` multiplier — which
was already fixed but not yet rebuilt into the trace binary when the
background task was launched.

## The actual remaining issue

The corpus sweep also had no per-invocation timeout, so one slow
image blocked the entire run with no way to distinguish "stuck" from
"working." Fixed in `corpus_stc12_on_stc89.sh` with `timeout 10`
per invocation and Timeout as a sixth outcome category.

## Lessons

1. Background tasks that use compiled binaries must rebuild first.
   A shell script running `./stc12_trace` gets whatever binary exists
   on disk, not whatever was most recently compiled.
2. A loop without per-invocation timeout looks identical to a loop
   still running when one element hangs. Fixed.
3. The `clock_per_cycle()` fix was load-bearing for the 12T model in
   ways that weren't obvious until a real corpus exercised it.
