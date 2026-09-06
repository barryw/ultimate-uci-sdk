#!/usr/bin/env python3
"""The original demo's three shapes, pre-shifted into image/mask pairs."""
import math
from pathlib import Path


def pixel(shape, x, y):
    dx, dy = x + 0.5 - 8, (y + 0.5) / 2 - 8
    distance = math.sqrt(dx * dx + dy * dy)
    if shape == 0:
        if distance > 7.9:
            return 0
        if math.sqrt((dx + 2.7) ** 2 + (dy + 2.7) ** 2) < 2.3:
            return 3
        return 1 if distance > 6.4 else 2
    if shape == 1:
        distance = abs(dx) + abs(dy)
        if distance > 7.9:
            return 0
        if distance > 6.2:
            return 1
        return 3 if distance < 2.6 else 2
    if distance > 7.9 or distance < 3.6:
        return 0
    if distance > 6.6 or distance < 4.8:
        return 1
    return 3 if dy < -2 and dx < 0 else 2


def build():
    data = bytearray()
    for shape in range(3):
        for shift in range(4):
            for mask in (False, True):
                for column in range(5):
                    for row in range(32):
                        byte = 0
                        for pair in range(4):
                            x = column * 4 + pair - shift
                            value = pixel(shape, x, row) if 0 <= x < 16 else 0
                            if mask:
                                value = 3 if value == 0 else 0
                            byte |= value << (6 - 2 * pair)
                        data.append(byte)
    return bytes(data)


if __name__ == "__main__":
    output = Path(__file__).with_name("build") / "shapes.bin"
    output.parent.mkdir(exist_ok=True)
    output.write_bytes(build())
