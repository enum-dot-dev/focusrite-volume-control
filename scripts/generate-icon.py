#!/usr/bin/env python3
"""
Generate app icon for Volume Control.
Creates a 1024x1024 master icon and all required sizes for AppIcon.appiconset.
Uses only Python standard library + macOS sips for resizing.
"""

import subprocess
import struct
import zlib
import os
import math

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
ICON_DIR = os.path.join(PROJECT_DIR, "Focusrite Volume Control", "Assets.xcassets", "AppIcon.appiconset")

# Required sizes: (width, scale, filename)
ICON_SIZES = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png"),
]

MASTER_SIZE = 1024


def create_png(width, height, pixels):
    """Create a PNG file from raw RGBA pixel data."""
    def make_chunk(chunk_type, data):
        chunk = chunk_type + data
        return struct.pack(">I", len(data)) + chunk + struct.pack(">I", zlib.crc32(chunk) & 0xFFFFFFFF)

    # PNG signature
    signature = b'\x89PNG\r\n\x1a\n'

    # IHDR
    ihdr_data = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # 8-bit RGBA
    ihdr = make_chunk(b'IHDR', ihdr_data)

    # IDAT - raw pixel data with filter bytes
    raw_data = b''
    for y in range(height):
        raw_data += b'\x00'  # no filter
        for x in range(width):
            idx = (y * width + x) * 4
            raw_data += bytes(pixels[idx:idx+4])

    compressed = zlib.compress(raw_data, 9)
    idat = make_chunk(b'IDAT', compressed)

    # IEND
    iend = make_chunk(b'IEND', b'')

    return signature + ihdr + idat + iend


def lerp(a, b, t):
    return a + (b - a) * t


def draw_icon(size):
    """Draw the app icon at the given size. Returns RGBA pixel list."""
    pixels = [0] * (size * size * 4)

    center = size / 2.0
    radius = size * 0.44  # rounded rect "radius"
    corner_r = size * 0.185  # corner radius

    # Colors
    bg_dark = (28, 28, 30)       # dark background
    bg_mid = (44, 44, 46)        # slightly lighter
    accent = (220, 60, 60)       # Focusrite red
    accent_light = (255, 100, 80)
    knob_dark = (58, 58, 62)
    knob_light = (90, 90, 96)
    tick_color = (160, 160, 166)

    def in_rounded_rect(x, y, cx, cy, hw, hh, cr):
        """Check if point is inside a rounded rectangle."""
        dx = abs(x - cx) - (hw - cr)
        dy = abs(y - cy) - (hh - cr)
        if dx <= 0 or dy <= 0:
            return abs(x - cx) <= hw and abs(y - cy) <= hh
        return dx * dx + dy * dy <= cr * cr

    def dist(x1, y1, x2, y2):
        return math.sqrt((x1 - x2) ** 2 + (y1 - y2) ** 2)

    # Knob params
    knob_cx = center
    knob_cy = center + size * 0.02
    knob_r = size * 0.25

    # Draw each pixel
    for y in range(size):
        for x in range(size):
            idx = (y * size + x) * 4

            # Check if inside rounded rect
            if not in_rounded_rect(x, y, center, center, radius, radius, corner_r):
                pixels[idx:idx+4] = [0, 0, 0, 0]
                continue

            # Background gradient (subtle top-to-bottom)
            t = y / size
            r = int(lerp(bg_mid[0], bg_dark[0], t))
            g = int(lerp(bg_mid[1], bg_dark[1], t))
            b = int(lerp(bg_mid[2], bg_dark[2], t))

            d = dist(x, y, knob_cx, knob_cy)

            # Volume knob (outer ring)
            knob_outer_r = knob_r + size * 0.025
            if d <= knob_outer_r and d > knob_r:
                ring_t = (d - knob_r) / (knob_outer_r - knob_r)
                r = int(lerp(knob_light[0], bg_dark[0], ring_t))
                g = int(lerp(knob_light[1], bg_dark[1], ring_t))
                b = int(lerp(knob_light[2], bg_dark[2], ring_t))
            # Volume knob (body)
            elif d <= knob_r:
                # Subtle radial gradient on knob
                knob_t = d / knob_r
                r = int(lerp(knob_light[0], knob_dark[0], knob_t * 0.7))
                g = int(lerp(knob_light[1], knob_dark[1], knob_t * 0.7))
                b = int(lerp(knob_light[2], knob_dark[2], knob_t * 0.7))

                # Indicator line (points to ~2 o'clock position, ~60 degrees from top)
                angle = math.atan2(y - knob_cy, x - knob_cx)
                indicator_angle = -math.pi * 0.33  # roughly 60 degrees from top
                angle_diff = abs(angle - indicator_angle)
                if angle_diff > math.pi:
                    angle_diff = 2 * math.pi - angle_diff

                line_width = size * 0.025
                angle_threshold = math.atan2(line_width, d) if d > 0 else math.pi
                if angle_diff < angle_threshold and d > knob_r * 0.3 and d < knob_r * 0.9:
                    r, g, b = accent[0], accent[1], accent[2]

            # Tick marks around the knob (arc from ~7 o'clock to ~5 o'clock)
            tick_ring_r = knob_r + size * 0.06
            tick_ring_outer = knob_r + size * 0.10
            if d >= tick_ring_r and d <= tick_ring_outer:
                angle = math.atan2(y - knob_cy, x - knob_cx)
                # Arc from 120 degrees to 420 degrees (= 60 degrees), covering bottom gap
                # In standard math: start at ~7 o'clock (150 deg) going clockwise to ~5 o'clock (30 deg)
                # Normalize angle to 0..2pi
                norm_angle = angle % (2 * math.pi)
                # Dead zone at bottom (from ~100deg to ~80deg, i.e., around 90deg / south)
                # Let's say dead zone is from 60deg to 120deg (pi/3 to 2pi/3)
                dead_start = math.pi * 0.38
                dead_end = math.pi * 0.62
                in_dead_zone = dead_start <= norm_angle <= dead_end

                if not in_dead_zone:
                    # Draw tick marks every 30 degrees
                    num_ticks = 11
                    arc_start = dead_end
                    arc_range = 2 * math.pi - (dead_end - dead_start)
                    for i in range(num_ticks):
                        tick_angle = arc_start + (arc_range * i / (num_ticks - 1))
                        tick_angle = tick_angle % (2 * math.pi)
                        tick_diff = abs(norm_angle - tick_angle)
                        if tick_diff > math.pi:
                            tick_diff = 2 * math.pi - tick_diff
                        tick_width = math.atan2(size * 0.008, d) if d > 0 else 0
                        if tick_diff < tick_width:
                            # Color ticks - first ~70% are red (active), rest are gray
                            if i < 8:
                                r, g, b = accent[0], accent[1], accent[2]
                            else:
                                r, g, b = tick_color[0], tick_color[1], tick_color[2]

            # Small "F" letter at top
            fx = center
            fy = center - knob_r - size * 0.12
            f_size = size * 0.045
            dx_f = abs(x - fx)
            dy_f = y - (fy - f_size)
            if dx_f < f_size * 0.8 and 0 <= dy_f <= f_size * 2:
                # Vertical bar of F
                if dx_f < f_size * 0.2:
                    r, g, b = accent_light[0], accent_light[1], accent_light[2]
                # Top horizontal bar
                elif dy_f < f_size * 0.3:
                    r, g, b = accent_light[0], accent_light[1], accent_light[2]
                # Middle horizontal bar
                elif f_size * 0.85 < dy_f < f_size * 1.15 and dx_f < f_size * 0.55:
                    r, g, b = accent_light[0], accent_light[1], accent_light[2]

            # Anti-aliased edge of rounded rect
            edge_dist = 0
            ex = abs(x - center) - (radius - corner_r)
            ey = abs(y - center) - (radius - corner_r)
            if ex > 0 and ey > 0:
                edge_dist = math.sqrt(ex * ex + ey * ey) - corner_r
            elif ex > 0:
                edge_dist = ex - (radius - abs(y - center))
                if edge_dist < -1:
                    edge_dist = -2
            elif ey > 0:
                edge_dist = ey - (radius - abs(x - center))
                if edge_dist < -1:
                    edge_dist = -2

            alpha = 255
            if edge_dist > -1 and edge_dist <= 0:
                alpha = int(255 * (1.0 + edge_dist))

            r = max(0, min(255, r))
            g = max(0, min(255, g))
            b = max(0, min(255, b))

            pixels[idx] = r
            pixels[idx + 1] = g
            pixels[idx + 2] = b
            pixels[idx + 3] = alpha

    return pixels


