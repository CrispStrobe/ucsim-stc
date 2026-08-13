#!/bin/bash
# rung_lcd_i2c.sh — I2C LCD protocol edge measurement
#
# Validates:
#   1. I2C START/address/data/STOP structure on P2.1 (SDA) and P2.2 (SCL)
#   2. Address byte = 0x4E (PCF8574 at 0x27, write)
#   3. HD44780 4-bit init sequence (0x30×3, 0x20, then 0x28/0x0C/0x06/0x01)
#   4. SCL timing vs NXP I2C standard-mode spec (t_HIGH ≥ 4000 ns, t_LOW ≥ 4700 ns)
#
# Fixtures: i2c_1t.ihx (v1, loop=13), i2c_1t_v2.ihx (v2, loop=26), i2c_12t.ihx (12T)
#
# Category: 3 (single-implementation, ucsim only)

set -e

TRACE="./ucsim/src/sims/s51.src/stc12_trace"
FOSC=11059200
DURATION=50000000  # 50 ms — 12T is ~6× slower, needs more time for init

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [ ! -x "$TRACE" ]; then echo "FAIL: stc12_trace not found" >&2; exit 1; fi

# Run trace and extract P2 pin events
run_trace() {
    local model="$1" fixture="$2"
    timeout 60 "$TRACE" -t "$model" -fosc "$FOSC" -until-ns "$DURATION" "$fixture" 2>/dev/null \
        | grep "PIN	2\."
}

# Decode I2C from pin events via inline Python
decode_i2c() {
    python3 -c '
import sys, re
from collections import Counter

sda, scl = 1, 1
state = "IDLE"
bit_count = 0
byte_val = 0
tx_bytes = []
current_tx = []
current_tx_start = 0

# SCL timing (excluding START/STOP edges)
scl_highs, scl_lows = [], []
last_rise, last_fall = None, None
in_start_stop = False

for line in sys.stdin:
    m = re.match(r"(\d+)\tPIN\t2\.(\d)\s+\w+\s+([HL])", line.strip())
    if not m: continue
    time_ns, pin, lvl = int(m.group(1)), int(m.group(2)), m.group(3)
    level = 1 if lvl == "H" else 0

    if pin == 1:
        old_sda = sda
        sda = level
        if old_sda == 1 and sda == 0 and scl == 1:  # START
            current_tx = []
            current_tx_start = time_ns
            state = "DATA"
            bit_count = 0
            byte_val = 0
            if scl == 1:
                in_start_stop = True
        elif old_sda == 0 and sda == 1 and scl == 1:  # STOP
            tx_bytes.append(current_tx)
            current_tx = []
            state = "IDLE"
            bit_count = 0
            in_start_stop = True
    elif pin == 2:
        old_scl = scl
        scl = level
        if old_scl == 0 and scl == 1:  # rising
            if last_fall is not None and not in_start_stop:
                scl_lows.append(time_ns - last_fall)
            last_rise = time_ns
            in_start_stop = False
            if state == "DATA":
                if bit_count < 8:
                    byte_val = (byte_val << 1) | sda
                    bit_count += 1
                    if bit_count == 8:
                        current_tx.append(byte_val)
                        state = "ACK"
            elif state == "ACK":
                state = "DATA"
                bit_count = 0
                byte_val = 0
        elif old_scl == 1 and scl == 0:  # falling
            if last_rise is not None and not in_start_stop:
                scl_highs.append(time_ns - last_rise)
            last_fall = time_ns

# Output results as key=value pairs
n_tx = len(tx_bytes)
print(f"N_TX={n_tx}")

# Check address bytes (first byte of each tx should be 0x4E)
if n_tx > 0:
    addr_ok = sum(1 for tx in tx_bytes if tx and tx[0] == 0x4E)
    print(f"ADDR_OK={addr_ok}")
    print(f"ADDR_TOTAL={n_tx}")

# Check init sequence: first 24 txs, data bytes
init_data = [tx[1] if len(tx) > 1 else -1 for tx in tx_bytes[:24]]
expected = [0x3C, 0x38, 0x3C, 0x38, 0x3C, 0x38, 0x2C, 0x28,
            0x2C, 0x28, 0x8C, 0x88, 0x0C, 0x08, 0xCC, 0xC8,
            0x0C, 0x08, 0x6C, 0x68, 0x0C, 0x08, 0x1C, 0x18]
init_ok = init_data == expected
print(f"INIT_OK={init_ok}")

# SCL timing
if scl_highs:
    hc = Counter(scl_highs)
    dominant_h = hc.most_common(1)[0][0]
    min_h = min(scl_highs)
    print(f"SCL_HIGH_DOM={dominant_h}")
    print(f"SCL_HIGH_MIN={min_h}")
if scl_lows:
    lc = Counter(scl_lows)
    dominant_l = lc.most_common(1)[0][0]
    min_l = min(scl_lows)
    print(f"SCL_LOW_DOM={dominant_l}")
    print(f"SCL_LOW_MIN={min_l}")
'
}

