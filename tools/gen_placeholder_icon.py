#!/usr/bin/env python3
"""Generate the EmoPlay placeholder app icon (docs/SPEC.md §1).

Draws a simple vector-style mark: dark rounded square, a light play triangle
and an "E" bar glyph, rendered directly into an RGBA pixel buffer and written
as PNG (zlib). No third-party imaging dependency required.

Usage: python3 gen_placeholder_icon.py <output.png> [size]
"""
import struct
import sys
import zlib


def lerp(a, b, t):
    return a + (b - a) * t


def rounded_rect_mask(x, y, size, radius):
    """1 inside the rounded square, anti-aliased at the corners."""
    r = radius
    if r <= 0:
        return 1.0
    cx = min(max(x, r), size - r)
    cy = min(max(y, r), size - r)
    dist = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
    edge = max(size - r, r)
    if x < r or x > edge or y < r or y > edge:
        inside = dist <= r
        if inside:
            return 1.0
        return max(0.0, min(1.0, r - dist + 0.5))
    return 1.0 if (0 <= x < size and 0 <= y < size) else 0.0


def point_in_triangle(px, py, tri):
    (x1, y1), (x2, y2), (x3, y3) = tri
    d1 = (px - x2) * (y1 - y2) - (x1 - x2) * (py - y2)
    d2 = (px - x3) * (y2 - y3) - (x2 - x3) * (py - y3)
    d3 = (px - x1) * (y3 - y1) - (x3 - x1) * (py - y1)
    has_neg = d1 < 0 or d2 < 0 or d3 < 0
    has_pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (has_neg and has_pos)


def render(size):
    bg = (16, 20, 28)          # #10141c 深底
    fg = (235, 240, 248)       # 浅字
    accent = (96, 165, 250)    # 柔和蓝
    radius = size * 0.22
    rows = []
    for y in range(size):
        row = bytearray([0])  # filter type 0
        for x in range(size):
            m = rounded_rect_mask(x + 0.5, y + 0.5, size, radius)

            # play triangle (left-center)
            tri = [
                (size * 0.18, size * 0.26),
                (size * 0.18, size * 0.74),
                (size * 0.54, size * 0.50),
            ]
            # E glyph bars (right side)
            bar_x0, bar_x1 = size * 0.62, size * 0.82
            bars = [
                (size * 0.26, size * 0.33),
                (size * 0.465, size * 0.535),
                (size * 0.67, size * 0.74),
            ]

            px, py = x + 0.5, y + 0.5
            color = bg  # dark rounded-square base
            if point_in_triangle(px, py, tri):
                color = accent
            elif bar_x0 <= px <= bar_x1:
                for y0, y1 in bars:
                    if y0 <= py <= y1:
                        color = fg
                        break

            r, g, b = color
            row += bytes((int(r), int(g), int(b), int(255 * m)))
        rows.append(bytes(row))
    return b"".join(rows)


def write_png(path, size):
    raw = render(size)
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)
    print(f"wrote {path} ({size}x{size}, {len(png)} bytes)")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "emoplay_icon.png"
    size = int(sys.argv[2]) if len(sys.argv) > 2 else 512
    write_png(out, size)
