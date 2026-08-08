# ADC_START clear timing

**Proposed update to STC12-PERIPHERAL-MODEL.md §4**

## Issue

The spec does not state when `ADC_START` (bit 3 of `ADC_CONTR`) is
cleared by hardware.  Two interpretations:

1. Cleared immediately on write (before the conversion runs)
2. Cleared when the conversion completes (together with `ADC_FLAG` being set)

## Resolution

**Option 2: cleared at conversion completion.**

Datasheet §10.3 says "ADC_START is automatically cleared by hardware
when the conversion is done."  emu8051-stc implements this
(stc12.c line 476).  ucsim-stc initially implemented option 1 and
the divergence was caught by differential execution (diff_test.sh on
the generateC scheduler image).

## Evidence

Differential execution of `scheduled_gen.ihx` (generateC output with
ADC reads):

- With option 1: ucsim emits `SFR BC E3` (START already cleared)
  while emu8051 emits `SFR BC EB` (START still set).  **Divergence.**
- With option 2: both emit `SFR BC EB` then `SFR BC F3` (FLAG set,
  START still set) then `SFR BC E3` (software clears FLAG, hardware
  cleared START).  **Identical.**

## What should change in the spec

Add to §4, after the `ADC_FLAG` paragraph:

> `ADC_START` (bit 3) is cleared by hardware when the conversion
> completes — at the same time `ADC_FLAG` is set.  It is NOT cleared
> on write.  Both emu8051-stc and ucsim-stc implement this; the
> behaviour was validated by differential execution.
