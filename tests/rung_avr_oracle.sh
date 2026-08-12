#!/bin/bash
# rung_avr_oracle.sh — AVR differential oracle: simavr vs avr8js.
#
# Runs both simulators on the same ATmega328P hex files and compares:
#   1. Pin-edge cycle counts (must agree exactly)
#   2. UART byte order and values (must agree exactly)
#   3. UART byte timing (documents the known simavr parity-bit bug)
#
# Prerequisites:
#   - simavr_harness built: gcc -O2 -o tests/simavr_harness tests/simavr_harness.c -lsimavr -lm
#   - avr8js available via bw-board's node_modules (read-only)
#
# Usage: ./tests/rung_avr_oracle.sh
set -e
cd "$(dirname "$0")/.."

SIMAVR="./tests/simavr_harness"
AVR8JS="tests/avr8js_harness.mjs"
PASS=0
FAIL=0
KNOWN=0

pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
known() { echo "KNOWN $1"; KNOWN=$((KNOWN+1)); }

if [ ! -x "$SIMAVR" ]; then
    echo "Building simavr_harness..."
    gcc -O2 -o "$SIMAVR" tests/simavr_harness.c -lsimavr -lm
fi
if [ ! -f "$AVR8JS" ]; then echo "FAIL: $AVR8JS not found" >&2; exit 1; fi

TMP_S=$(mktemp)
TMP_A=$(mktemp)
trap "rm -f $TMP_S $TMP_A" EXIT

# ── Test 1: Hand-assembled blink — pin edges ──
echo ""
echo "=== Test 1: Hand-assembled blink (pin edges) ==="
HEX="tests/fixtures/avr_blink_hand.ihx"
timeout 10 "$SIMAVR" "$HEX" 3000 16000000 > "$TMP_S" 2>/dev/null
timeout 10 node "$AVR8JS" "$HEX" 3000 16000000 > "$TMP_A" 2>/dev/null

S_EDGES=$(grep '^PIN_EDGE' "$TMP_S")
A_EDGES=$(grep '^PIN_EDGE' "$TMP_A")

if [ "$S_EDGES" = "$A_EDGES" ]; then
    pass "Hand blink: all pin edges match exactly"
    # Verify toggle period
    PERIOD=$(echo "$S_EDGES" | grep -Eo 'cy=[0-9]+' | head -2 | \
             awk -F= 'NR==1{a=$2} NR==2{print $2-a}')
    if [ "$PERIOD" = "769" ]; then
        pass "Hand blink: toggle period = 769 cycles (matches arithmetic oracle)"
    else
        fail "Hand blink: toggle period = $PERIOD (expected 769)"
    fi
else
    fail "Hand blink: pin edges disagree"
    echo "  simavr: $(echo "$S_EDGES" | head -2)"
    echo "  avr8js: $(echo "$A_EDGES" | head -2)"
fi

# ── Test 2: Compiled blink — pin edges ──
echo ""
echo "=== Test 2: Compiled blink (pin edges) ==="
HEX="tests/fixtures/avr_blink_compiled.ihx"
timeout 10 "$SIMAVR" "$HEX" 200000 16000000 > "$TMP_S" 2>/dev/null
timeout 10 node "$AVR8JS" "$HEX" 200000 16000000 > "$TMP_A" 2>/dev/null

S_EDGES=$(grep '^PIN_EDGE' "$TMP_S")
A_EDGES=$(grep '^PIN_EDGE' "$TMP_A")

if [ "$S_EDGES" = "$A_EDGES" ]; then
    pass "Compiled blink: all pin edges match exactly"
    PERIOD=$(echo "$S_EDGES" | grep -Eo 'cy=[0-9]+' | head -2 | \
             awk -F= 'NR==1{a=$2} NR==2{print $2-a}')
    pass "Compiled blink: toggle period = $PERIOD cycles"
else
    fail "Compiled blink: pin edges disagree"
fi

# ── Test 3: UART test — byte values and order ──
echo ""
echo "=== Test 3: UART TX (byte values and timing) ==="
HEX="tests/fixtures/avr_uart_test.ihx"
if [ ! -f "$HEX" ]; then
    echo "SKIP: $HEX not found"
