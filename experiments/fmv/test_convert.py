import unittest

import numpy as np

from convert import FRAME_BYTES, PAL, GENTLE_FILTER, custom_palette, decode, encode, shot_ranges, shot_palette
from render import _colour_rows
from pathlib import Path
from tempfile import TemporaryDirectory
from PIL import Image
import subprocess


class FrameTest(unittest.TestCase):
    def test_gentle_cleanup_preserves_edges_and_endpoints(self):
        rgb = np.zeros((32, 32, 3), dtype=np.uint8)
        rgb[:, 16:] = 255
        # Low-amplitude compression-like noise in otherwise solid regions.
        rgb[8:24:2, 2:12:2] = 3
        rgb[8:24:2, 20:30:2] = 252
        with TemporaryDirectory() as directory:
            src, dst = Path(directory) / "in.png", Path(directory) / "out.png"
            Image.fromarray(rgb).save(src)
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(src),
                            "-vf", GENTLE_FILTER, "-frames:v", "1", str(dst)], check=True)
            cleaned = np.asarray(Image.open(dst).convert("RGB"))
        self.assertTrue(np.all(cleaned[:, :16] == 0))
        self.assertTrue(np.all(cleaned[:, 16:] == 255))

    def test_shot_boundaries_and_shared_palette(self):
        self.assertEqual(shot_ranges([0, 2], 4), [(0, 2), (2, 4)])
        for starts in ([], [1], [0, 0], [0, 3, 2], [0, 4], [0, -1]):
            with self.assertRaises(ValueError):
                shot_ranges(starts, 4)
        with TemporaryDirectory() as directory:
            paths = []
            for i, color in enumerate(([240, 30, 20], [20, 40, 230])):
                path = Path(directory) / (str(i) + ".png")
                Image.new("RGB", (160, 200), tuple(color)).save(path)
                paths.append(path)
            palette = shot_palette(paths)
            frames = [encode(np.asarray(Image.open(p)), palette) for p in paths]
            self.assertEqual(frames[0][10001:], frames[1][10001:])
            for p, frame in zip(paths, frames):
                np.testing.assert_array_equal(decode(frame), np.asarray(Image.open(p)))

    def test_exact_colors_and_independent_renderer(self):
        palette = np.array(PAL, dtype=np.uint8)
        y, x = np.indices((200, 160))
        # Four colors in every cell, changing across both cell boundaries.
        cell = (y // 8) * 40 + x // 4
        indices = np.where(x % 4 == 0, 0, (cell + x % 4) % 15 + 1)
        rgb = palette[indices]
        packed = encode(rgb, palette)
        self.assertEqual(len(packed), FRAME_BYTES)
        np.testing.assert_array_equal(decode(packed), rgb)
        bitmap, screen, color = packed[:8000], packed[8000:9000], packed[9000:10000]
        def colors(row, column):
            i = row * 40 + column
            return [packed[10000], screen[i] >> 4, screen[i] & 15, color[i]]
        independent = palette[np.array(_colour_rows(bitmap, colors))]
        np.testing.assert_array_equal(independent, rgb)

    def test_custom_and_bad_frame(self):
        rgb = np.full((200, 160, 3), [247, 121, 36], dtype=np.uint8)
        palette = custom_palette(rgb)
        self.assertEqual(palette.shape, (16, 3))
        np.testing.assert_array_equal(palette[0], [0, 0, 0])
        np.testing.assert_array_equal(decode(encode(rgb, palette)), rgb)
        with self.assertRaises(ValueError):
            decode(bytes(FRAME_BYTES - 1))
        with self.assertRaises(ValueError):
            encode(rgb[:10], palette)


if __name__ == "__main__":
    unittest.main()
