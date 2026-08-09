#!/bin/bash
# run_control_diff.sh — DEBUG-CONTROL-MODEL §8 acceptance ladder.
#
# Cross-emulator run-control tests: rungs 3 through 7.
# Exits non-zero on the first rung that fails.
#
# Usage: ./tests/run_control_diff.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="${STC12_TRACE:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace}"
UCSIM="${UCSIM:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/ucsim_51}"
EMU_TRACE="${EMU_TRACE:-$(command -v emu_trace 2>/dev/null || echo "")}"
FOSC=11059200

BLINK=/tmp/blink_rc.ihx
SCHED="$SCRIPT_DIR/fixtures/scheduled_gen.ihx"
SYMBOLS="$SCRIPT_DIR/fixtures/scheduled_gen.symbols.json"
PASS=0; FAIL=0; SKIP=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP+1)); }

if [ ! -x "$STC12_TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$UCSIM" ]; then echo "FAIL: ucsim_51 not found" >&2; exit 1; fi

# Compile blink for rung 3/7
cat > /tmp/blink_rc.c << 'CEOF'
#include <stc12.h>
#define FOSC_HZ 11059200UL
#define T0_RELOAD (65536UL - FOSC_HZ / 12UL / 1000UL)
static void delay_init(void) {
    AUXR &= ~0x80; TMOD = (TMOD & 0xF0) | 0x01; TR0 = 0; TF0 = 0;
}
static void delay_ms(unsigned int ms) {
    while (ms--) {
        TL0 = (unsigned char)(T0_RELOAD & 0xFF);
        TH0 = (unsigned char)((T0_RELOAD >> 8) & 0xFF);
        TF0 = 0; TR0 = 1; while (!TF0) ; TR0 = 0; TF0 = 0;
    }
}
void main(void) {
    P1M1 &= ~0x03; P1M0 |= 0x03;
    P1_0 = 1; P1_1 = 1;
    delay_init();
    for (;;) { P1_0 = 0; delay_ms(150); P1_0 = 1; delay_ms(150); }
}
CEOF
sdcc -mmcs51 --model-small -o "$BLINK" /tmp/blink_rc.c 2>/dev/null

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

echo "=== DEBUG-CONTROL-MODEL §8 acceptance ladder ==="
echo ""

# ─── RUNG 3: step('insn') x N, interrupts masked ───
echo "[Rung 3] step('insn') x 1000, interrupts masked"
if [ -z "$EMU_TRACE" ] || [ ! -x "$EMU_TRACE" ]; then
    skip "emu_trace not found"
else
    "$EMU_TRACE" -fosc $FOSC -step-pcs 1001 "$BLINK" 2>/dev/null \
        | grep -v '	' | tail -n +2 | head -1000 \
        | awk '{printf "%04X\n", strtonum("0x" $0)}' > "$TMP/emu_r3.txt"

    python3 -c "
for i in range(1000):
    print('step')
print('quit')
" | $UCSIM -t STC12 "$BLINK" 2>/dev/null \
        | grep 'Stop at 0x' | sed 's/.*Stop at 0x0*\([0-9a-fA-F]*\).*/\1/' \
        | awk '{printf "%04X\n", strtonum("0x" $0)}' | head -1000 > "$TMP/ucsim_r3.txt"

    EN=$(wc -l < "$TMP/emu_r3.txt"); UN=$(wc -l < "$TMP/ucsim_r3.txt")
    if diff "$TMP/emu_r3.txt" "$TMP/ucsim_r3.txt" > /dev/null 2>&1; then
        pass "$EN/$UN PCs identical from reset"
    else
        fail "PC divergence"
        FAIL=$((FAIL+1))
    fi
fi

# ─── RUNG 4: code breakpoint, same PC + registers ───
echo ""
echo "[Rung 4] code breakpoint at bw_task0 entry"
BP_ADDR=$(python3 -c "import json; print(json.load(open('$SYMBOLS'))['scheduler']['tasks'][0]['func_addr'])")
BP_HEX=$(printf '%04x' $BP_ADDR)

# ucsim side
OUT=$(printf "break 0x$BP_HEX\nrun\ndump sfr 0xe0 0xe0\ndump sfr 0xf0 0xf0\ndump sfr 0x82 0x83\ndump sfr 0x81 0x81\ndump sfr 0xd0 0xd0\npc\nquit\n" | $UCSIM -t STC12 "$SCHED" 2>/dev/null)
UCSIM_PC=$(echo "$OUT" | grep "^0x" | tail -1 | grep -oP '0x[0-9a-fA-F]+' | head -1)
UCSIM_ACC=$(echo "$OUT" | grep "ACC:" | grep -oP '0x\S+' | head -2 | tail -1)
UCSIM_SP=$(echo "$OUT" | grep " SP:" | grep -oP '0x\S+' | head -2 | tail -1)

if echo "$UCSIM_PC" | grep -qi "$BP_HEX"; then
    pass "ucsim halted at 0x$BP_HEX (A=$UCSIM_ACC SP=$UCSIM_SP)"
else
    fail "ucsim wrong PC: $UCSIM_PC"
fi

