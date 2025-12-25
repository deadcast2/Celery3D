#!/usr/bin/env python3
"""
Celery3D GPU - UART Cube Animation Driver
Sends a rotating textured cube to the GPU over UART

Usage: python3 cube_uart.py [serial_port]
Default: /dev/ttyUSB0
"""

import serial
import struct
import math
import time
import sys

# Screen resolution (must match FPGA)
SCREEN_WIDTH = 64
SCREEN_HEIGHT = 64

# Fixed-point parameters
FP_FRAC_BITS = 16

# Command bytes
CMD_CLEAR_FB = 0x01
CMD_CLEAR_DEPTH = 0x02
CMD_TRIANGLE = 0x03
CMD_SET_CONFIG = 0x04

# Config flags
CFG_TEX_ENABLE = 0x01
CFG_DEPTH_TEST = 0x02
CFG_DEPTH_WRITE = 0x04
CFG_BLEND_ENABLE = 0x08


# =============================================================================
# Fixed-point conversion
# =============================================================================

def float_to_fp(f):
    """Convert float to S15.16 fixed-point as unsigned 32-bit."""
    val = int(f * (1 << FP_FRAC_BITS))
    return val & 0xFFFFFFFF  # Treat as unsigned for packing


def pack_rgb565(r, g, b):
    """Pack float RGB (0-1) to RGB565."""
    ri = int(min(r, 1.0) * 31)
    gi = int(min(g, 1.0) * 63)
    bi = int(min(b, 1.0) * 31)
    return (ri << 11) | (gi << 5) | bi


# =============================================================================
# 3D Math Library
# =============================================================================

def mat4_identity():
    return [
        [1, 0, 0, 0],
        [0, 1, 0, 0],
        [0, 0, 1, 0],
        [0, 0, 0, 1]
    ]


def mat4_multiply(a, b):
    result = [[0]*4 for _ in range(4)]
    for i in range(4):
        for j in range(4):
            for k in range(4):
                result[i][j] += a[i][k] * b[k][j]
    return result


def mat4_transform(m, v):
    """Transform vec4 by mat4."""
    return [
        m[0][0]*v[0] + m[0][1]*v[1] + m[0][2]*v[2] + m[0][3]*v[3],
        m[1][0]*v[0] + m[1][1]*v[1] + m[1][2]*v[2] + m[1][3]*v[3],
        m[2][0]*v[0] + m[2][1]*v[1] + m[2][2]*v[2] + m[2][3]*v[3],
        m[3][0]*v[0] + m[3][1]*v[1] + m[3][2]*v[2] + m[3][3]*v[3],
    ]


def mat4_perspective(fov_y, aspect, near, far):
    tan_half_fov = math.tan(fov_y / 2.0)
    m = [[0]*4 for _ in range(4)]
    m[0][0] = 1.0 / (aspect * tan_half_fov)
    m[1][1] = 1.0 / tan_half_fov
    m[2][2] = -(far + near) / (far - near)
    m[2][3] = -(2.0 * far * near) / (far - near)
    m[3][2] = -1.0
    return m


def vec3_dot(a, b):
    return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]


def vec3_sub(a, b):
    return [a[0]-b[0], a[1]-b[1], a[2]-b[2]]


def vec3_cross(a, b):
    return [
        a[1]*b[2] - a[2]*b[1],
        a[2]*b[0] - a[0]*b[2],
        a[0]*b[1] - a[1]*b[0]
    ]


def vec3_scale(v, s):
    return [v[0]*s, v[1]*s, v[2]*s]


def vec3_length(v):
    return math.sqrt(vec3_dot(v, v))


def vec3_normalize(v):
    length = vec3_length(v)
    if length > 0.0001:
        return vec3_scale(v, 1.0 / length)
    return v


def mat4_look_at(eye, target, up):
    f = vec3_normalize(vec3_sub(target, eye))
    r = vec3_normalize(vec3_cross(f, up))
    u = vec3_cross(r, f)

    m = mat4_identity()
    m[0][0] = r[0]; m[0][1] = r[1]; m[0][2] = r[2]
    m[1][0] = u[0]; m[1][1] = u[1]; m[1][2] = u[2]
    m[2][0] = -f[0]; m[2][1] = -f[1]; m[2][2] = -f[2]

    m[0][3] = -vec3_dot(r, eye)
    m[1][3] = -vec3_dot(u, eye)
    m[2][3] = vec3_dot(f, eye)

    return m


