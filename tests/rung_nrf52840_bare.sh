#!/bin/bash
# rung_nrf52840_bare.sh — nRF52840 bare-metal execution under labwired.
#
# Proves: ARM Thumb-2 bare-metal code executes correctly on labwired's
# nRF52840 model. GPIO register writes (DIRSET/OUTSET/OUTCLR) and UART
# TX (ENABLE, STARTTX, TXD, TXDRDY) work end-to-end.
#
# Recipe:
#   Assemble:  arm-none-eabi-as -mcpu=cortex-m4 -mthumb -o X.o X.S
#   Link:      arm-none-eabi-ld -T gpio_toggle.ld -o X.elf X.o
#   Run:       labwired run --chip nrf52840.yaml --firmware X.elf --max-steps N
#
# Usage: ./tests/rung_nrf52840_bare.sh
set -e
cd "$(dirname "$0")/.."

PASS=0
FAIL=0

pass() { echo "PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }

LW="labwired-core/target/release/labwired"
CHIP="labwired-core/configs/chips/nrf52840.yaml"
FIXDIR="tests/fixtures/nrf52840"

if [ ! -x "$LW" ]; then
    echo "SKIP: labwired-core not built"
    exit 0
fi

echo ""
echo "=== nRF52840 bare-metal execution (labwired) ==="
echo ""

# ── Build fixtures if needed ──
if [ ! -f "$FIXDIR/uart_hello.elf" ] || [ ! -f "$FIXDIR/gpio_toggle_uart.elf" ]; then
    echo "Building fixtures..."
    (cd "$FIXDIR" && \
     arm-none-eabi-as -mcpu=cortex-m4 -mthumb -o uart_hello.o uart_hello.S && \
     arm-none-eabi-ld -T gpio_toggle.ld -o uart_hello.elf uart_hello.o && \
     arm-none-eabi-as -mcpu=cortex-m4 -mthumb -o gpio_toggle_uart.o gpio_toggle_uart.S && \
     arm-none-eabi-ld -T gpio_toggle.ld -o gpio_toggle_uart.elf gpio_toggle_uart.o && \
     arm-none-eabi-as -mcpu=cortex-m4 -mthumb -o gpio_toggle.o gpio_toggle.S && \
     arm-none-eabi-ld -T gpio_toggle.ld -o gpio_toggle.elf gpio_toggle.o)
fi

# ── Test 1: UART hello ──
OUT=$(timeout 10 "$LW" run --chip "$CHIP" --firmware "$FIXDIR/uart_hello.elf" \
    --max-steps 5000000 2>/dev/null || true)

if echo "$OUT" | grep -q "nRF52840 OK"; then
    pass "UART hello outputs 'nRF52840 OK'"
else
    fail "UART hello: expected 'nRF52840 OK', got: $(echo "$OUT" | head -1)"
fi

# ── Test 2: GPIO toggle with UART reporting ──
OUT=$(timeout 30 "$LW" run --chip "$CHIP" --firmware "$FIXDIR/gpio_toggle_uart.elf" \
    --max-steps 50000000 2>/dev/null || true)

EDGES=$(echo "$OUT" | grep -c '^[HL]$' || true)
DONE=$(echo "$OUT" | grep -c '^DONE$' || true)
PATTERN=$(echo "$OUT" | grep '^[HLD]' | tr '\n' ' ')

if [ "$EDGES" -eq 8 ]; then
    pass "GPIO toggle: 8 edges (H/L transitions)"
else
    fail "GPIO toggle: expected 8 edges, got $EDGES"
fi

if [ "$DONE" -ge 1 ]; then
    pass "GPIO toggle: program reached DONE marker"
else
    fail "GPIO toggle: DONE marker missing"
fi

if echo "$PATTERN" | grep -q "H L H L H L H L DONE"; then
    pass "GPIO toggle: correct H/L alternation"
else
    fail "GPIO toggle: pattern wrong: $PATTERN"
fi

# ── Test 3: GPIO toggle (infinite, no UART) loads without crash ──
OUT=$(timeout 5 "$LW" run --chip "$CHIP" --firmware "$FIXDIR/gpio_toggle.elf" \
    --max-steps 100 2>/dev/null; echo "exit:$?")

if echo "$OUT" | grep -q "exit:0"; then
    pass "GPIO toggle (infinite): loads and executes 100 steps"
else
    fail "GPIO toggle (infinite): did not exit cleanly"
fi

# ── Summary ──
echo ""
echo "================================"
echo "nRF52840 bare-metal: $PASS pass, $FAIL fail"
echo "================================"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