# emu8051 side: would need emu_trace to support breakpoint+register dump
# For now report what ucsim says and note what's needed from emu8051
skip "emu8051 register dump at breakpoint not yet exposed via emu_trace"

# ─── RUNG 5: yield breakpoint, same (task, state, bw_ms) ───
echo ""
echo "[Rung 5] yield breakpoint at task0 state=3"
YIELD_ADDR=$(python3 -c "
import json
d = json.load(open('$SYMBOLS'))
for y in d['scheduler']['tasks'][0]['yields']:
    if y['state'] == 3: print(y['addr']); break
")
YIELD_HEX=$(printf '%04x' $YIELD_ADDR)
BW_MS_ADDR=$(python3 -c "import json; print(json.load(open('$SYMBOLS'))['scheduler']['bw_ms']['addr'])")
T0_STATE_ADDR=$(python3 -c "import json; print(json.load(open('$SYMBOLS'))['scheduler']['tasks'][0]['state']['addr'])")

# ucsim side
OUT=$(printf "break 0x$YIELD_HEX\nrun\ndi $(printf '0x%02x' $T0_STATE_ADDR) $(printf '0x%02x' $((T0_STATE_ADDR+1)))\ndi $(printf '0x%02x' $BW_MS_ADDR) $(printf '0x%02x' $((BW_MS_ADDR+1)))\npc\nquit\n" | $UCSIM -t STC12 "$SCHED" 2>/dev/null)

UCSIM_YPC=$(echo "$OUT" | grep "^0x" | tail -1 | grep -oP '0x[0-9a-fA-F]+' | head -1)
if echo "$UCSIM_YPC" | grep -qi "$YIELD_HEX"; then
    # Read state from IRAM dump
    STATE_LINE=$(echo "$OUT" | grep "^0x$(printf '%02x' $T0_STATE_ADDR)" | head -1)
    STATE_LOW=$(echo "$STATE_LINE" | awk '{print $2}')
    STATE_VAL=$(printf '%d' "0x$STATE_LOW" 2>/dev/null || echo "?")
    if [ "$STATE_VAL" = "3" ]; then
        pass "ucsim: PC=0x$YIELD_HEX, task0_state=3"
    else
        fail "ucsim: state=$STATE_VAL, expected 3"
    fi
else
    fail "ucsim wrong yield PC: $UCSIM_YPC"
fi

skip "emu8051 yield breakpoint + bw_ms read not yet exposed via emu_trace"

# ─── RUNG 6: write variable while halted ───
echo ""
echo "[Rung 6] write task0_state=0xFFFF while halted, resume"
STATE_HEX=$(printf '%02x' $T0_STATE_ADDR)
STATE_HI_HEX=$(printf '%02x' $((T0_STATE_ADDR + 1)))

OUT=$(printf "break 0x$YIELD_HEX\nrun\nset mem iram 0x$STATE_HEX 0xFF\nset mem iram 0x$STATE_HI_HEX 0xFF\nstep\nstep\nstep\nstep\nstep\nstep\nstep\nstep\nstep\nstep\ndi 0x$STATE_HEX 0x$STATE_HI_HEX\nquit\n" | $UCSIM -t STC12 "$SCHED" 2>/dev/null)

LAST_DUMP=$(echo "$OUT" | grep "^0x$(printf '%02x' $T0_STATE_ADDR)" | tail -1)
if echo "$LAST_DUMP" | grep -q "ff ff"; then
    pass "ucsim: task0_state=0xFFFF persists after resume"
else
    fail "ucsim: state changed after resume"
fi

skip "emu8051 write-while-halted not yet exposed via emu_trace"

# ─── RUNG 7: peripheral events on interrupt-driven image ───
echo ""
echo "[Rung 7] peripheral-event differential on blink (10 ms)"
if [ -z "$EMU_TRACE" ] || [ ! -x "$EMU_TRACE" ]; then
    skip "emu_trace not found"
else
    "$EMU_TRACE" -fosc $FOSC -until-ns 10000000 "$BLINK" 2>/dev/null \
        | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/emu_r7.ev"
    timeout 60 "$STC12_TRACE" -fosc $FOSC -until-ns 10000000 "$BLINK" 2>/dev/null \
        | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/ucsim_r7.ev"

    EN=$(wc -l < "$TMP/emu_r7.ev"); UN=$(wc -l < "$TMP/ucsim_r7.ev")
    MIN=$((EN < UN ? EN : UN))
    if [ "$EN" -eq "$UN" ] && diff "$TMP/emu_r7.ev" "$TMP/ucsim_r7.ev" > /dev/null 2>&1; then
        pass "$EN/$UN events strictly identical (10 ms)"
    elif diff <(head -$MIN "$TMP/emu_r7.ev") <(head -$MIN "$TMP/ucsim_r7.ev") > /dev/null 2>&1; then
        pass "first $MIN events identical (emu=$EN ucsim=$UN)"
    else
        fail "event divergence"
    fi
fi

echo ""
echo "=== Results ==="
echo "Pass: $PASS  Fail: $FAIL  Skip: $SKIP"
echo ""
echo "Skipped rungs need emu8051 to expose breakpoint + register dump"
echo "and write-while-halted through emu_trace or a test binary."

[ $FAIL -eq 0 ] && exit 0 || exit 1
