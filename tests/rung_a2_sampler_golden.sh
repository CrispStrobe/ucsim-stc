#!/bin/bash
# rung_a2_sampler_golden.sh — A2 multi-device golden trace.
#
# End-to-end proof: keypad debounce → SEVENSEG8 display → LEDBANK8 chase.
# Uses a self-contained fixture (mock keypad scanner, no pin injection)
# that both emulators run identically.
#
# Mock timeline (bw_ms):
#   <10: no key (-1)    >=10: key 5
#
# Debounce (5ms poll, two-agreeing-reads):
#   ms=5:  read=-1, raw=-1==read → key=-1
#   ms=10: read=5,  raw=-1≠5    → key unchanged; raw←5
#   ms=15: read=5,  raw=5==5    → key←5 (debounced!)
#
# Golden events:
#   P3 (LEDBANK8): FE→FD→FB→DF  (chase steps + key override at ms=15)
#   P0 (SEVENSEG8): digit 0 shows 3F (font[0]) until key, then 6D (font[5])
#
# Usage: ./tests/rung_a2_sampler_golden.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STC12_TRACE="$SCRIPT_DIR/../ucsim/src/sims/s51.src/stc12_trace"
EMU_TRACE="${EMU_TRACE:-../emu8051-stc/emu_trace}"
HEX="$SCRIPT_DIR/fixtures/a2_sampler_keyshow.ihx"
FOSC=11059200
# 30ms: captures full debounce sequence + 2 display frames after key
UNTIL_NS=30000000

