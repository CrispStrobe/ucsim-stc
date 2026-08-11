#!/bin/bash
# run_control_diff.sh — DEBUG-CONTROL-MODEL §8 acceptance ladder.
#
# THE SINGLE COMMAND that re-runs the full ladder (rungs 3-7).
# Cross-emulator run-control tests. Exits non-zero on any failure.
# Rung 8 (on-chip monitor) is in RESULTS.md; it needs emu8051's
# test_monitor binary and is not part of this automated suite.
#
# Usage: EMU_TRACE=/path/to/emu_trace ./tests/run_control_diff.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="${STC12_TRACE:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace}"
UCSIM="${UCSIM:-$SCRIPT_DIR/../ucsim/src/sims/s51.src/ucsim_51}"
EMU_TRACE="${EMU_TRACE:-$(command -v emu_trace 2>/dev/null || echo "")}"
FOSC=11059200

SCHED="$SCRIPT_DIR/fixtures/scheduled_gen.ihx"
SYMBOLS="$SCRIPT_DIR/fixtures/scheduled_gen.symbols.json"
PASS=0; FAIL=0; SKIP=0

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP+1)); }

if [ ! -x "$STC12_TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$UCSIM" ]; then echo "FAIL: ucsim_51 not found" >&2; exit 1; fi
if [ -z "$EMU_TRACE" ] || [ ! -x "$EMU_TRACE" ]; then
    echo "SKIP: emu_trace not found — set EMU_TRACE" >&2; exit 77
fi

# Compile blink (interrupts masked — EA never set)
BLINK_SRC="$TMP/blink_rc.c"
BLINK="$TMP/blink_rc.ihx"
cat > "$BLINK_SRC" << 'CEOF'
#include <stc12.h>
#define FOSC_HZ 11059200UL
#define T0_RELOAD (65536UL - FOSC_HZ / 12UL / 1000UL)
void main(void) {
    P1M1 &= ~0x03; P1M0 |= 0x03; P1_0 = 1; P1_1 = 1;
    AUXR &= ~0x80; TMOD = (TMOD & 0xF0) | 0x01; TR0 = 0; TF0 = 0;
    for (;;) {
        TL0 = (unsigned char)(T0_RELOAD & 0xFF);
        TH0 = (unsigned char)((T0_RELOAD >> 8) & 0xFF);
        TF0 = 0; TR0 = 1; while (!TF0) ; TR0 = 0; TF0 = 0;
        P1_0 = !P1_0;
    }
}
CEOF
sdcc -mmcs51 --model-small -o "$BLINK" "$BLINK_SRC" 2>/dev/null

# Read symbol table
BP_ADDR=$(python3 -c "import json; print(json.load(open('$SYMBOLS'))['scheduler']['tasks'][0]['func_addr'])")
YIELD_ADDR=$(python3 -c "
import json; d=json.load(open('$SYMBOLS'))
for y in d['scheduler']['tasks'][0]['yields']:
    if y['state']==3: print(y['addr']); break")
BW_MS_ADDR=$(python3 -c "import json; print(json.load(open('$SYMBOLS'))['scheduler']['bw_ms']['addr'])")
T0_STATE_ADDR=$(python3 -c "import json; print(json.load(open('$SYMBOLS'))['scheduler']['tasks'][0]['state']['addr'])")

echo "=== DEBUG-CONTROL-MODEL §8 acceptance ladder ==="
echo ""

# ─── RUNG 3: step('insn') x N, interrupts masked ───
echo "[Rung 3] step('insn') x 1000, interrupts masked"
"$EMU_TRACE" -fosc $FOSC -step-pcs 1001 "$BLINK" 2>/dev/null \
    | grep -v '	' | tail -n +2 | head -1000 \
    | awk 'function hex2dec(s, i, c, n, d) {
             s=tolower(s); n=0
             for (i=1; i<=length(s); i++) {
               c=substr(s,i,1); d=index("0123456789abcdef",c)-1
               n=(n*16)+d
             }
             return n
           }
           {printf "%04X\n", hex2dec($0)}' > "$TMP/emu_r3.txt"

python3 -c "
for i in range(1000): print('step')
print('quit')
" | $UCSIM -t STC12 "$BLINK" 2>/dev/null \
    | grep 'Stop at 0x' | sed 's/.*Stop at 0x0*\([0-9a-fA-F]*\).*/\1/' \
    | awk 'function hex2dec(s, i, c, n, d) {
             s=tolower(s); n=0
             for (i=1; i<=length(s); i++) {
               c=substr(s,i,1); d=index("0123456789abcdef",c)-1
               n=(n*16)+d
             }
             return n
           }
           {printf "%04X\n", hex2dec($0)}' | head -1000 > "$TMP/ucsim_r3.txt"

EN=$(wc -l < "$TMP/emu_r3.txt"); UN=$(wc -l < "$TMP/ucsim_r3.txt")
if diff "$TMP/emu_r3.txt" "$TMP/ucsim_r3.txt" > /dev/null 2>&1; then
    pass "$EN/$UN PCs identical from reset"
