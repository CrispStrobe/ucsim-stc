#!/bin/bash
# rung_sevenseg8_golden.sh — per-tick SEVENSEG8 scan golden trace.
#
# For the fixture sevenseg8_digits (digits 1-8 in frame buffer), asserts
# absolute byte-exact values for each ISR tick:
#   tick N: digit select P2[2:0] = N, segment port P0 = font[N+1]
#
# Reuses the same harness structure as MATRIX8X8.
#
# Usage: ./tests/rung_sevenseg8_golden.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
HEX="$SCRIPT_DIR/fixtures/sevenseg8_digits.ihx"
FOSC=11059200
# 16 ticks = 2 full scans; STC89 12T needs ~1ms per tick
UNTIL_NS=18000000

if [ ! -x "$STC12_TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU_TRACE" ]; then echo "SKIP: emu_trace not found" >&2; exit 0; fi
if [ ! -f "$HEX" ]; then echo "FAIL: fixture not found at $HEX" >&2; exit 1; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# 7-seg font: common cathode, indices 0-F
FONT=(3F 06 5B 4F 66 6D 7D 07 7F 6F 77 7C 39 5E 79 71)

# Frame buffer: digits 1-8 → font indices 1-8
#   fb[0]=font[1]=06  fb[1]=font[2]=5B  ... fb[7]=font[8]=7F
GOLDEN_SEG=()
for i in $(seq 0 7); do
    idx=$((i + 1))
    GOLDEN_SEG+=("${FONT[$idx]}")
done

# Digit select: tick N → P2 & 0x07 = N
#   tick 0: P2 low bits = 000 → P2 = F8
#   tick 1: 001 → F9   tick 2: 010 → FA   tick 3: 011 → FB
#   tick 4: 100 → FC   tick 5: 101 → FD   tick 6: 110 → FE   tick 7: 111 → FF
GOLDEN_P2=(F8 F9 FA FB FC FD FE FF)

# Extract the segment byte (last P0 write, excluding blank 0x00) and
# the digit select (last P2 write) per tick.
# Output: one line per tick: "P2_HEX P0_HEX"
extract_per_tick() {
    awk '
    $2 == "SFR" && $3 == "80" && $4 != "00" { last_p0 = $4 }
    $2 == "SFR" && $3 == "A0" { last_p2 = $4 }
    $2 == "TF" {
        if (NR > 1 && last_p0 != "" && last_p2 != "")
            print last_p2 " " last_p0
        last_p0 = ""; last_p2 = ""
    }
    END { if (last_p0 != "" && last_p2 != "") print last_p2 " " last_p0 }
    ' "$1"
}

PASS=0; FAIL=0

echo "=== SEVENSEG8 Per-Tick Golden Trace (digits 1-8, STC89) ==="
echo ""

# Run both emulators — filter SFR writes for P0 and P2 plus TF events
timeout 10 "$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "SFR" && ($3 == "80" || $3 == "A0") || $2 == "TF"' > "$TMP/emu.sfr"
timeout 10 "$STC12_TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "SFR" && ($3 == "80" || $3 == "A0") || $2 == "TF"' > "$TMP/ucsim.sfr"

extract_per_tick "$TMP/emu.sfr"   > "$TMP/emu_ticks.txt"
extract_per_tick "$TMP/ucsim.sfr" > "$TMP/ucsim_ticks.txt"

emu_count=$(wc -l < "$TMP/emu_ticks.txt")
ucs_count=$(wc -l < "$TMP/ucsim_ticks.txt")
echo "Ticks captured: emu=$emu_count ucsim=$ucs_count"
echo ""

# --- Table 1: per-tick golden comparison (first 8 = one full scan) ---
printf "%-6s %-6s %-10s %-10s %-10s %-10s %-6s\n" \
    "Tick" "Digit" "gold-P2" "gold-P0" "emu" "ucsim" "Match"
printf "%-6s %-6s %-10s %-10s %-10s %-10s %-6s\n" \
    "----" "-----" "-------" "-------" "---" "-----" "-----"

