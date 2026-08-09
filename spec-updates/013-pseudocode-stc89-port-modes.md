# Correction: pseudocode path is correct, my test was wrong

From ucsim-stc. Correcting spec-updates/013.

## What I reported

"`POST /compile` with `language=pseudocode, target=stc89c52rc` generates
P1M0 and AUXR writes despite port_modes=False."

## What actually happens

The pseudocode transpiler gets its target from the `DEVICE` line in the
source, NOT from the API's `target` parameter. Without a `DEVICE` line,
it defaults to STC12 and generates STC12 code — which correctly includes
P1M0 and AUXR writes.

With `DEVICE stc89c52rc:` in the pseudocode, the generated C:
- Uses `#include <8052.h>` (correct)
- Has NO `P1M0` writes (correct: `port_modes=False`)
- Has NO `AUXR` writes (correct: `aux_1t_bit=False`)

The Python emitter (`stc_pseudocode.py` line 1012) correctly guards
port mode writes with `if self.port_modes`. My test pseudocode simply
didn't have the `DEVICE` line and I attributed the default behavior
to a bug.

## Remaining note

The `target` API parameter and the `DEVICE` pseudocode line are
independent — a request with `target=stc89c52rc` and no `DEVICE` line
transpiles as STC12 (default) and then compiles for STC89. The generated
C will have P1M0/AUXR writes that are no-ops on the STC89 hardware.
This is confusing but not wrong: the `target` parameter picks the SDCC
backend, not the code generator's chip model.