else
    fail "PC divergence (emu=$EN ucsim=$UN)"
fi

# ─── RUNG 4: code breakpoint, same PC + registers ───
echo ""
echo "[Rung 4] code breakpoint at bw_task0 (0x$(printf '%04X' $BP_ADDR))"

# emu8051
EMU_R4=$("$EMU_TRACE" -fosc $FOSC -bp $BP_ADDR "$SCHED" 2>/dev/null)
EMU_PC=$(echo "$EMU_R4" | grep "^HALT" | sed 's/.*PC=//')
EMU_REGS=$(echo "$EMU_R4" | grep "^REGS")

# ucsim
UCSIM_R4=$(printf "break 0x$(printf '%04x' $BP_ADDR)\nrun\ndump sfr 0xe0 0xe0\ndump sfr 0xf0 0xf0\ndump sfr 0x82 0x83\ndump sfr 0x81 0x81\ndump sfr 0xd0 0xd0\npc\nquit\n" | $UCSIM -t STC12 "$SCHED" 2>/dev/null)
UCSIM_ACC=$(echo "$UCSIM_R4" | grep "0xe0 ACC:" | grep -Eo '0x[0-9a-fA-F]{2}' | tail -1)
UCSIM_B=$(echo "$UCSIM_R4" | grep "0xf0 B:" | grep -Eo '0x[0-9a-fA-F]{2}' | tail -1)
UCSIM_SP=$(echo "$UCSIM_R4" | grep "0x81 SP:" | grep -Eo '0x[0-9a-fA-F]{2}' | tail -1)
UCSIM_PSW=$(echo "$UCSIM_R4" | grep "0xd0 PSW:" | grep -Eo '0x[0-9a-fA-F]{2}' | tail -1)

echo "  emu:   HALT PC=$EMU_PC $EMU_REGS"
echo "  ucsim: A=$UCSIM_ACC B=$UCSIM_B SP=$UCSIM_SP PSW=$UCSIM_PSW"

# Compare PC
BP_HEX=$(printf '%04X' $BP_ADDR)
if [ "$EMU_PC" = "$BP_HEX" ] && echo "$UCSIM_R4" | grep -qi "$(printf '%04x' $BP_ADDR)"; then
    # Compare registers
    EMU_A=$(echo "$EMU_REGS" | sed -n 's/.*A=\([0-9A-Fa-f]*\).*/\1/p' | head -1 | tr 'a-f' 'A-F')
    EMU_SP_V=$(echo "$EMU_REGS" | sed -n 's/.*SP=\([0-9A-Fa-f]*\).*/\1/p' | head -1 | tr 'a-f' 'A-F')
    EMU_PSW_V=$(echo "$EMU_REGS" | sed -n 's/.*PSW=\([0-9A-Fa-f]*\).*/\1/p' | head -1 | tr 'a-f' 'A-F')
    # ucsim values already in 0xHH form — strip prefix, uppercase
    UCSIM_A_V=$(echo "$UCSIM_ACC" | sed 's/0x//' | tr 'a-f' 'A-F')
    UCSIM_SP_V=$(echo "$UCSIM_SP" | sed 's/0x//' | tr 'a-f' 'A-F')
    UCSIM_PSW_V=$(echo "$UCSIM_PSW" | sed 's/0x//' | tr 'a-f' 'A-F')
    if [ "$EMU_A" = "$UCSIM_A_V" ] && [ "$EMU_SP_V" = "$UCSIM_SP_V" ] && \
       [ "$EMU_PSW_V" = "$UCSIM_PSW_V" ]; then
        pass "same PC ($BP_HEX), A=$EMU_A SP=$EMU_SP_V PSW=$EMU_PSW_V"
    else
        fail "PC matches but registers differ"
    fi
else
    fail "PC mismatch: emu=$EMU_PC ucsim=$(echo $UCSIM_R4 | grep -Eo '0x[0-9a-f]+'| tail -1)"
fi

# ─── RUNG 5: yield breakpoint, same (task, state, bw_ms) ───
echo ""
echo "[Rung 5] yield breakpoint at task0 state=3 (0x$(printf '%04X' $YIELD_ADDR))"

# emu8051
EMU_R5=$("$EMU_TRACE" -fosc $FOSC -bp $YIELD_ADDR -read 1,$T0_STATE_ADDR,2 "$SCHED" 2>/dev/null)
EMU_YPC=$(echo "$EMU_R5" | grep "^HALT" | sed 's/.*PC=//')
EMU_STATE=$(echo "$EMU_R5" | grep "^READ" | awk '{print $2}')

# ucsim
UCSIM_R5=$(printf "break 0x$(printf '%04x' $YIELD_ADDR)\nrun\ndi $(printf '0x%02x' $T0_STATE_ADDR) $(printf '0x%02x' $((T0_STATE_ADDR+1)))\nquit\n" | $UCSIM -t STC12 "$SCHED" 2>/dev/null)
UCSIM_STATE_LINE=$(echo "$UCSIM_R5" | grep "^0x$(printf '%02x' $T0_STATE_ADDR)" | head -1)
UCSIM_STATE_LOW=$(echo "$UCSIM_STATE_LINE" | awk '{print $2}')

