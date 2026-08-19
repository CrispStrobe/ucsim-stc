#!/bin/bash
# rung_matrix8x8_bcm_golden.sh — MATRIX8X8 BCM 4-level brightness golden trace.
#
# Verifies the 3-phase bit-plane render (BCM) produces the correct
# column port byte per row per phase, absolute and byte/pin-exact
# across both emulators.
#
# Test pattern: rows 0-3 at brightness levels 3, 2, 1, 0.
#
# BCM phase render (P0 = ~bw_lit, active-low columns):
#   Phase 0 (p0|p1): row0=00 row1=00 row2=00 row3=FF rows4-7=FF
#   Phase 1 (p1):    row0=00 row1=00 row2=FF row3=FF rows4-7=FF
#   Phase 2 (p0&p1): row0=00 row1=FF row2=FF row3=FF rows4-7=FF
#
# Duty per row: row0=3/3 (full), row1=2/3, row2=1/3, row3=0/3 (off)
#
# Usage: ./tests/rung_matrix8x8_bcm_golden.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
HEX="$SCRIPT_DIR/fixtures/matrix8x8_bcm4.ihx"
FOSC=11059200
# 55ms: captures two full BCM cycles (48 ticks) + margin
UNTIL_NS=55000000

if [ ! -x "$STC12_TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU_TRACE" ]; then echo "SKIP: emu_trace not found" >&2; exit 0; fi
if [ ! -f "$HEX" ]; then echo "FAIL: fixture not found at $HEX" >&2; exit 1; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PASS=0; FAIL=0

echo "=== MATRIX8X8 BCM 4-Level Golden Trace (STC89) ==="
echo ""

# Golden column values (P0) per tick: 3 phases × 8 rows = 24 ticks.
# Phase 0 (p0|p1): levels >=1 lit
# Phase 1 (p1):    levels >=2 lit
# Phase 2 (p0&p1): levels >=3 lit
GOLDEN=(
    00 00 00 FF FF FF FF FF
    00 00 FF FF FF FF FF FF
    00 FF FF FF FF FF FF FF
)

# Extract the column byte per tick (last P0 write between TF events).
# When no P0 event occurs in a tick, the value is 0xFF (stayed at blank).
extract_col_per_tick() {
    awk '
    $2 == "SFR" && $3 == "80" { last_p0 = toupper($4) }
    $2 == "TF" {
        if (NR > 1) {
            if (last_p0 != "") print last_p0
            else print "FF"
        }
        last_p0 = ""
    }
    END { if (last_p0 != "") print last_p0; else if (NR > 0) print "FF" }
    ' "$1"
}

# Run both emulators
timeout 15 "$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "SFR" && $3 == "80" || $2 == "TF"' > "$TMP/emu.sfr"
timeout 15 "$STC12_TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "SFR" && $3 == "80" || $2 == "TF"' > "$TMP/ucsim.sfr"

extract_col_per_tick "$TMP/emu.sfr"   > "$TMP/emu_cols.txt"
extract_col_per_tick "$TMP/ucsim.sfr" > "$TMP/ucsim_cols.txt"

emu_count=$(wc -l < "$TMP/emu_cols.txt")
ucs_count=$(wc -l < "$TMP/ucsim_cols.txt")
echo "Ticks captured: emu=$emu_count ucsim=$ucs_count"
echo ""

# --- Section 1: Per-tick golden comparison (full BCM cycle = 24 ticks) ---
echo "--- Section 1: Per-tick BCM golden comparison (3 phases × 8 rows) ---"
printf "%-6s %-7s %-4s %-12s %-8s %-8s %-6s\n" \
    "Tick" "Phase" "Row" "BCM-mask" "emu-P0" "ucs-P0" "Match"
printf "%-6s %-7s %-4s %-12s %-8s %-8s %-6s\n" \
    "----" "-----" "---" "--------" "------" "------" "-----"

PHASE_NAMES=("p0|p1" "p1" "p0&p1")
min_ticks=$((emu_count < 24 ? emu_count : 24))
for tick in $(seq 0 $((min_ticks - 1))); do
    p=$((tick / 8))
    row=$((tick % 8))
    gold="${GOLDEN[$tick]}"
    gold=$(echo "$gold" | tr '[:lower:]' '[:upper:]')
    emu_val=$(sed -n "$((tick+1))p" "$TMP/emu_cols.txt")
    ucs_val=$(sed -n "$((tick+1))p" "$TMP/ucsim_cols.txt")

    if [ "$emu_val" = "$gold" ] && [ "$ucs_val" = "$gold" ]; then
        m="PASS"
        PASS=$((PASS+1))
    else
        m="FAIL"
        FAIL=$((FAIL+1))
    fi
    printf "%-6d %-7s %-4d %-12s %-8s %-8s %-6s\n" \
        "$tick" "${PHASE_NAMES[$p]}" "$row" "P0=0x$gold" "0x$emu_val" "0x$ucs_val" "$m"