def mat4_rotate_x(angle):
    m = mat4_identity()
    c, s = math.cos(angle), math.sin(angle)
    m[1][1] = c;  m[1][2] = -s
    m[2][1] = s;  m[2][2] = c
    return m


def mat4_rotate_y(angle):
    m = mat4_identity()
    c, s = math.cos(angle), math.sin(angle)
    m[0][0] = c;  m[0][2] = s
    m[2][0] = -s; m[2][2] = c
    return m


# =============================================================================
# Cube Geometry
# =============================================================================

# Cube vertex positions (24 vertices for separate face normals)
CUBE_POSITIONS = [
    # Front face
    [-1, -1,  1], [ 1, -1,  1], [ 1,  1,  1], [-1,  1,  1],
    # Back face
    [ 1, -1, -1], [-1, -1, -1], [-1,  1, -1], [ 1,  1, -1],
    # Top face
    [-1,  1,  1], [ 1,  1,  1], [ 1,  1, -1], [-1,  1, -1],
    # Bottom face
    [-1, -1, -1], [ 1, -1, -1], [ 1, -1,  1], [-1, -1,  1],
    # Right face
    [ 1, -1,  1], [ 1, -1, -1], [ 1,  1, -1], [ 1,  1,  1],
    # Left face
    [-1, -1, -1], [-1, -1,  1], [-1,  1,  1], [-1,  1, -1],
]

# UV coordinates for texture mapping
CUBE_UVS = [
    [0, 1], [1, 1], [1, 0], [0, 0],  # Front
    [0, 1], [1, 1], [1, 0], [0, 0],  # Back
    [0, 1], [1, 1], [1, 0], [0, 0],  # Top
    [0, 1], [1, 1], [1, 0], [0, 0],  # Bottom
    [0, 1], [1, 1], [1, 0], [0, 0],  # Right
    [0, 1], [1, 1], [1, 0], [0, 0],  # Left
]

# Face colors (Gouraud shading)
FACE_COLORS = [
    [1.0, 0.8, 0.8],  # Front - light red
    [0.8, 1.0, 0.8],  # Back - light green
    [0.8, 0.8, 1.0],  # Top - light blue
    [1.0, 1.0, 0.8],  # Bottom - light yellow
    [1.0, 0.8, 1.0],  # Right - light magenta
    [0.8, 1.0, 1.0],  # Left - light cyan
]

# Triangle indices (2 triangles per face, 12 total)
CUBE_INDICES = [
    0, 1, 2,  0, 2, 3,       # Front
    4, 5, 6,  4, 6, 7,       # Back
    8, 9, 10, 8, 10, 11,     # Top
    12, 13, 14, 12, 14, 15,  # Bottom
    16, 17, 18, 16, 18, 19,  # Right
    20, 21, 22, 20, 22, 23,  # Left
]


# =============================================================================
# Vertex Transformation
# =============================================================================

def transform_vertex(pos, uv, color, mvp):
    """Transform 3D vertex to screen space."""
    # Transform to clip space
    clip = mat4_transform(mvp, [pos[0], pos[1], pos[2], 1.0])

    # Perspective divide
    inv_w = 1.0 / clip[3]
    ndc_x = clip[0] * inv_w
    ndc_y = clip[1] * inv_w
    ndc_z = clip[2] * inv_w

    # NDC to screen coordinates
    x = (ndc_x + 1.0) * 0.5 * SCREEN_WIDTH
    y = (1.0 - ndc_y) * 0.5 * SCREEN_HEIGHT  # Flip Y
    z = (ndc_z + 1.0) * 0.5  # Map to [0, 1]

    # Use 1/clip.w for perspective-correct interpolation
    # Scale up to keep values in a range the fixed-point RTL handles well
    w = inv_w * 16.0

    return {
        'x': x, 'y': y, 'z': z, 'w': w,
        'u': uv[0], 'v': uv[1],
        'r': color[0], 'g': color[1], 'b': color[2],
        'a': 1.0
    }


# =============================================================================
# UART Command Functions
# =============================================================================

def send_clear_fb(ser, color_rgb565):
    """Send framebuffer clear command."""
    ser.write(bytes([CMD_CLEAR_FB]))
    ser.write(struct.pack('<H', color_rgb565))


def send_clear_depth(ser):
    """Send depth buffer clear command."""
    ser.write(bytes([CMD_CLEAR_DEPTH]))


def send_config(ser, flags):
    """Send configuration command."""
    ser.write(bytes([CMD_SET_CONFIG, flags]))