def main():
    os.makedirs(ICON_DIR, exist_ok=True)

    # Generate master icon
    print(f"Generating {MASTER_SIZE}x{MASTER_SIZE} master icon...")
    master_pixels = draw_icon(MASTER_SIZE)
    master_path = os.path.join(ICON_DIR, "icon_512x512@2x.png")
    png_data = create_png(MASTER_SIZE, MASTER_SIZE, master_pixels)
    with open(master_path, 'wb') as f:
        f.write(png_data)
    print(f"  Written: {master_path}")

    # Generate each required size using sips
    for base_size, scale, filename in ICON_SIZES:
        px = base_size * scale
        out_path = os.path.join(ICON_DIR, filename)

        if px == MASTER_SIZE:
            # Already generated
            continue

        if px >= 512:
            # Generate directly for better quality at large sizes
            print(f"Generating {px}x{px} ({filename})...")
            icon_pixels = draw_icon(px)
            png_data = create_png(px, px, icon_pixels)
            with open(out_path, 'wb') as f:
                f.write(png_data)
        else:
            # Resize from master using sips
            print(f"Resizing to {px}x{px} ({filename})...")
            subprocess.run([
                "sips", "-z", str(px), str(px),
                master_path, "--out", out_path
            ], capture_output=True)

        print(f"  Written: {out_path}")

    # Update Contents.json
    contents = {
        "images": [],
        "info": {"author": "xcode", "version": 1}
    }
    for base_size, scale, filename in ICON_SIZES:
        entry = {
            "filename": filename,
            "idiom": "mac",
            "scale": f"{scale}x",
            "size": f"{base_size}x{base_size}"
        }
        contents["images"].append(entry)

    import json
    contents_path = os.path.join(ICON_DIR, "Contents.json")
    with open(contents_path, 'w') as f:
        json.dump(contents, f, indent=2)
    print(f"  Updated: {contents_path}")

    print("\nDone! App icon generated.")


if __name__ == "__main__":
    main()
