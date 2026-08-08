# Symbol table input format for debug targets

**Proposed shared format consumed by both ucsim-stc and emu8051-stc.**

## Purpose

Both emulators need the addresses of `bw_ms`, `<task>_state`,
`<task>_until` and a `(task, state) → source block` mapping to
implement Level 1 position (§2) and yield breakpoints (§5).

Neither emulator writes a `.cdb` parser.  Both take a symbol table
as input.  This format is produced by `stc-compiler` / `sb3-creator`
from SDCC's `.cdb` and `.map` files.

## Format

JSON, one object.  Example for the SCHEDULED fixture:

```json
{
  "fosc": 11059200,
  "device": "stc12c5a60s2",
  "scheduler": {
    "bw_ms": {"space": "iram", "addr": 8, "size": 2},
    "tasks": [
      {
        "name": "bw_task0",
        "func_addr": 285,
        "state": {"space": "iram", "addr": 14, "size": 2},
        "until": {"space": "iram", "addr": 16, "size": 2},
        "yields": [
          {"state": 0, "label": "entry"},
          {"state": 1, "label": "forever_top", "addr": 295},
          {"state": 2, "label": "repeat_top", "addr": 301},
          {"state": 3, "label": "wait_150ms", "addr": 310}
        ]
      },
      {
        "name": "bw_task1",
        "func_addr": 429,
        "state": {"space": "iram", "addr": 18, "size": 2},
        "until": {"space": "iram", "addr": 20, "size": 2},
        "yields": [
          {"state": 0, "label": "entry"},
          {"state": 1, "label": "wait_until_button", "addr": 440},
          {"state": 2, "label": "forever_top", "addr": 455},
          {"state": 3, "label": "wait_50ms", "addr": 490}
        ]
      }
    ]
  }
}
```

## Field definitions

- `fosc`: oscillator frequency in Hz.
- `device`: target device, lowercase.
- `scheduler.bw_ms`: location of the millisecond tick counter.
- `tasks[].name`: C function name.
- `tasks[].func_addr`: code address of the function entry.
- `tasks[].state`: location of `<task>_state` variable.
- `tasks[].until`: location of `<task>_until` variable.
- `tasks[].yields[]`: the Duff's-device case labels.
  - `state`: the case number (0 = entry, 0xFFFF = ended).
  - `label`: human-readable name (for UI display).
  - `addr`: code address of the case label (for code breakpoints).

The `addr` field on yields is what §5 calls "the code address of
that case label".  Both emulators use this for yield breakpoints,
ensuring they halt at the same instruction.

## Where the addresses come from

SDCC's `.cdb` file, `L:` lines:
```
L:Fmodule$bw_ms$0_0$0:8           → bw_ms at iram 0x08
L:Fmodule$bw_task0_state$0_0$0:E  → task0_state at iram 0x0E
L:Fmodule$bw_task0$0$0:11D        → task0 func at code 0x011D
```

The yield `addr` values come from the `.lst` file by matching
`case N:` labels, or from the emitter which knows the case numbers.

## What produces this file

`stc-compiler` or `sb3-creator`, not either emulator.  The emulators
consume it via a `-symbols file.json` command-line flag.
