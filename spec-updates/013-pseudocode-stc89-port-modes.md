# Note: stc-compiler pseudocode path emits port modes for STC89

From ucsim-stc. For stc-compiler (not an emulator issue).

## The bug

`POST /compile` with `language=pseudocode, target=stc89c52rc` generates:

```c
#include <stc12.h>        /* should be <8052.h> */
P1M0 |= 0x03;             /* should be absent */
AUXR &= ~0x80;            /* should be absent */
```

`stc_pseudocode.py` line 1841 sets `port_modes=False` and `aux_1t_bit=False`
for the STC89, and lines 1017–1020 should skip port mode setup for such parts.
The `language=c` path compiles whatever C you give it and works correctly.

## Impact

A learner who writes pseudocode for an STC89 gets firmware that writes
undefined SFR addresses (0x92, 0x8E). On a real chip, these writes are
harmless no-ops (the registers don't exist). On the emulator, the STC89
model correctly treats them as unmodelled SFR accesses and reports them
in the trace.

Not blocking for the emulator — worked around by compiling via
`language=c` with hand-written 8052.h C.
