#!/usr/bin/env python3
"""Decode I2C protocol from PIN trace events on P2.1 (SDA) and P2.2 (SCL).

Reads tab-separated PIN events from stdin or a file:
    78125   PIN  2.1 OD L
    79029   PIN  2.2 OD L

Outputs decoded I2C transactions:
    START, address byte, data bytes, ACK/NACK, STOP
    with timestamps for each edge and SCL timing measurements.
"""

import sys
import re

def main():
    fname = sys.argv[1] if len(sys.argv) > 1 else "-"
    f = open(fname) if fname != "-" else sys.stdin

    # State: track SDA and SCL levels
    sda = 1  # idle high (open drain, pull-up)
    scl = 1

    # I2C decode state
    state = "IDLE"  # IDLE, ADDR, DATA, ACK
    bit_count = 0
    byte_val = 0
    bytes_in_frame = []
    frame_start_ns = 0

    # Timing stats
    scl_edges = []  # (time_ns, direction)  H=rising, L=falling
    scl_high_times = []
    scl_low_times = []
    last_scl_rise = None
    last_scl_fall = None

    transactions = []
    current_tx = None

    for line in f:
        line = line.strip()
        # Parse: time_ns\tPIN\t2.N OD H/L
        m = re.match(r'(\d+)\tPIN\t2\.(\d)\s+\w+\s+([HL])', line)
        if not m:
            continue
        time_ns = int(m.group(1))
        pin = int(m.group(2))
        level = 1 if m.group(3) == 'H' else 0

        if pin == 1:
            old_sda = sda
            sda = level
            # START condition: SDA falls while SCL is high
            if old_sda == 1 and sda == 0 and scl == 1:
                if current_tx is not None:
                    # Repeated START
                    current_tx["events"].append(("RSTART", time_ns))
                current_tx = {
                    "start_ns": time_ns,
                    "events": [("START", time_ns)],
                    "bytes": [],
                    "acks": [],
                }
                state = "DATA"
                bit_count = 0
                byte_val = 0

            # STOP condition: SDA rises while SCL is high
            elif old_sda == 0 and sda == 1 and scl == 1:
                if current_tx is not None:
                    current_tx["events"].append(("STOP", time_ns))
                    current_tx["stop_ns"] = time_ns
                    transactions.append(current_tx)
                    current_tx = None
                state = "IDLE"
                bit_count = 0

        elif pin == 2:
            old_scl = scl
            scl = level
            # SCL rising edge: sample SDA
            if old_scl == 0 and scl == 1:
                last_scl_rise = time_ns
                if last_scl_fall is not None:
                    scl_low_times.append(time_ns - last_scl_fall)

                if state == "DATA" and current_tx is not None:
                    if bit_count < 8:
                        byte_val = (byte_val << 1) | sda
                        bit_count += 1
                        if bit_count == 8:
                            current_tx["bytes"].append(byte_val)
                            current_tx["events"].append(("BYTE", time_ns, byte_val))
                            state = "ACK"
                    elif state == "ACK":
                        pass  # handled below

                elif state == "ACK" and current_tx is not None:
                    # This SCL rising edge is the ACK/NACK clock
                    ack = "ACK" if sda == 0 else "NACK"
                    current_tx["acks"].append(ack)
                    current_tx["events"].append((ack, time_ns))
                    state = "DATA"
                    bit_count = 0
                    byte_val = 0

            # SCL falling edge
            elif old_scl == 1 and scl == 0:
                last_scl_fall = time_ns
                if last_scl_rise is not None:
                    scl_high_times.append(time_ns - last_scl_rise)

    if f != sys.stdin:
        f.close()

    # Print results
    print("=" * 70)
    print("I2C PROTOCOL DECODE")
    print("=" * 70)
    print(f"Total transactions: {len(transactions)}")
    print()

    for i, tx in enumerate(transactions):
        duration_ns = tx.get("stop_ns", tx["start_ns"]) - tx["start_ns"]
        addr_byte = tx["bytes"][0] if tx["bytes"] else None
        if addr_byte is not None:
            addr_7bit = addr_byte >> 1
            rw = "R" if addr_byte & 1 else "W"
        else:
            addr_7bit = None
            rw = "?"

        data_bytes = tx["bytes"][1:]

        if i < 30 or i == len(transactions) - 1:
            print(f"TX {i:4d}: START @ {tx['start_ns']:>12d} ns  "
                  f"addr=0x{addr_7bit:02X}({rw})  "
                  f"data=[{', '.join(f'0x{b:02X}' for b in data_bytes)}]  "
                  f"acks=[{', '.join(tx['acks'])}]  "
                  f"dur={duration_ns} ns"
                  if addr_7bit is not None else
                  f"TX {i:4d}: START @ {tx['start_ns']:>12d} ns  (no bytes)")
        elif i == 30:
            print(f"  ... ({len(transactions) - 31} more transactions) ...")

    # SCL timing summary
    print()
    print("=" * 70)
    print("SCL TIMING")
    print("=" * 70)
    if scl_high_times:
        avg_h = sum(scl_high_times) / len(scl_high_times)
        min_h = min(scl_high_times)
        max_h = max(scl_high_times)
        print(f"SCL HIGH: avg={avg_h:.1f} ns  min={min_h} ns  max={max_h} ns  "
              f"(n={len(scl_high_times)})")
        # I2C standard mode minimums: t_HIGH >= 4000 ns, t_LOW >= 4700 ns
        if min_h < 4000:
            print(f"  ** WARNING: min t_HIGH {min_h} ns < 4000 ns spec minimum **")
        else:
            print(f"  OK: min t_HIGH {min_h} ns >= 4000 ns spec minimum")

    if scl_low_times:
        avg_l = sum(scl_low_times) / len(scl_low_times)
        min_l = min(scl_low_times)
        max_l = max(scl_low_times)
        print(f"SCL LOW:  avg={avg_l:.1f} ns  min={min_l} ns  max={max_l} ns  "
              f"(n={len(scl_low_times)})")
        if min_l < 4700:
            print(f"  ** WARNING: min t_LOW {min_l} ns < 4700 ns spec minimum **")
        else:
            print(f"  OK: min t_LOW {min_l} ns >= 4700 ns spec minimum")

    if scl_high_times and scl_low_times:
        period = avg_h + avg_l
        freq_khz = 1e6 / period if period > 0 else 0
        print(f"SCL freq: ~{freq_khz:.1f} kHz  (period ~{period:.0f} ns)")
        print()

    # Decode LCD init sequence
    print("=" * 70)
    print("LCD HD44780 PROTOCOL DECODE")
    print("=" * 70)
    # PCF8574 bit layout: D7 D6 D5 D4 BL EN RW RS
    # Each LCD nibble is sent as two I2C writes: one with EN=1, one with EN=0
    nibbles = []
    for tx in transactions:
        if len(tx["bytes"]) >= 2:
            addr_byte = tx["bytes"][0]
            for db in tx["bytes"][1:]:
                en = (db >> 2) & 1
                rs = db & 1
                rw = (db >> 1) & 1
                bl = (db >> 3) & 1
                data_nib = (db >> 4) & 0xF
                nibbles.append({
                    "raw": db,
                    "data": data_nib,
                    "en": en,
                    "rs": rs,
                    "rw": rw,
                    "bl": bl,
                    "time_ns": tx["start_ns"],
                })

    # Pair up nibbles: EN=1 followed by EN=0 makes one "latch"
    # Then pair latches for full bytes (high nibble, low nibble)
    latches = []
    for nib in nibbles:
        if nib["en"] == 1:
            latches.append(nib)

    # Print first 40 latches
    print(f"Total EN=1 latches: {len(latches)}")
    cmds = []
    i = 0
    # First 4 latches are single-nibble init commands
    init_nibs = 0
    while i < len(latches) and init_nibs < 4:
        n = latches[i]
        if n["rs"] == 0:
            print(f"  INIT nibble: 0x{n['data']:X}0  (rs={n['rs']}, nibble=0x{n['data']:X})")
            init_nibs += 1
            i += 1
        else:
            break

    # Remaining latches come in pairs (high nibble, low nibble)
    cmd_count = 0
    while i + 1 < len(latches):
        hi = latches[i]
        lo = latches[i + 1]
        full_byte = (hi["data"] << 4) | lo["data"]
        kind = "DATA" if hi["rs"] == 1 else "CMD"
        if cmd_count < 30:
            if kind == "DATA" and full_byte >= 0x20 and full_byte < 0x7F:
                print(f"  {kind}: 0x{full_byte:02X} = '{chr(full_byte)}'")
            else:
                desc = ""
                if kind == "CMD":
                    if full_byte == 0x01:
                        desc = " (clear display)"
                    elif full_byte == 0x02:
                        desc = " (return home)"
                    elif full_byte & 0xFC == 0x04:
                        desc = f" (entry mode: I/D={'inc' if full_byte&2 else 'dec'}, S={'shift' if full_byte&1 else 'no'})"
                    elif full_byte & 0xF8 == 0x08:
                        d = "on" if full_byte & 4 else "off"
                        c = "on" if full_byte & 2 else "off"
                        b = "blink" if full_byte & 1 else "no"
                        desc = f" (display {d}, cursor {c}, {b})"
                    elif full_byte & 0xF0 == 0x20:
                        dl = "8bit" if full_byte & 0x10 else "4bit"
                        n = "2line" if full_byte & 0x08 else "1line"
                        f = "5x10" if full_byte & 0x04 else "5x8"
                        desc = f" (function set: {dl}, {n}, {f})"
                    elif full_byte & 0x80:
                        desc = f" (set DDRAM addr 0x{full_byte & 0x7F:02X})"
                    elif full_byte & 0x40:
                        desc = f" (set CGRAM addr 0x{full_byte & 0x3F:02X})"
                print(f"  {kind}: 0x{full_byte:02X}{desc}")
        elif cmd_count == 30:
            print(f"  ... (showing first 30 of remaining)")
        cmds.append({"byte": full_byte, "kind": kind, "rs": hi["rs"]})
        i += 2
        cmd_count += 1

    # Summary: extract text written to LCD
    text = []
    for c in cmds:
        if c["rs"] == 1 and c["byte"] >= 0x20 and c["byte"] < 0x7F:
            text.append(chr(c["byte"]))
        elif c["rs"] == 0 and c["byte"] & 0x80:
            addr = c["byte"] & 0x7F
            if addr == 0x40:
                text.append('\n')  # line 2
    if text:
        print()
        print("LCD text output:")
        print("  " + "".join(text).replace('\n', '\n  '))


if __name__ == "__main__":
    main()