min_ticks=$((emu_count < 8 ? emu_count : 8))
for tick in $(seq 0 $((min_ticks - 1))); do
    digit=$((tick % 8))
    gold_p2=$(echo "${GOLDEN_P2[$digit]}" | tr '[:lower:]' '[:upper:]')
    gold_seg=$(echo "${GOLDEN_SEG[$digit]}" | tr '[:lower:]' '[:upper:]')

    emu_line=$(sed -n "$((tick+1))p" "$TMP/emu_ticks.txt")
    ucs_line=$(sed -n "$((tick+1))p" "$TMP/ucsim_ticks.txt")

    emu_p2=$(echo "$emu_line" | awk '{print $1}' | tr '[:lower:]' '[:upper:]')
    emu_p0=$(echo "$emu_line" | awk '{print $2}' | tr '[:lower:]' '[:upper:]')
    ucs_p2=$(echo "$ucs_line" | awk '{print $1}' | tr '[:lower:]' '[:upper:]')
    ucs_p0=$(echo "$ucs_line" | awk '{print $2}' | tr '[:lower:]' '[:upper:]')

    if [ "$emu_p2" = "$gold_p2" ] && [ "$emu_p0" = "$gold_seg" ] \
       && [ "$ucs_p2" = "$gold_p2" ] && [ "$ucs_p0" = "$gold_seg" ]; then
        m="PASS"
        PASS=$((PASS+1))
    else
        m="FAIL"
        FAIL=$((FAIL+1))
    fi
    printf "%-6d %-6d %-10s %-10s %-10s %-10s %-6s\n" \
        "$tick" "$digit" "P2=$gold_p2" "P0=$gold_seg" \
        "$emu_p2:$emu_p0" "$ucs_p2:$ucs_p0" "$m"
done

# --- Cross-emulator agreement on ALL ticks ---
echo ""
min_both=$((emu_count < ucs_count ? emu_count : ucs_count))
if head -n "$min_both" "$TMP/emu_ticks.txt" \
   | diff - <(head -n "$min_both" "$TMP/ucsim_ticks.txt") > /dev/null 2>&1; then
    echo "Cross-emulator: EXACT match on first $min_both ticks"
    PASS=$((PASS+1))
else
    echo "Cross-emulator: DIVERGENCE"
    diff "$TMP/emu_ticks.txt" "$TMP/ucsim_ticks.txt" | head -10
    FAIL=$((FAIL+1))
fi

# --- Verify second scan repeats (cursor wraps at 8) ---
if [ "$emu_count" -ge 16 ]; then
    echo ""
    frame1=$(head -8 "$TMP/emu_ticks.txt")
    frame2=$(sed -n '9,16p' "$TMP/emu_ticks.txt")
    if [ "$frame1" = "$frame2" ]; then
        echo "Scan wrap: emu frame 1 == frame 2 (cursor wraps correctly)"
        PASS=$((PASS+1))
    else
        echo "Scan wrap: MISMATCH"
        FAIL=$((FAIL+1))
    fi
fi

# --- Digit-select PIN events cross-emu (P2.0, P2.1, P2.2 between TF#1 and TF#2) ---
echo ""
echo "--- Digit select PIN events (P2.0/P2.1/P2.2 between tick 0 and tick 1) ---"
timeout 10 "$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "TF" { tf++; next } tf == 1 && $2 == "PIN" && $3 ~ /2\.[012]/' \
    | cut -f2- > "$TMP/emu_sel.pin"
timeout 10 "$STC12_TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    | awk '$2 == "TF" { tf++; next } tf == 1 && $2 == "PIN" && $3 ~ /2\.[012]/' \
    | cut -f2- > "$TMP/ucsim_sel.pin"

emu_pins=$(wc -l < "$TMP/emu_sel.pin")
ucs_pins=$(wc -l < "$TMP/ucsim_sel.pin")

if diff "$TMP/emu_sel.pin" "$TMP/ucsim_sel.pin" > /dev/null 2>&1; then
    echo "Digit-select PINs: EXACT match ($emu_pins events)"
    PASS=$((PASS+1))
else
    echo "Digit-select PINs: DIVERGENCE (emu=$emu_pins ucsim=$ucs_pins)"
    diff "$TMP/emu_sel.pin" "$TMP/ucsim_sel.pin" | head -10
    FAIL=$((FAIL+1))
fi

echo ""
echo "=== Results ==="
echo "Pass: $PASS  Fail: $FAIL"
[ $FAIL -eq 0 ] && exit 0 || exit 1