done

# --- Section 2: Duty verification per row ---
echo ""
echo "--- Section 2: Duty per row (lit phases / 3) ---"

for row in 0 1 2 3; do
    emu_lit=0; ucs_lit=0; gold_lit=0
    for p in 0 1 2; do
        tick=$((p * 8 + row))
        g="${GOLDEN[$tick]}"
        ev=$(sed -n "$((tick+1))p" "$TMP/emu_cols.txt")
        uv=$(sed -n "$((tick+1))p" "$TMP/ucsim_cols.txt")
        [ "$g" != "FF" ] && gold_lit=$((gold_lit+1))
        [ "$ev" != "FF" ] && emu_lit=$((emu_lit+1))
        [ "$uv" != "FF" ] && ucs_lit=$((ucs_lit+1))
    done
    expected_level=$((3 - row))
    if [ "$gold_lit" -eq "$expected_level" ] && [ "$emu_lit" -eq "$expected_level" ] \
       && [ "$ucs_lit" -eq "$expected_level" ]; then
        printf "Row %d (level %d): duty %d/3 — PASS\n" "$row" "$expected_level" "$gold_lit"
        PASS=$((PASS+1))
    else
        printf "Row %d (level %d): gold=%d/3 emu=%d/3 ucs=%d/3 — FAIL\n" \
            "$row" "$expected_level" "$gold_lit" "$emu_lit" "$ucs_lit"
        FAIL=$((FAIL+1))
    fi
done

# --- Section 3: Cross-emulator agreement on full cycle ---
echo ""
echo "--- Section 3: Cross-emulator column agreement (full BCM cycle) ---"
min_both=$((emu_count < ucs_count ? emu_count : ucs_count))
if head -n "$min_both" "$TMP/emu_cols.txt" \
   | diff - <(head -n "$min_both" "$TMP/ucsim_cols.txt") > /dev/null 2>&1; then
    echo "Cross-emulator: EXACT match on first $min_both ticks"
    PASS=$((PASS+1))
else
    echo "Cross-emulator: DIVERGENCE"
    diff "$TMP/emu_cols.txt" "$TMP/ucsim_cols.txt" | head -10
    FAIL=$((FAIL+1))
fi

# --- Section 4: BCM cycle repeats (second cycle matches first) ---
echo ""
echo "--- Section 4: BCM cycle repeat (ticks 0-23 vs 24-47) ---"
if [ "$emu_count" -ge 48 ] && [ "$ucs_count" -ge 48 ]; then
    cycle1=$(head -24 "$TMP/emu_cols.txt")
    cycle2=$(sed -n '25,48p' "$TMP/emu_cols.txt")
    if [ "$cycle1" = "$cycle2" ]; then
        echo "emu: BCM cycle 1 == cycle 2 (scan+phase wraps correctly) — PASS"
        PASS=$((PASS+1))
    else
        echo "emu: BCM cycle MISMATCH — FAIL"
        FAIL=$((FAIL+1))
    fi
else
    echo "SKIP: need >= 48 ticks for cycle repeat check (have emu=$emu_count ucsim=$ucs_count)"
fi

# --- Section 5: 595 shift register edges cross-emu ---
echo ""
echo "--- Section 5: 595 edge order (P3.4=data, P3.5=latch, P3.6=clock) ---"
# Extract PIN events between TF#0 and TF#1 (one row's 595 protocol)
timeout 15 "$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "TF" { tf++; next } tf == 1 && $2 == "PIN" && $3 ~ /3\.[456]/' \
    | cut -f2- > "$TMP/emu_595.pin"
timeout 15 "$STC12_TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "TF" { tf++; next } tf == 1 && $2 == "PIN" && $3 ~ /3\.[456]/' \
    | cut -f2- > "$TMP/ucsim_595.pin"

emu_595=$(wc -l < "$TMP/emu_595.pin")
ucs_595=$(wc -l < "$TMP/ucsim_595.pin")

if diff "$TMP/emu_595.pin" "$TMP/ucsim_595.pin" > /dev/null 2>&1; then
    echo "595 edges: EXACT match ($emu_595 events)"
    clock_count=$(grep -c "3.6" "$TMP/emu_595.pin")
    echo "595 protocol: $((clock_count/2)) clock cycles per row"
    PASS=$((PASS+1))
else
    echo "595 edges: DIVERGENCE (emu=$emu_595 ucsim=$ucs_595)"
    diff "$TMP/emu_595.pin" "$TMP/ucsim_595.pin" | head -10
    FAIL=$((FAIL+1))
fi

echo ""
echo "=== Results ==="
echo "Pass: $PASS  Fail: $FAIL"
[ $FAIL -eq 0 ] && exit 0 || exit 1