if [ ! -x "$STC12_TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi
if [ ! -x "$EMU_TRACE" ]; then echo "SKIP: emu_trace not found" >&2; exit 0; fi
if [ ! -f "$HEX" ]; then echo "FAIL: fixture not found at $HEX" >&2; exit 1; fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PASS=0; FAIL=0

echo "=== A2 Sampler Golden Trace (keypad→7seg+LEDs, STC89) ==="
echo ""

# Run both emulators, capture full trace
timeout 15 "$EMU_TRACE" -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    > "$TMP/emu_full.txt"
timeout 15 "$STC12_TRACE" -t STC89 -fosc $FOSC -until-ns $UNTIL_NS "$HEX" 2>/dev/null \
    > "$TMP/ucsim_full.txt"

# ---------- Section 1: LEDBANK8 chase + key override (P3 sequence) ----------
echo "--- Section 1: LEDBANK8 chase + key override (P3 = 0xB0) ---"

# Golden P3 sequence: chase 0x01→0x02→0x04, then key override 0x20
# ISR writes ~shadow, so: FE FD FB DF
GOLDEN_P3="FE FD FB DF"

emu_p3=$(awk '$2 == "SFR" && $3 == "B0" { print $4 }' "$TMP/emu_full.txt" \
    | tr '[:lower:]' '[:upper:]' | head -4 | tr '\n' ' ' | sed 's/ $//')
ucs_p3=$(awk '$2 == "SFR" && $3 == "B0" { print $4 }' "$TMP/ucsim_full.txt" \
    | tr '[:lower:]' '[:upper:]' | head -4 | tr '\n' ' ' | sed 's/ $//')

printf "%-10s %-20s\n" "golden:" "$GOLDEN_P3"
printf "%-10s %-20s\n" "emu:" "$emu_p3"
printf "%-10s %-20s\n" "ucsim:" "$ucs_p3"

if [ "$emu_p3" = "$GOLDEN_P3" ] && [ "$ucs_p3" = "$GOLDEN_P3" ]; then
    echo "PASS: P3 chase+override sequence matches"
    PASS=$((PASS+1))
else
    echo "FAIL: P3 sequence mismatch"
    FAIL=$((FAIL+1))
fi

# Verify no further P3 changes after the key override
emu_p3_total=$(awk '$2 == "SFR" && $3 == "B0"' "$TMP/emu_full.txt" | wc -l)
ucs_p3_total=$(awk '$2 == "SFR" && $3 == "B0"' "$TMP/ucsim_full.txt" | wc -l)

if [ "$emu_p3_total" -eq 4 ] && [ "$ucs_p3_total" -eq 4 ]; then
    echo "PASS: exactly 4 P3 writes (3 chase + 1 key), no spurious changes"
    PASS=$((PASS+1))
else
    echo "FAIL: expected 4 P3 writes, got emu=$emu_p3_total ucsim=$ucs_p3_total"
    FAIL=$((FAIL+1))
fi

# ---------- Section 2: Debounce timing (P3 key override at correct tick) ----------
echo ""
echo "--- Section 2: Debounce timing (key override at ms ~15) ---"

# The key override (P3=DF) should appear 3 chase steps after the first P3 write,
# each chase step is 5ms apart. Count TF events between first P3 and fourth P3
# to verify the 15ms debounce delay (should be ~15 ticks = ~15ms).
for src in emu ucsim; do
    file="$TMP/${src}_full.txt"
    # Get nanosecond timestamps of first and fourth P3 writes
    first_p3_ns=$(awk '$2 == "SFR" && $3 == "B0" { print $1; exit }' "$file")
    fourth_p3_ns=$(awk '$2 == "SFR" && $3 == "B0" { n++; if (n==4) { print $1; exit } }' "$file")
    # Count TF events between them
    ticks_between=$(awk -v t1="$first_p3_ns" -v t4="$fourth_p3_ns" \
        '$2 == "TF" && $1+0 > t1+0 && $1+0 < t4+0 { n++ } END { print n+0 }' "$file")
    # Convert to approximate ms
    delta_ns=$(( fourth_p3_ns - first_p3_ns ))
    delta_ms=$(( delta_ns / 1000000 ))
    # Should be ~15ms (14-16ms acceptable due to timer phase)
    if [ "$delta_ms" -ge 14 ] && [ "$delta_ms" -le 16 ]; then
        printf "%-6s: chase→key delta = %d ms (%d ticks) — PASS\n" "$src" "$delta_ms" "$ticks_between"
        PASS=$((PASS+1))
    else
        printf "%-6s: chase→key delta = %d ms (%d ticks) — FAIL (expected 14-16ms)\n" "$src" "$delta_ms" "$ticks_between"
        FAIL=$((FAIL+1))
    fi
done

# ---------- Section 3: SEVENSEG8 digit-0 transition (P0: 3F → 6D) ----------
echo ""
echo "--- Section 3: SEVENSEG8 digit-0 segment transition ---"

# Extract non-zero P0 writes (segment values, not blanks).
# Digit 0 appears on ticks 0, 8, 16, 24, ... — these are the P0 writes
# that follow a blank (0x00) and come after P2 shows digit-0 select.
# Simpler: just look at all non-zero P0 values in sequence.
# Before key: 3F (font[0]). After key: 6D (font[5]).
for src in emu ucsim; do
    file="$TMP/${src}_full.txt"
    # Get unique P0 non-zero segment values in appearance order
    p0_vals=$(awk '$2 == "SFR" && $3 == "80" && $4 != "00" { print $4 }' "$file" \
        | tr '[:lower:]' '[:upper:]')

    # First non-zero P0 should be 3F (font[0])
    first_p0=$(echo "$p0_vals" | head -1)
    # After key fires, should see 6D (font[5])
    has_6d=$(echo "$p0_vals" | grep -c "^6D$")

    if [ "$first_p0" = "3F" ] && [ "$has_6d" -gt 0 ]; then
        echo "$src: digit-0 shows 0x3F then 0x6D — PASS"
        PASS=$((PASS+1))
    else
        echo "$src: expected 3F→6D, got first=$first_p0, 6D count=$has_6d — FAIL"
        FAIL=$((FAIL+1))
    fi
done

# Verify transition order: last 3F must precede first 6D
echo ""
for src in emu ucsim; do
    file="$TMP/${src}_full.txt"
    last_3f_ns=$(awk '$2 == "SFR" && $3 == "80" && $4 == "3F" { t=$1 } END { print t+0 }' "$file" \
        | tr '[:lower:]' '[:upper:]')
    # Handle case-insensitive hex
    first_6d_ns=$(awk '$2 == "SFR" && $3 == "80" && ($4 == "6D" || $4 == "6d") { print $1; exit }' "$file")

    if [ "$first_6d_ns" -gt "$last_3f_ns" ]; then
        echo "$src: 3F→6D ordering correct (last 3F at ${last_3f_ns}ns < first 6D at ${first_6d_ns}ns) — PASS"
        PASS=$((PASS+1))
    else
        echo "$src: ordering wrong — FAIL"
        FAIL=$((FAIL+1))
    fi
done

# ---------- Section 4: Edge fires exactly once ----------
echo ""
echo "--- Section 4: One edge per press (P0=6D appears, then repeats stably) ---"

for src in emu ucsim; do
    file="$TMP/${src}_full.txt"
    # Count how many times P0 transitions to 6D among non-zero writes.
    # Skip blank (0x00) values — the ISR blanks P0 between digit writes,
    # so the real segment transition is 3F→6D, not 00→6D.
    transitions=$(awk '
        $2 == "SFR" && $3 == "80" && $4 != "00" {
            v = toupper($4)
            if (v == "6D" && prev != "6D") n++
            prev = v
        }
        END { print n+0 }
    ' "$file")

    if [ "$transitions" -eq 1 ]; then
        echo "$src: exactly 1 transition to 6D (one edge per press) — PASS"
        PASS=$((PASS+1))
    else
        echo "$src: $transitions transitions to 6D — FAIL"
        FAIL=$((FAIL+1))
    fi
done

# ---------- Section 5: Cross-emulator SFR+TF sequence match ----------
echo ""
echo "--- Section 5: Cross-emulator full SFR+TF sequence ---"

# Strip timestamps, keep event type + data, for P0/P2/P3/TF events
for src in emu ucsim; do
    awk '$2 == "SFR" && ($3 == "80" || $3 == "A0" || $3 == "B0") || $2 == "TF" { print $2, $3, $4 }' \
        "$TMP/${src}_full.txt" > "$TMP/${src}_seq.txt"
done

emu_lines=$(wc -l < "$TMP/emu_seq.txt")
ucs_lines=$(wc -l < "$TMP/ucsim_seq.txt")
min_lines=$((emu_lines < ucs_lines ? emu_lines : ucs_lines))

if head -n "$min_lines" "$TMP/emu_seq.txt" \
   | diff - <(head -n "$min_lines" "$TMP/ucsim_seq.txt") > /dev/null 2>&1; then
    echo "Cross-emulator: EXACT match on first $min_lines events"
    PASS=$((PASS+1))
else
    echo "Cross-emulator: DIVERGENCE"
    diff "$TMP/emu_seq.txt" "$TMP/ucsim_seq.txt" | head -20
    FAIL=$((FAIL+1))
fi

# ---------- Section 6: Digit-select PIN events cross-emu ----------
echo ""
echo "--- Section 6: Digit-select PIN events (P2.0/P2.1/P2.2) ---"

for src in emu ucsim; do
    awk '$2 == "PIN" && $3 ~ /^2\.[012]/' "$TMP/${src}_full.txt" \
        | cut -f2- > "$TMP/${src}_p2.pin"
done

emu_pin_count=$(wc -l < "$TMP/emu_p2.pin")
ucs_pin_count=$(wc -l < "$TMP/ucsim_p2.pin")
min_pins=$((emu_pin_count < ucs_pin_count ? emu_pin_count : ucs_pin_count))

# Compare common prefix (tail may differ by 1-3 events due to boundary timing)
if head -n "$min_pins" "$TMP/emu_p2.pin" \
   | diff - <(head -n "$min_pins" "$TMP/ucsim_p2.pin") > /dev/null 2>&1; then
    echo "Digit-select PINs: EXACT match on first $min_pins events (emu=$emu_pin_count ucsim=$ucs_pin_count)"
    PASS=$((PASS+1))
else
    echo "Digit-select PINs: DIVERGENCE (emu=$emu_pin_count ucsim=$ucs_pin_count)"
    diff <(head -n "$min_pins" "$TMP/emu_p2.pin") <(head -n "$min_pins" "$TMP/ucsim_p2.pin") | head -10
    FAIL=$((FAIL+1))
fi

# ---------- Section 7: LEDBANK8 PIN events cross-emu ----------
echo ""
echo "--- Section 7: LEDBANK8 PIN events (P3.0-P3.7) ---"

for src in emu ucsim; do
    awk '$2 == "PIN" && $3 ~ /^3\./' "$TMP/${src}_full.txt" \
        | cut -f2- > "$TMP/${src}_p3.pin"
done

emu_p3_pins=$(wc -l < "$TMP/emu_p3.pin")
ucs_p3_pins=$(wc -l < "$TMP/ucsim_p3.pin")

if diff "$TMP/emu_p3.pin" "$TMP/ucsim_p3.pin" > /dev/null 2>&1; then
    echo "LEDBANK8 PINs: EXACT match ($emu_p3_pins events)"
    PASS=$((PASS+1))
else
    echo "LEDBANK8 PINs: DIVERGENCE (emu=$emu_p3_pins ucsim=$ucs_p3_pins)"
    diff "$TMP/emu_p3.pin" "$TMP/ucsim_p3.pin" | head -10
    FAIL=$((FAIL+1))
fi

echo ""
echo "=== Results ==="
echo "Pass: $PASS  Fail: $FAIL"
[ $FAIL -eq 0 ] && exit 0 || exit 1