def send_vertex(ser, v):
    """Send a single vertex (40 bytes)."""
    # Pack vertex data as 10 little-endian 32-bit values
    data = struct.pack('<10I',
        float_to_fp(v['x']),
        float_to_fp(v['y']),
        float_to_fp(v['z']),
        float_to_fp(v['w']),
        float_to_fp(v['u']),
        float_to_fp(v['v']),
        float_to_fp(v['r']),
        float_to_fp(v['g']),
        float_to_fp(v['b']),
        float_to_fp(v['a'])
    )
    ser.write(data)


def send_triangle(ser, v0, v1, v2):
    """Send a triangle command with 3 vertices."""
    ser.write(bytes([CMD_TRIANGLE]))
    send_vertex(ser, v0)
    send_vertex(ser, v1)
    send_vertex(ser, v2)


# =============================================================================
# Main Animation Loop
# =============================================================================

def main():
    # Parse command line for serial port
    port = sys.argv[1] if len(sys.argv) > 1 else '/dev/ttyUSB0'

    print("=" * 50)
    print("Celery3D GPU - UART Cube Animation")
    print("=" * 50)
    print(f"Serial port: {port}")
    print(f"Resolution: {SCREEN_WIDTH}x{SCREEN_HEIGHT}")
    print()

    # Open serial port
    try:
        ser = serial.Serial(port, 115200, timeout=1)
        print(f"Opened {port} at 115200 baud")
    except serial.SerialException as e:
        print(f"Error opening {port}: {e}")
        print("\nUsage: python3 cube_uart.py [serial_port]")
        sys.exit(1)

    # Give FPGA time to initialize
    time.sleep(0.5)

    # Configure GPU: texture + depth test enabled
    config = CFG_DEPTH_TEST | CFG_DEPTH_WRITE
    send_config(ser, config)
    time.sleep(0.01)

    # Setup projection matrix (60 degree FOV)
    aspect = SCREEN_WIDTH / SCREEN_HEIGHT
    proj = mat4_perspective(60.0 * math.pi / 180.0, aspect, 0.1, 100.0)

    # Setup view matrix (camera at [0, 2, 5] looking at origin)
    eye = [0, 2, 5]
    target = [0, 0, 0]
    up = [0, 1, 0]
    view = mat4_look_at(eye, target, up)

    # Background color (dark blue)
    bg_color = pack_rgb565(0.1, 0.1, 0.25)

    print("Starting animation (Ctrl+C to stop)...")
    print()

    frame = 0
    try:
        while True:
            frame_start = time.time()

            # Calculate rotation angle (full rotation over 60 frames)
            angle = (frame % 60) / 60.0 * 2.0 * math.pi

            # Create model matrix (rotation around Y and X axes)
            model = mat4_multiply(mat4_rotate_y(angle), mat4_rotate_x(angle * 0.7))

            # Create MVP matrix
            mv = mat4_multiply(view, model)
            mvp = mat4_multiply(proj, mv)

            # Clear framebuffer and depth buffer
            send_clear_fb(ser, bg_color)
            send_clear_depth(ser)

            # Render the 12 triangles of the cube
            for i in range(0, 36, 3):
                face = i // 6
                color = FACE_COLORS[face]

                i0 = CUBE_INDICES[i]
                i1 = CUBE_INDICES[i + 1]
                i2 = CUBE_INDICES[i + 2]

                v0 = transform_vertex(CUBE_POSITIONS[i0], CUBE_UVS[i0], color, mvp)
                v1 = transform_vertex(CUBE_POSITIONS[i1], CUBE_UVS[i1], color, mvp)
                v2 = transform_vertex(CUBE_POSITIONS[i2], CUBE_UVS[i2], color, mvp)

                send_triangle(ser, v0, v1, v2)

            # Flush and wait for data to be sent
            ser.flush()

            # Calculate timing
            frame_time = time.time() - frame_start
            fps = 1.0 / frame_time if frame_time > 0 else 0

            # Print status every 10 frames
            if frame % 10 == 0:
                print(f"Frame {frame:4d} | {fps:.1f} FPS | {frame_time*1000:.1f} ms/frame")

            frame += 1

            # Small delay to avoid overwhelming the UART
            # At 115200 baud, each frame is ~1500 bytes = ~130ms minimum
            # Add a small buffer
            min_frame_time = 0.15  # 150ms = ~6.6 FPS max
            if frame_time < min_frame_time:
                time.sleep(min_frame_time - frame_time)

    except KeyboardInterrupt:
        print("\n\nAnimation stopped.")
        print(f"Total frames: {frame}")

    ser.close()
    print("Serial port closed.")


if __name__ == '__main__':
    main()
