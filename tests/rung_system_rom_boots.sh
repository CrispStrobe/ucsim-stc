#!/bin/bash
# rung_system_rom_boots.sh — system ROM boot verification.
#
# Continuously verifies that three system ROMs boot correctly
# under the W65C02 / M6502 / Z80 engines:
#
# 1. Tali Forth 2 (public domain, SamCoVT/TaliForth2):
#    Boots to banner, computes 2 3 + . → 5, compiles : sq dup * ; 7 sq . → 49.
#
# 2. ehBASIC / MS BASIC V1.1 (NC-licensed ROM — never vendored):
#    MEMORY SIZE? → auto-detect → WIDTH? → OK → PRINT 2+3 → 5.
#
# 3. CP/M 2.2 + BBC BASIC (Z80) (Caldera-licensed CP/M, zlib BBC BASIC):
#    Cold boot → A> → DIR lists BBCBASIC.COM → launch → PRINT 2+2 → 4.
#
# All use bw-board engines (read-only reference at /mnt/volume1/code/bw-board).
#
# Usage: ./tests/rung_system_rom_boots.sh
set -e
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
SKIP=0

pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP  $1"; SKIP=$((SKIP+1)); }

BW_BOARD="/mnt/volume1/code/bw-board"

if [ ! -f "$BW_BOARD/src/w65c02.js" ]; then
    echo "SKIP: bw-board not found at $BW_BOARD"
    exit 0
fi

echo ""
echo "=== System ROM boot verification ==="
echo ""

# ── Test 1: Tali Forth 2 ──
TALI_BIN="/mnt/volume1/code/TaliForth2/taliforth-py65mon.bin"
if [ ! -f "$TALI_BIN" ]; then
    skip "Tali Forth 2: binary not found (clone SamCoVT/TaliForth2)"
else
    echo "--- Tali Forth 2 ---"
    OUT=$(cd "$BW_BOARD" && TALI_BIN="$TALI_BIN" node scripts/taliforth-smoke.mjs 2>&1)
    echo "$OUT"

    if echo "$OUT" | grep -q "^ok.*banner"; then
        pass "Tali Forth 2: banner"
    else
        fail "Tali Forth 2: banner"
    fi

    if echo "$OUT" | grep -q "^ok.*arithmetic"; then
        pass "Tali Forth 2: arithmetic (2 3 + . → 5)"
    else
        fail "Tali Forth 2: arithmetic"
    fi

    if echo "$OUT" | grep -q "^ok.*compiling"; then
        pass "Tali Forth 2: compiling (7 sq . → 49)"
    else
        fail "Tali Forth 2: compiling"
    fi

    if echo "$OUT" | grep -q "^ok.*WORDS"; then
        pass "Tali Forth 2: dictionary listing"
    else
        fail "Tali Forth 2: dictionary listing"
    fi
fi

# ── Test 2: ehBASIC (bw-board preset, 32K ROM at $8000) ──
EHBASIC_ROM="/mnt/volume1/code/basic-m6502-bw/basic.bin"
if [ ! -f "$EHBASIC_ROM" ]; then
    skip "ehBASIC: ROM not found (NC-licensed, local build only)"