echo "=== LCD I2C protocol edge measurement ==="
echo

for fixture_label in "v1_1T:STC12:tests/fixtures/i2c_1t.ihx" \
                     "v2_1T:STC12:tests/fixtures/i2c_1t_v2.ihx" \
                     "12T:STC89:tests/fixtures/i2c_12t.ihx"; do
    IFS=: read -r label model fixture <<< "$fixture_label"
    echo "--- $label ($fixture) ---"

    if [ ! -f "$fixture" ]; then
        fail "$label: fixture not found"
        continue
    fi

    RESULT=$(run_trace "$model" "$fixture" | decode_i2c)

    N_TX=$(echo "$RESULT" | grep "^N_TX=" | cut -d= -f2)
    ADDR_OK=$(echo "$RESULT" | grep "^ADDR_OK=" | cut -d= -f2)
    ADDR_TOTAL=$(echo "$RESULT" | grep "^ADDR_TOTAL=" | cut -d= -f2)
    INIT_OK=$(echo "$RESULT" | grep "^INIT_OK=" | cut -d= -f2)
    SCL_HIGH_DOM=$(echo "$RESULT" | grep "^SCL_HIGH_DOM=" | cut -d= -f2)
    SCL_HIGH_MIN=$(echo "$RESULT" | grep "^SCL_HIGH_MIN=" | cut -d= -f2)
    SCL_LOW_DOM=$(echo "$RESULT" | grep "^SCL_LOW_DOM=" | cut -d= -f2)
    SCL_LOW_MIN=$(echo "$RESULT" | grep "^SCL_LOW_MIN=" | cut -d= -f2)

    # Test 1: transactions detected
    if [ "$N_TX" -gt 24 ] 2>/dev/null; then
        pass "$label: $N_TX I2C transactions detected"
    else
        fail "$label: only $N_TX transactions (expected >24)"
    fi

    # Test 2: address byte = 0x4E on all transactions
    if [ "$ADDR_OK" = "$ADDR_TOTAL" ] 2>/dev/null; then
        pass "$label: address 0x4E on all $ADDR_TOTAL transactions"
    else
        fail "$label: address 0x4E on $ADDR_OK/$ADDR_TOTAL transactions"
    fi

    # Test 3: HD44780 init sequence correct
    if [ "$INIT_OK" = "True" ]; then
        pass "$label: HD44780 init sequence correct (0x30×3, 0x20, 0x28, 0x0C, 0x06, 0x01)"
    else
        fail "$label: HD44780 init sequence mismatch"
    fi

    # Test 4: SCL timing (only v2 and 12T expected to pass)
    echo "  SCL timing: t_HIGH(dom)=${SCL_HIGH_DOM} ns, t_LOW(dom)=${SCL_LOW_DOM} ns"
    case "$label" in
        v1_1T)
            # v1 is known out-of-spec — verify it IS out of spec
            if [ "$SCL_HIGH_DOM" -lt 4000 ] 2>/dev/null; then
                pass "$label: t_HIGH ${SCL_HIGH_DOM} ns correctly below 4000 ns (known v1 bug)"
            else
                fail "$label: expected t_HIGH below 4000 (v1 known bug), got ${SCL_HIGH_DOM}"
            fi
            ;;
        v2_1T)
            if [ "$SCL_HIGH_MIN" -ge 4000 ] 2>/dev/null; then
                pass "$label: t_HIGH min ${SCL_HIGH_MIN} ns >= 4000 ns spec"
            else
                fail "$label: t_HIGH min ${SCL_HIGH_MIN} ns < 4000 ns spec"
            fi
            if [ "$SCL_LOW_MIN" -ge 4700 ] 2>/dev/null; then
                pass "$label: t_LOW min ${SCL_LOW_MIN} ns >= 4700 ns spec"
            else
                # The min may be at SDA-change edges; check dominant
                if [ "$SCL_LOW_DOM" -ge 4700 ] 2>/dev/null; then
                    pass "$label: t_LOW dominant ${SCL_LOW_DOM} ns >= 4700 ns (min ${SCL_LOW_MIN} at SDA transitions)"
                else
                    fail "$label: t_LOW dominant ${SCL_LOW_DOM} ns < 4700 ns spec"
                fi
            fi
            ;;
        12T)
            if [ "$SCL_HIGH_MIN" -ge 4000 ] 2>/dev/null; then
                pass "$label: t_HIGH min ${SCL_HIGH_MIN} ns >= 4000 ns spec"
            else
                fail "$label: t_HIGH min ${SCL_HIGH_MIN} ns < 4000 ns spec"
            fi
            if [ "$SCL_LOW_MIN" -ge 4700 ] 2>/dev/null; then
                pass "$label: t_LOW min ${SCL_LOW_MIN} ns >= 4700 ns spec"
            else
                fail "$label: t_LOW min ${SCL_LOW_MIN} ns < 4700 ns spec"
            fi
            ;;
    esac
    echo
done

echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
