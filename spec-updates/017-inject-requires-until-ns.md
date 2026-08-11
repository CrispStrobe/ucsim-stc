# `-inject` requires `-until-ns`, not `-e 'run ...'`

From ucsim-stc. For bw-board (resync-inconclusive resolution).

## Root cause

`-inject` fires inside `stc12_trace`'s own `for(;;) { do_inst(); }`
loop, which is controlled by `-until-ns`. The `-e 'run N'` flag
passes a command to ucsim's interactive interpreter, which has its
own execution loop that never calls the inject code.

Confirmed:
- Without `-e`: inject fires at the scheduled time, RI rises ~83 µs later
- With `-e 'run ...'`: inject never executes, 0 bytes received

## Correct usage

```bash
stc12_trace -t STC12 -fosc 11059200 -until-ns 100000000 \
    -inject 10000000,0x7E \
    -inject 10100000,0x01 \
    -inject 10200000,0x00 \
    -inject 10300000,0xFE \
    firmware.hex
```

Do NOT combine `-inject` with `-e`. They use different execution
loops and `-e` runs before `stc12_trace`'s own loop starts.

## What this resolves

bw-board's `resync-inconclusive.md`: the INCONCLUSIVE was caused
by using `-e 'run ...'` which bypassed the inject. The inject path
itself works — `inject_byte` sets `input_avail`, `serial.tick()`
starts receiving, RI rises after one frame time.

## What remains to test

With the correct invocation, does the firmware:
1. See RI rise (check SCON bit 0)
2. Read SBUF (the injected byte)
3. Process the HELLO frame
4. Produce TX output (TI + SBUF writes)

That test is writable now with `-until-ns` instead of `-e`.
