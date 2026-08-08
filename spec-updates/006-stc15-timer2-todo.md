# STC15 Timer 2 — noted, not yet implemented

## What

The STC15 replaces the STC12's BRT (dedicated baud-rate timer,
0x9C, 8-bit) with Timer 2 (T2H/T2L at 0xD6/0xD7, 16-bit
auto-reload). Controlled by AUXR bits 4 (T2R), 3 (T2_C/T),
2 (T2x12).

## Why it's deferred

The generated code (from generateC) uses Timer 0 for the
cooperative scheduler tick. Timer 2 / BRT is for UART baud rate
generation, which is out of scope per STC12-PERIPHERAL-MODEL.md §8.

No test image in the corpus or in our fixtures uses Timer 2.

## When to implement

When the on-chip monitor (src/10-live-firmware) needs UART2
at a specific baud rate, or when a test image requires it.
emu8051-stc already has it (commit 5029523).

## What it requires

A new cl_timer2_stc15 class with:
- 16-bit auto-reload from T2H/T2L
- 1T/12T prescaler via AUXR.T2x12 (same pattern as timer0/1)
- Overflow can be selected as UART1 baud source via AUXR.S1ST2