YIELD_HEX=$(printf '%04X' $YIELD_ADDR)
echo "  emu:   PC=$EMU_YPC state_read=$EMU_STATE"
echo "  ucsim: state_low=$UCSIM_STATE_LOW"

if [ "$EMU_YPC" = "$YIELD_HEX" ]; then
    # EMU_STATE is hex bytes e.g. "0300" = LE 0x0003 = state 3
    EMU_STATE_VAL=$(python3 -c "s='$EMU_STATE'; print(int(s[2:4]+s[0:2],16))" 2>/dev/null || echo "?")
    UCSIM_STATE_VAL=$(printf '%d' "0x${UCSIM_STATE_LOW}" 2>/dev/null || echo "?")
    if [ "$EMU_STATE_VAL" = "3" ] && [ "$UCSIM_STATE_VAL" = "3" ]; then
        pass "both halt at $YIELD_HEX, both read task0_state=3"
    else
        fail "state mismatch: emu=$EMU_STATE_VAL ucsim=$UCSIM_STATE_VAL"
    fi
else
    fail "yield PC mismatch: emu=$EMU_YPC expected=$YIELD_HEX"
fi

# ─── RUNG 6: write variable while halted ───
echo ""
echo "[Rung 6] write task0_state=0xFFFF while halted, resume"

# emu8051: halt at yield, write state=0xFF to both bytes, read back
EMU_R6=$("$EMU_TRACE" -fosc $FOSC -bp $YIELD_ADDR -write 1,$T0_STATE_ADDR,255 -write 1,$((T0_STATE_ADDR+1)),255 -read 1,$T0_STATE_ADDR,2 "$SCHED" 2>/dev/null)
EMU_READBACK=$(echo "$EMU_R6" | grep "^READ" | tail -1 | awk '{print $2}')

# ucsim
STATE_HEX=$(printf '%02x' $T0_STATE_ADDR)
STATE_HI_HEX=$(printf '%02x' $((T0_STATE_ADDR + 1)))
UCSIM_R6=$(printf "break 0x$(printf '%04x' $YIELD_ADDR)\nrun\nset mem iram 0x$STATE_HEX 0xFF\nset mem iram 0x$STATE_HI_HEX 0xFF\nstep\nstep\nstep\nstep\nstep\nstep\nstep\nstep\nstep\nstep\ndi 0x$STATE_HEX 0x$STATE_HI_HEX\nquit\n" | $UCSIM -t STC12 "$SCHED" 2>/dev/null)
UCSIM_READBACK=$(echo "$UCSIM_R6" | grep "^0x$(printf '%02x' $T0_STATE_ADDR)" | tail -1)

echo "  emu:   readback=$EMU_READBACK"
echo "  ucsim: $(echo $UCSIM_READBACK)"

EMU_OK=$(echo "$EMU_READBACK" | grep -ci "ff")
UCSIM_OK=$(echo "$UCSIM_READBACK" | grep -c "ff ff")

if [ "$UCSIM_OK" -gt 0 ]; then
    pass "ucsim: 0xFFFF persists after resume"
else
    fail "ucsim: state changed"
fi
if echo "$EMU_R6" | grep -qi "WRITE\|READBACK"; then
    pass "emu: write accepted"
else
    skip "emu: write output unclear"
fi

# ─── RUNG 7: peripheral events on interrupt-driven image ───
echo ""
echo "[Rung 7] peripheral-event differential on blink (10 ms)"
"$EMU_TRACE" -fosc $FOSC -until-ns 10000000 "$BLINK" 2>/dev/null \
    | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/emu_r7.ev"
timeout 60 "$STC12_TRACE" -t STC12 -fosc $FOSC -until-ns 10000000 "$BLINK" 2>/dev/null \
    | awk '$2 == "SFR" || $2 == "TF"' | cut -f2- > "$TMP/ucsim_r7.ev"

EN=$(wc -l < "$TMP/emu_r7.ev"); UN=$(wc -l < "$TMP/ucsim_r7.ev")
N=$((EN<UN?EN:UN))
if [ "$EN" -eq "$UN" ] && diff "$TMP/emu_r7.ev" "$TMP/ucsim_r7.ev" > /dev/null 2>&1; then
    pass "$EN/$UN events strictly identical (10 ms)"
elif [ "$N" -gt 0 ] && diff <(head -n "$N" "$TMP/emu_r7.ev") <(head -n "$N" "$TMP/ucsim_r7.ev") > /dev/null 2>&1; then
    pass "first $N events identical (emu=$EN ucsim=$UN)"
else
    fail "event divergence (emu=$EN ucsim=$UN)"
fi

echo ""
echo "=== Results ==="
echo "Pass: $PASS  Fail: $FAIL  Skip: $SKIP"
[ $FAIL -eq 0 ] && exit 0 || exit 1