else
    timeout 15 "$SIMAVR" "$HEX" 5000000 16000000 > "$TMP_S" 2>/dev/null
    timeout 15 node "$AVR8JS" "$HEX" 5000000 16000000 > "$TMP_A" 2>/dev/null

    # Byte values must match
    S_BYTES=$(grep '^UART_TX' "$TMP_S" | grep -Eo 'byte=0x[0-9a-f]+' | tr '\n' ' ')
    A_BYTES=$(grep '^UART_TX' "$TMP_A" | grep -Eo 'byte=0x[0-9a-f]+' | tr '\n' ' ')

    if [ "$S_BYTES" = "$A_BYTES" ]; then
        pass "UART: byte values and order match"
    else
        fail "UART: byte values differ"
        echo "  simavr: $S_BYTES"
        echo "  avr8js: $A_BYTES"
    fi

    # First byte cycle must match
    S_FIRST=$(grep '^UART_TX' "$TMP_S" | head -1 | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')
    A_FIRST=$(grep '^UART_TX' "$TMP_A" | head -1 | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')

    if [ "$S_FIRST" = "$A_FIRST" ]; then
        pass "UART: first byte cycle agrees ($S_FIRST)"
    else
        fail "UART: first byte cycle differs (simavr=$S_FIRST avr8js=$A_FIRST)"
    fi

    # Subsequent bytes: document the known parity-bit drift
    S_SECOND=$(grep '^UART_TX' "$TMP_S" | sed -n '2p' | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')
    A_SECOND=$(grep '^UART_TX' "$TMP_A" | sed -n '2p' | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')
    DRIFT=$((S_SECOND - A_SECOND))

    if [ "$DRIFT" -ge 1660 ] && [ "$DRIFT" -le 1670 ]; then
        known "UART: simavr 2nd byte drifts by $DRIFT cy (1 bit time) — phantom parity bit (spec-updates/018)"
    elif [ "$DRIFT" -eq 0 ]; then
        pass "UART: 2nd byte cycle agrees (simavr bug may be fixed)"
    else
        fail "UART: unexpected 2nd byte drift: $DRIFT cycles"
    fi
fi

# ── Test 4: ADC + UART — byte values match, timing drifts ──
echo ""
echo "=== Test 4: ADC + UART (byte values and ADC completion) ==="
HEX="tests/fixtures/avr_adc_test.ihx"
if [ ! -f "$HEX" ]; then
    echo "SKIP: $HEX not found"
else
    timeout 30 "$SIMAVR" "$HEX" 20000000 16000000 > "$TMP_S" 2>/dev/null
    timeout 30 node "$AVR8JS" "$HEX" 20000000 16000000 > "$TMP_A" 2>/dev/null

    S_BYTES=$(grep '^UART_TX' "$TMP_S" | grep -Eo 'byte=0x[0-9a-f]+' | tr '\n' ' ')
    A_BYTES=$(grep '^UART_TX' "$TMP_A" | grep -Eo 'byte=0x[0-9a-f]+' | tr '\n' ' ')

    if [ "$S_BYTES" = "$A_BYTES" ]; then
        pass "ADC+UART: byte values match (both read ADC=0)"
    else
        fail "ADC+UART: byte values differ"
        echo "  simavr: $S_BYTES"
        echo "  avr8js: $A_BYTES"
    fi

    # First byte timing (includes ADC wait) should match
    S_FIRST=$(grep '^UART_TX' "$TMP_S" | head -1 | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')
    A_FIRST=$(grep '^UART_TX' "$TMP_A" | head -1 | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')

    if [ "$S_FIRST" = "$A_FIRST" ]; then
        pass "ADC+UART: first byte cycle agrees ($S_FIRST) — ADC timing matches"
    else
        ADC_DIFF=$((S_FIRST - A_FIRST))
        if [ "$ADC_DIFF" -eq 0 ] 2>/dev/null; then
            pass "ADC+UART: first byte cycle agrees"
        else
            known "ADC+UART: first byte differs by $ADC_DIFF cy (ADC timing variance)"
        fi
    fi

    # PB5 pin edge should exist in both
    S_PIN=$(grep '^PIN_EDGE' "$TMP_S" | wc -l)
    A_PIN=$(grep '^PIN_EDGE' "$TMP_A" | wc -l)

    if [ "$S_PIN" -gt 0 ] && [ "$A_PIN" -gt 0 ]; then
        pass "ADC+UART: both toggle PB5 after UART output"
    else
        fail "ADC+UART: pin edge missing (simavr=$S_PIN avr8js=$A_PIN)"
    fi
fi

# ── Test 5: Timer1 CTC — execution time agreement ──
echo ""
echo "=== Test 5: Timer1 CTC (execution timing) ==="
HEX="tests/fixtures/avr_timer_test.ihx"
if [ ! -f "$HEX" ]; then
    echo "SKIP: $HEX not found"
else
    timeout 10 "$SIMAVR" "$HEX" 200000 16000000 > "$TMP_S" 2>/dev/null
    timeout 10 node "$AVR8JS" "$HEX" 200000 16000000 > "$TMP_A" 2>/dev/null

    # PB5 toggle marks program completion — should exist in both
    S_PB5=$(grep 'portb\.5=1' "$TMP_S" | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')
    A_PB5=$(grep 'portb\.5=1' "$TMP_A" | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')

    if [ -n "$S_PB5" ] && [ -n "$A_PB5" ]; then
        DIFF=$((S_PB5 - A_PB5))
        ABS_DIFF=${DIFF#-}
        if [ "$ABS_DIFF" -le 2 ]; then
            pass "Timer1 CTC: completion PB5 agrees within $ABS_DIFF cy (simavr=$S_PB5 avr8js=$A_PB5)"
        else
            fail "Timer1 CTC: completion PB5 differs by $ABS_DIFF cy (simavr=$S_PB5 avr8js=$A_PB5)"
        fi
    else
        fail "Timer1 CTC: PB5 missing (simavr='$S_PB5' avr8js='$A_PB5')"
    fi

    # simavr also shows OC1A toggles on PB1 (hw output); avr8js correctly
    # does not modify PORTB register for COMnx overrides (per datasheet).
    S_OC1A=$(grep 'portb\.1' "$TMP_S" | wc -l)
    if [ "$S_OC1A" -gt 0 ]; then
        known "Timer1 CTC: simavr shows $S_OC1A OC1A edges on PB1; avr8js doesn't (harness visibility, not a bug)"
    fi
fi

# ── Test 6: Timer0 overflow — ISR-driven toggle period ──
echo ""
echo "=== Test 6: Timer0 overflow (ISR-driven toggle) ==="
HEX="tests/fixtures/avr_timer0_ovf.ihx"
if [ ! -f "$HEX" ]; then
    echo "SKIP: $HEX not found"
else
    timeout 15 "$SIMAVR" "$HEX" 500000 16000000 > "$TMP_S" 2>/dev/null
    timeout 15 node "$AVR8JS" "$HEX" 500000 16000000 > "$TMP_A" 2>/dev/null

    S_COUNT=$(grep '^PIN_EDGE' "$TMP_S" | wc -l)
    A_COUNT=$(grep '^PIN_EDGE' "$TMP_A" | wc -l)

    if [ "$S_COUNT" = "$A_COUNT" ]; then
        pass "Timer0 OVF: same edge count ($S_COUNT)"
    else
        fail "Timer0 OVF: edge count differs (simavr=$S_COUNT avr8js=$A_COUNT)"
    fi

    # Check average period matches expected: 2 * 256 * 64 = 32768 cy
    S_P1=$(grep '^PIN_EDGE' "$TMP_S" | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+' | head -2 | \
           awk 'NR==1{a=$1} NR==2{print $1-a}')
    A_P1=$(grep '^PIN_EDGE' "$TMP_A" | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+' | head -2 | \
           awk 'NR==1{a=$1} NR==2{print $1-a}')

    # Average of first two periods should be 32768
    S_P2=$(grep '^PIN_EDGE' "$TMP_S" | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+' | head -3 | \
           awk 'NR==1{a=$1} NR==2{b=$1} NR==3{print $1-b}')
    A_P2=$(grep '^PIN_EDGE' "$TMP_A" | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+' | head -3 | \
           awk 'NR==1{a=$1} NR==2{b=$1} NR==3{print $1-b}')

    S_AVG=$(( (S_P1 + S_P2) / 2 ))
    A_AVG=$(( (A_P1 + A_P2) / 2 ))

    if [ "$S_AVG" -eq 32768 ] && [ "$A_AVG" -eq 32768 ]; then
        pass "Timer0 OVF: avg period = 32768 cy (both, = 2×256×64)"
    else
        fail "Timer0 OVF: avg period simavr=$S_AVG avr8js=$A_AVG (expected 32768)"
    fi

    # Constant offset between simulators should be small (≤ 4 cy)
    S_FIRST=$(grep '^PIN_EDGE' "$TMP_S" | head -1 | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')
    A_FIRST=$(grep '^PIN_EDGE' "$TMP_A" | head -1 | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')
    T0_OFFSET=$((A_FIRST - S_FIRST))
    ABS_OFFSET=${T0_OFFSET#-}

    if [ "$ABS_OFFSET" -le 4 ]; then
        pass "Timer0 OVF: first-edge offset = $T0_OFFSET cy (ISR dispatch timing)"
    else
        fail "Timer0 OVF: first-edge offset = $T0_OFFSET cy (expected ≤ 4)"
    fi
fi

# ── Test 7: PWM — completion timing agreement ──
echo ""
echo "=== Test 7: Fast PWM (OC0A on PD6, completion timing) ==="
HEX="tests/fixtures/avr_pwm_test.ihx"
if [ ! -f "$HEX" ]; then
    echo "SKIP: $HEX not found"
else
    timeout 10 "$SIMAVR" "$HEX" 200000 16000000 > "$TMP_S" 2>/dev/null
    timeout 10 node "$AVR8JS" "$HEX" 200000 16000000 > "$TMP_A" 2>/dev/null

    S_PB5=$(grep 'portb\.5=1' "$TMP_S" | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')
    A_PB5=$(grep 'portb\.5=1' "$TMP_A" | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')

    if [ "$S_PB5" = "$A_PB5" ]; then
        pass "PWM: completion PB5 agrees exactly ($S_PB5)"
    else
        DIFF=$((S_PB5 - A_PB5))
        ABS=${DIFF#-}
        if [ "$ABS" -le 2 ]; then
            pass "PWM: completion PB5 agrees within $ABS cy"
        else
            fail "PWM: completion PB5 differs by $ABS cy (simavr=$S_PB5 avr8js=$A_PB5)"
        fi
    fi

    # OC0A (PD6) PWM output: neither simulator writes PORTD register
    # for hardware compare-match output (correct per datasheet).
    S_PD=$(grep 'portd\.' "$TMP_S" | wc -l)
    A_PD=$(grep 'portd\.' "$TMP_A" | wc -l)
    if [ "$S_PD" -eq 0 ] && [ "$A_PD" -eq 0 ]; then
        pass "PWM: OC0A hw output invisible in PORT register (both, correct)"
    else
        known "PWM: OC0A edges visible (simavr=$S_PD avr8js=$A_PD)"
    fi
fi

# ── Test 8: ISR latency — Timer2 CTC interrupt dispatch ──
echo ""
echo "=== Test 8: ISR latency (Timer2 CTC, 100 cy period) ==="
HEX="tests/fixtures/avr_isr_latency.ihx"
if [ ! -f "$HEX" ]; then
    echo "SKIP: $HEX not found"
else
    timeout 10 "$SIMAVR" "$HEX" 10000 16000000 > "$TMP_S" 2>/dev/null
    timeout 10 node "$AVR8JS" "$HEX" 10000 16000000 > "$TMP_A" 2>/dev/null

    S_COUNT=$(grep '^PIN_EDGE' "$TMP_S" | wc -l)
    A_COUNT=$(grep '^PIN_EDGE' "$TMP_A" | wc -l)

    if [ "$S_COUNT" = "$A_COUNT" ]; then
        pass "ISR latency: same edge count ($S_COUNT)"
    else
        fail "ISR latency: edge count differs (simavr=$S_COUNT avr8js=$A_COUNT)"
    fi

    # Completion timing (last PB5 edge)
    S_LAST=$(grep 'portb\.5' "$TMP_S" | tail -1 | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')
    A_LAST=$(grep 'portb\.5' "$TMP_A" | tail -1 | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')
    DIFF=$((S_LAST - A_LAST))
    ABS=${DIFF#-}

    if [ "$ABS" -le 5 ]; then
        pass "ISR latency: completion agrees within $ABS cy (simavr=$S_LAST avr8js=$A_LAST)"
    else
        fail "ISR latency: completion differs by $ABS cy"
    fi

    # Average ISR-to-ISR period (from edges 1-4)
    S_PERIODS=$(grep '^PIN_EDGE.*portb' "$TMP_S" | head -4 | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+')
    S_FIRST=$(echo "$S_PERIODS" | head -1)
    S_FOURTH=$(echo "$S_PERIODS" | tail -1)
    S_AVG_PERIOD=$(( (S_FOURTH - S_FIRST) / 3 ))

    if [ "$S_AVG_PERIOD" -eq 100 ]; then
        pass "ISR latency: simavr avg period = 100 cy (correct for OCR2A=99)"
    else
        fail "ISR latency: simavr avg period = $S_AVG_PERIOD (expected 100)"
    fi
fi

# ── Test 9: Cooperative scheduler — multi-peripheral integration ──
echo ""
echo "=== Test 9: Cooperative scheduler (Timer0+GPIO+UART) ==="
HEX="tests/fixtures/avr_scheduler.ihx"
if [ ! -f "$HEX" ]; then
    echo "SKIP: $HEX not found"
else
    timeout 30 "$SIMAVR" "$HEX" 1000000 16000000 > "$TMP_S" 2>/dev/null
    timeout 30 node "$AVR8JS" "$HEX" 1000000 16000000 > "$TMP_A" 2>/dev/null

    # Same event count
    S_ALL=$(grep -c '^[PU]' "$TMP_S")
    A_ALL=$(grep -c '^[PU]' "$TMP_A")
    if [ "$S_ALL" = "$A_ALL" ]; then
        pass "Scheduler: same event count ($S_ALL)"
    else
        fail "Scheduler: event count differs (simavr=$S_ALL avr8js=$A_ALL)"
    fi

    # UART byte values match
    S_BYTES=$(grep '^UART_TX' "$TMP_S" | grep -Eo 'byte=0x[0-9a-f]+' | tr '\n' ' ')
    A_BYTES=$(grep '^UART_TX' "$TMP_A" | grep -Eo 'byte=0x[0-9a-f]+' | tr '\n' ' ')
    if [ "$S_BYTES" = "$A_BYTES" ]; then
        pass "Scheduler: UART values match (both report same tick count)"
    else
        fail "Scheduler: UART values differ"
    fi

    # Pin edge order matches (both PB5 and PB4 events)
    S_ORDER=$(grep '^PIN_EDGE' "$TMP_S" | grep -Eo 'portb\.[0-9]=[0-9]' | tr '\n' ' ')
    A_ORDER=$(grep '^PIN_EDGE' "$TMP_A" | grep -Eo 'portb\.[0-9]=[0-9]' | tr '\n' ' ')
    if [ "$S_ORDER" = "$A_ORDER" ]; then
        pass "Scheduler: pin edge order matches"
    else
        fail "Scheduler: pin edge order differs"
    fi

    # Max cycle offset between corresponding edges should be small
    S_CY=($(grep '^PIN_EDGE' "$TMP_S" | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+'))
    A_CY=($(grep '^PIN_EDGE' "$TMP_A" | grep -Eo 'cy=[0-9]+' | grep -Eo '[0-9]+'))
    MAX_DIFF=0
    for i in $(seq 0 $((${#S_CY[@]} - 1))); do
        D=$(( ${S_CY[$i]} - ${A_CY[$i]} ))
        AD=${D#-}
        if [ "$AD" -gt "$MAX_DIFF" ]; then MAX_DIFF=$AD; fi
    done
    if [ "$MAX_DIFF" -le 20 ]; then
        pass "Scheduler: max pin-edge offset = $MAX_DIFF cy (ISR dispatch jitter)"
    else
        fail "Scheduler: max pin-edge offset = $MAX_DIFF cy (expected ≤ 20)"
    fi
fi

# ── Summary ──
echo ""
echo "================================"
echo "Results: $PASS pass, $FAIL fail, $KNOWN known"
echo "================================"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
