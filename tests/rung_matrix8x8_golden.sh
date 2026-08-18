#!/bin/bash
# rung_matrix8x8_golden.sh — per-tick MATRIX8X8 scan golden trace.
#
# For the heart image shown on an 8x8 LED matrix via 595 row select +
# port columns, asserts absolute byte-exact values for each ISR tick:
#   tick N: column_port P0 = ~heart[N] (active-low)
#
# Reusable harness structure:
#   1. Define golden values (image bytes, SFR addresses)
#   2. Extract per-tick SFR writes from both emulators
#   3. Compare absolute values against golden model
#   To plug SEVENSEG8/LEDBANK8: change the golden array + SFR address.
#
# Usage: ./tests/rung_matrix8x8_golden.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
HEX="$SCRIPT_DIR/fixtures/matrix8x8_heart.ihx"
FOSC=11059200
# 16 ticks = 2 full frames; STC89 12T needs ~1.08ms per tick
UNTIL_NS=18000000

if [ ! -x "$STC12_TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU_TRACE" ]; then echo "SKIP: emu_trace not found" >&2; exit 0; fi
if [ ! -f "$HEX" ]; then echo "FAIL: fixture not found at $HEX" >&2; exit 1; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Heart image bytes (row 0 = top)
HEART_HEX=(66 FF FF FF 7E 3C 18 00)

# Golden column port: ~heart[row] & 0xFF (active-low columns)
golden_col() {
    printf "%02X" $(( (~0x${HEART_HEX[$1]}) & 0xFF ))
}

# Extract the last P0 (SFR 80) write before each TF event.
# This is the column byte the ISR drove before the NEXT tick fires.
extract_col_per_tick() {
    awk '
    $2 == "SFR" && $3 == "80" { last_p0 = $4 }
    $2 == "TF" {
        if (NR > 1 && last_p0 != "") print last_p0
        last_p0 = ""
    }
    END { if (last_p0 != "") print last_p0 }
    ' "$1"
}

PASS=0; FAIL=0

echo "=== MATRIX8X8 Per-Tick Golden Trace (heart image, STC89) ==="
echo ""

# Run both emulators
timeout 10 "$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "SFR" && $3 == "80" || $2 == "TF"' > "$TMP/emu.sfr"
timeout 10 "$STC12_TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "SFR" && $3 == "80" || $2 == "TF"' > "$TMP/ucsim.sfr"

extract_col_per_tick "$TMP/emu.sfr" > "$TMP/emu_cols.txt"
extract_col_per_tick "$TMP/ucsim.sfr" > "$TMP/ucsim_cols.txt"

emu_count=$(wc -l < "$TMP/emu_cols.txt")
ucs_count=$(wc -l < "$TMP/ucsim_cols.txt")
echo "Ticks captured: emu=$emu_count ucsim=$ucs_count"
echo ""

# --- Table 1: per-tick golden comparison (first 8 = one frame) ---
printf "%-6s %-4s %-12s %-10s %-10s %-6s\n" "Tick" "Row" "Heart[row]" "emu-P0" "ucs-P0" "Match"
printf "%-6s %-4s %-12s %-10s %-10s %-6s\n" "----" "---" "----------" "------" "------" "-----"

min_ticks=$((emu_count < 8 ? emu_count : 8))
for tick in $(seq 0 $((min_ticks - 1))); do
    row=$((tick % 8))
    golden=$(golden_col $row)
    emu_val=$(sed -n "$((tick+1))p" "$TMP/emu_cols.txt" | tr '[:lower:]' '[:upper:]')
    ucs_val=$(sed -n "$((tick+1))p" "$TMP/ucsim_cols.txt" | tr '[:lower:]' '[:upper:]')
    golden=$(echo "$golden" | tr '[:lower:]' '[:upper:]')

    heart_byte="0x${HEART_HEX[$row]}"
    if [ "$emu_val" = "$golden" ] && [ "$ucs_val" = "$golden" ]; then
        m="PASS"
        PASS=$((PASS+1))
    else
        m="FAIL"
        FAIL=$((FAIL+1))
    fi
    printf "%-6d %-4d %-12s %-10s %-10s %-6s\n" "$tick" "$row" "$heart_byte→~$golden" "0x$emu_val" "0x$ucs_val" "$m"
done

# --- Cross-emulator agreement on ALL ticks ---
echo ""
min_both=$((emu_count < ucs_count ? emu_count : ucs_count))
if head -n "$min_both" "$TMP/emu_cols.txt" | diff - <(head -n "$min_both" "$TMP/ucsim_cols.txt") > /dev/null 2>&1; then
    echo "Cross-emulator: EXACT match on first $min_both ticks"
    PASS=$((PASS+1))
else
    echo "Cross-emulator: DIVERGENCE"
    diff "$TMP/emu_cols.txt" "$TMP/ucsim_cols.txt" | head -10
    FAIL=$((FAIL+1))
fi

# --- Verify second frame repeats (scan wraps) ---
if [ "$emu_count" -ge 16 ]; then
    echo ""
    frame1=$(head -8 "$TMP/emu_cols.txt")
    frame2=$(sed -n '9,16p' "$TMP/emu_cols.txt")
    if [ "$frame1" = "$frame2" ]; then
        echo "Frame repeat: emu frame 1 == frame 2 (scan wraps correctly)"
        PASS=$((PASS+1))
    else
        echo "Frame repeat: MISMATCH"
        FAIL=$((FAIL+1))
    fi
fi

# --- 595 edge order: latch/data/clock sequence cross-emu ---
echo ""
echo "--- 595 edge order (P3.4=data, P3.5=latch, P3.6=clock) ---"
# Extract PIN events for the 595 pins from first tick only (between TF#1 and TF#2)
timeout 10 "$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "TF" { tf++; next } tf == 1 && $2 == "PIN" && $3 ~ /3\.[456]/' \
    | cut -f2- > "$TMP/emu_595.pin"
timeout 10 "$STC12_TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "TF" { tf++; next } tf == 1 && $2 == "PIN" && $3 ~ /3\.[456]/' \
    | cut -f2- > "$TMP/ucsim_595.pin"

emu_595=$(wc -l < "$TMP/emu_595.pin")
ucs_595=$(wc -l < "$TMP/ucsim_595.pin")

if diff "$TMP/emu_595.pin" "$TMP/ucsim_595.pin" > /dev/null 2>&1; then
    echo "595 edges: EXACT match ($emu_595 events)"
    # Verify expected sequence: latch L, data, 7×(clk H, clk L), latch H, latch L
    first_ev=$(head -1 "$TMP/emu_595.pin")
    latch_count=$(grep -c "3.5" "$TMP/emu_595.pin")
    clock_count=$(grep -c "3.6" "$TMP/emu_595.pin")
    if echo "$first_ev" | grep -q "3.5.*L" && [ "$clock_count" -ge 14 ]; then
        echo "595 protocol: latch-first, $((clock_count/2)) clock cycles per row"
        PASS=$((PASS+1))
    else
        echo "595 protocol: unexpected sequence"
        head -5 "$TMP/emu_595.pin"
        FAIL=$((FAIL+1))
    fi
else
    echo "595 edges: DIVERGENCE (emu=$emu_595 ucsim=$ucs_595)"
    diff "$TMP/emu_595.pin" "$TMP/ucsim_595.pin" | head -10
    FAIL=$((FAIL+1))
fi

echo ""
echo "=== Results ==="
echo "Pass: $PASS  Fail: $FAIL"
[ $FAIL -eq 0 ] && exit 0 || exit 1