else
    echo ""
    echo "--- ehBASIC on EATER6502 preset ---"
    # Use inline Node.js with the correct preset (EATER6502, ROM at $8000).
    OUT=$(cd "$BW_BOARD" && node -e "
import { readFileSync } from 'node:fs';
import { M6502Machine, EATER6502 } from './src/m6502-machine.js';

const rom = new Uint8Array(readFileSync('$EHBASIC_ROM'));
const serial = [];
const m = new M6502Machine(EATER6502, {
    onSerial: (b) => serial.push(String.fromCharCode(b)),
});
m.loadRom(rom);
m.reset();

// Phase 1: boot to first prompt.
m.advanceToMs(500);
let tx = serial.join('');
console.log('PHASE1: ' + JSON.stringify(tx.slice(0, 200)));

// Handle [C]old/[W]arm if present — some builds ask, some go straight to MEMORY SIZE.
if (tx.includes('[C]old') || tx.includes('Cold/Warm')) {
    serial.length = 0;
    m.chips.acia1.rxPush(0x43); // 'C'
    m.advanceToMs(m.tMs + 2000);
    tx = serial.join('');
    console.log('PHASE2: ' + JSON.stringify(tx.slice(0, 200)));
}

// Handle MEMORY SIZE? prompt — send CR for auto-detect.
const allTx1 = serial.join('');
if (allTx1.includes('MEMORY SIZE') || allTx1.includes('Memory size')) {
    serial.length = 0;
    m.chips.acia1.rxPush(0x0D);
    m.advanceToMs(m.tMs + 2000);
    tx = serial.join('');
    console.log('MEMSIZE: ' + JSON.stringify(tx.slice(0, 300)));
}

// Handle WIDTH? prompt — send CR for default.
const allTx2 = serial.join('');
if (allTx2.includes('WIDTH')) {
    serial.length = 0;
    m.chips.acia1.rxPush(0x0D);
    m.advanceToMs(m.tMs + 5000);
    tx = serial.join('');
    console.log('WIDTH: ' + JSON.stringify(tx.slice(0, 300)));
}

// Check for Ready/OK prompt and try PRINT.
const finalTx = serial.join('');
if (finalTx.includes('Ready') || finalTx.includes('OK') || finalTx.includes('Bytes Free') || finalTx.includes('Bytes free')) {
    serial.length = 0;
    for (const ch of 'PRINT 2+3\r') m.chips.acia1.rxPush(ch.charCodeAt(0));
    m.advanceToMs(m.tMs + 2000);
    tx = serial.join('');
    console.log('PRINT: ' + JSON.stringify(tx.slice(0, 200)));
}
console.log('CYCLES: ' + m.cycles);
" 2>&1)
    echo "$OUT"

    if echo "$OUT" | grep -qE "MEMORY SIZE|Memory size|\[C\]old"; then
        pass "ehBASIC: boot prompt (MEMORY SIZE? or [C]old)"
    else
        fail "ehBASIC: boot prompt"
    fi

    if echo "$OUT" | grep -qiE "Ready|OK|Bytes Free|Bytes free"; then
        pass "ehBASIC: reached Ready/OK prompt"
    else
        fail "ehBASIC: did not reach Ready prompt"
    fi

    if echo "$OUT" | grep -q "PRINT:" && echo "$OUT" | grep -E "PRINT:.*5" > /dev/null 2>&1; then
        pass "ehBASIC: PRINT 2+3 → 5"
    else
        # If PRINT line exists at all, check it
        PRINT_LINE=$(echo "$OUT" | grep "^PRINT:" || true)
        if [ -n "$PRINT_LINE" ]; then
            if echo "$PRINT_LINE" | grep -q "5"; then
                pass "ehBASIC: PRINT 2+3 → 5"
            else
                fail "ehBASIC: PRINT 2+3 did not yield 5: $PRINT_LINE"
            fi
        else
            skip "ehBASIC: PRINT not attempted (prompt not reached)"
        fi
    fi
fi

# ── Test 3: CP/M 2.2 + BBC BASIC (Z80) ──
CPM_BIN="$BW_BOARD/roms/cpm/cpm22-64k.bin"
BIOS_BIN="$BW_BOARD/roms/cpm/bios.bin"
BBCZ80_COM="${BBCZ80_COM:-$HOME/code/BBCZ80/bin/cpm/BBCBASIC.COM}"
if [ ! -f "$CPM_BIN" ] || [ ! -f "$BIOS_BIN" ]; then
    skip "CP/M: binaries not found in bw-board/roms/cpm/"
elif [ ! -f "$BBCZ80_COM" ]; then
    skip "CP/M: BBCBASIC.COM not found (clone rtrussell/BBCZ80)"
elif [ ! -f "$BW_BOARD/src/z80-machine.js" ]; then
    skip "CP/M: Z80 machine not found in bw-board"
else
    echo ""
    echo "--- CP/M 2.2 + BBC BASIC (Z80) ---"
    OUT=$(cd "$BW_BOARD" && BBCZ80_COM="$BBCZ80_COM" node scripts/cpm-smoke.mjs 2>&1)
    echo "$OUT"

    if echo "$OUT" | grep -q "^ok.*cold boot"; then
        pass "CP/M: cold boot to A>"
    else
        fail "CP/M: cold boot"
    fi

    if echo "$OUT" | grep -q "^ok.*DIR lists"; then
        pass "CP/M: DIR lists BBCBASIC.COM"
    else
        fail "CP/M: DIR"
    fi

    if echo "$OUT" | grep -q "^ok.*BBC BASIC launches"; then
        pass "CP/M: BBC BASIC launches"
    else
        fail "CP/M: BBC BASIC launch"
    fi

    if echo "$OUT" | grep -q "^ok.*PRINT 2+2 produces 4"; then
        pass "CP/M: PRINT 2+2 → 4"
    else
        fail "CP/M: PRINT 2+2"
    fi
fi

# ── Summary ──
echo ""
echo "================================"
echo "System ROM boots: $PASS pass, $FAIL fail, $SKIP skip"
echo "================================"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
