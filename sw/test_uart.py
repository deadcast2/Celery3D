#!/usr/bin/env python3
"""
Simple UART test - just clear screen to verify communication works
"""

import serial
import struct
import time
import sys

# Command bytes
CMD_CLEAR_FB = 0x01
CMD_CLEAR_DEPTH = 0x02
CMD_TRIANGLE = 0x03
CMD_SET_CONFIG = 0x04

def pack_rgb565(r, g, b):
    """Pack float RGB (0-1) to RGB565."""
    ri = int(min(r, 1.0) * 31)
    gi = int(min(g, 1.0) * 63)
    bi = int(min(b, 1.0) * 31)
    return (ri << 11) | (gi << 5) | bi

def float_to_fp(f):
    """Convert float to S15.16 fixed-point."""
    val = int(f * 65536)
    return val & 0xFFFFFFFF

def main():
    port = sys.argv[1] if len(sys.argv) > 1 else '/dev/ttyUSB0'

    print(f"Opening {port}...")
    ser = serial.Serial(port, 115200, timeout=1)
    time.sleep(0.5)

    print("\n=== Test 1: Clear screen to RED ===")
    color = pack_rgb565(1.0, 0.0, 0.0)  # Bright red
    print(f"Sending CLEAR_FB with color 0x{color:04X}")
    ser.write(bytes([CMD_CLEAR_FB]))
    ser.write(struct.pack('<H', color))
    ser.flush()
    time.sleep(0.5)
    input("Press Enter if screen is RED (or note what you see)...")

    print("\n=== Test 2: Clear screen to GREEN ===")
    color = pack_rgb565(0.0, 1.0, 0.0)  # Bright green
    print(f"Sending CLEAR_FB with color 0x{color:04X}")
    ser.write(bytes([CMD_CLEAR_FB]))
    ser.write(struct.pack('<H', color))
    ser.flush()
    time.sleep(0.5)
    input("Press Enter if screen is GREEN...")

    print("\n=== Test 3: Clear screen to BLUE ===")
    color = pack_rgb565(0.0, 0.0, 1.0)  # Bright blue
    print(f"Sending CLEAR_FB with color 0x{color:04X}")
    ser.write(bytes([CMD_CLEAR_FB]))
    ser.write(struct.pack('<H', color))
    ser.flush()
    time.sleep(0.5)
    input("Press Enter if screen is BLUE...")

    print("\n=== Test 4: Disable depth test, draw simple triangle ===")
    # Disable all features for simple test
    ser.write(bytes([CMD_SET_CONFIG, 0x00]))
    time.sleep(0.1)

    # Clear to dark blue
    color = pack_rgb565(0.0, 0.0, 0.2)
    ser.write(bytes([CMD_CLEAR_FB]))
    ser.write(struct.pack('<H', color))
    time.sleep(0.1)

    # Send a simple triangle (covers center of 64x64 screen)
    # Vertex format: x, y, z, w, u, v, r, g, b, a (each 4 bytes, little-endian)
    print("Sending triangle...")
    ser.write(bytes([CMD_TRIANGLE]))

    # v0: top center, red
    ser.write(struct.pack('<10I',
        float_to_fp(32.0),  # x
        float_to_fp(10.0),  # y
        float_to_fp(0.5),   # z
        float_to_fp(1.0),   # w
        float_to_fp(0.0),   # u
        float_to_fp(0.0),   # v
        float_to_fp(1.0),   # r
        float_to_fp(0.0),   # g
        float_to_fp(0.0),   # b
        float_to_fp(1.0),   # a
    ))

    # v1: bottom left, green
    ser.write(struct.pack('<10I',
        float_to_fp(10.0),  # x
        float_to_fp(54.0),  # y
        float_to_fp(0.5),   # z
        float_to_fp(1.0),   # w
        float_to_fp(0.0),   # u
        float_to_fp(0.0),   # v
        float_to_fp(0.0),   # r
        float_to_fp(1.0),   # g
        float_to_fp(0.0),   # b
        float_to_fp(1.0),   # a
    ))

    # v2: bottom right, blue
    ser.write(struct.pack('<10I',
        float_to_fp(54.0),  # x
        float_to_fp(54.0),  # y
        float_to_fp(0.5),   # z
        float_to_fp(1.0),   # w
        float_to_fp(0.0),   # u
        float_to_fp(0.0),   # v
        float_to_fp(0.0),   # r
        float_to_fp(0.0),   # g
        float_to_fp(1.0),   # b
        float_to_fp(1.0),   # a
    ))

    ser.flush()
    time.sleep(0.5)

    print("\nYou should see a RGB gradient triangle on dark blue background.")
    print("If you see nothing, the issue is in triangle rendering.")
    print("If clear colors worked but triangle didn't, check cmd_parser.")

    ser.close()
    print("\nDone.")

if __name__ == '__main__':
    main()
