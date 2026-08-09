# Patch for sb3-creator/reference/c-target.md

## Where

The section "The emulator is the test harness for all three" currently
says:

> a recovered program can be validated by *executing* both and comparing
> pin/SFR traces — differential execution as the oracle for decompilation

## Add after it

> **What the oracle catches and what it does not.** The differential trace
> compares observable peripheral behaviour: port writes, timer flags, ADC
> register transitions. A recovered program that produces an identical
> trace is behaviourally correct — it drives the same pins at the same
> times. It may still have the wrong variable layout, different register
> allocation, or a restructured loop, because none of those change what
> the pins do. The oracle proves *behavioural equivalence*, not
> *structural identity*. A decompiler that passes it cannot produce wrong
> hardware behaviour, but it can produce ugly or incorrect pseudocode that
> happens to run the same way.
>
> Measured baseline: the scheduler fixture (318 instructions, 37 SFR+TF
> events over 10 ms) identifies 6 recognisable library patterns by byte
> signature. See `ucsim-stc/RESULTS.md` §"Oracle for the reverse
> direction".
