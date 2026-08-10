# STC15 Timer 2 — IMPLEMENTED

Implemented in commit `6587b3c`. 16-bit auto-reload timer at
T2H/T2L (0xD6/0xD7), controlled by AUXR bits 4 (T2R) and 2 (T2x12).
Only active when `-t STC15` is selected.

Smoke-tested: 24 ticks at 12T → T2L=2 (correct).
STC12 model correctly does NOT have Timer 2.
