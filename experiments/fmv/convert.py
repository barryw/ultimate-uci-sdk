#!/usr/bin/env python3
"""Offline multicolor bitmap encoder; previews are decoded from the packed bytes."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

# Share the fixed palette already used by the SDK's bitmap renderer.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bobs"))
from render import PAL

FRAME_BYTES = 10049
WEIGHTS = np.array([0.299, 0.587, 0.114], dtype=np.float32)

# Spatial cleanup only: preserve large edges, merge small RGB differences.
# Explicit GBR planes avoid smoothing only luma or subsampling chroma.
GENTLE_FILTER = ("format=gbrp,bilateral=sigmaS=1:sigmaR=0.06:planes=7,format=rgb24,"
                 "lutrgb=r='min(255,floor(val/8+0.5)*8)':"
                 "g='min(255,floor(val/8+0.5)*8)':b='min(255,floor(val/8+0.5)*8)'")


def custom_palette(rgb):
    """Reserve index zero for black; median-cut the remaining fifteen colors."""
    quantized = Image.fromarray(rgb).quantize(colors=15, method=Image.Quantize.MEDIANCUT)
    entries = quantized.getpalette()[:45]
    colors = np.array(entries + [0] * (45 - len(entries)), dtype=np.uint8).reshape(15, 3)
    # Stable brightness ordering avoids arbitrary palette-slot permutations.
    colors = colors[np.argsort(colors @ WEIGHTS, kind="stable")]
    return np.vstack([np.zeros((1, 3), dtype=np.uint8), colors])


def shot_ranges(starts, frame_count):
    """Explicit, zero-based shot starts; a transition may share a palette."""
    if (not starts or starts[0] != 0 or starts != sorted(set(starts))
            or starts[-1] >= frame_count):
        raise ValueError("shot starts must be unique, increasing, start at 0 and precede frame count")
    return list(zip(starts, starts[1:] + [frame_count]))


def shot_palette(paths):
    # Sample the whole shot with bounded memory, including both endpoints.
    samples = np.linspace(0, len(paths) - 1, min(32, len(paths)), dtype=int)
    rgb = np.concatenate([np.asarray(Image.open(paths[i]).convert("RGB")) for i in samples])
    return custom_palette(rgb)


def encode(rgb, palette):
    """Black background + three local colors per cell, packed in VIC byte order.

    Greedy local-color selection followed by two coordinate-descent passes.
    The same fitting algorithm is used for fixed and custom palettes.
    """
    rgb = np.asarray(rgb, dtype=np.uint8)
    palette = np.asarray(palette, dtype=np.uint8)
    if rgb.shape != (200, 160, 3) or palette.shape != (16, 3):
        raise ValueError("expected 160x200 RGB pixels and sixteen RGB colors")
    cells = rgb.reshape(25, 8, 40, 4, 3).transpose(0, 2, 1, 3, 4).reshape(1000, 32, 3)
    delta = cells[:, :, None, :].astype(np.float32) - palette.astype(np.float32)
    error = (delta * delta * WEIGHTS).sum(axis=3)
    local = np.zeros((1000, 4), dtype=np.uint8)
    row = np.arange(1000)[:, None]
    pixel = np.arange(32)[None, :]
    best = error[:, :, 0]
    for slot in range(1, 4):
        local[:, slot] = np.minimum(best[:, :, None], error).sum(axis=1).argmin(axis=1)
        best = np.minimum(best, error[row, pixel, local[:, slot, None]])
    for _ in range(2):
        for slot in range(1, 4):
            others = np.delete(local, slot, axis=1)
            best = np.take_along_axis(error, others[:, None, :], axis=2).min(axis=2)
            local[:, slot] = np.minimum(best[:, :, None], error).sum(axis=1).argmin(axis=1)
    choices = np.take_along_axis(error, local[:, None, :], axis=2).argmin(axis=2)
    groups = choices.reshape(1000, 8, 4).astype(np.uint8)
    bitmap = ((groups[:, :, 0] << 6) | (groups[:, :, 1] << 4)
              | (groups[:, :, 2] << 2) | groups[:, :, 3]).tobytes()
    screen = ((local[:, 1] << 4) | local[:, 2]).tobytes()
    color = local[:, 3].tobytes()
    return bitmap + screen + color + bytes([0]) + palette.tobytes()


def decode(frame):
    """Independent VIC address/pixel decoding for preview and packing checks."""
    if len(frame) != FRAME_BYTES:
        raise ValueError("invalid frame size")
    data = np.frombuffer(frame, dtype=np.uint8)
    if data[10000] > 15 or np.any(data[9000:10000] > 15):
        raise ValueError("invalid VIC color index")
    y, x = np.indices((200, 160))
    cell = (y // 8) * 40 + x // 4
    bitmap_address = (y // 8) * 320 + (x // 4) * 8 + y % 8
    selector = (data[bitmap_address] >> (6 - 2 * (x % 4))) & 3
    colors = np.stack([np.full_like(cell, data[10000]), data[8000 + cell] >> 4,
                       data[8000 + cell] & 15, data[9000 + cell]])
    indices = np.take_along_axis(colors, selector[None], axis=0)[0]
    return data[10001:].reshape(16, 3)[indices]


def panel(images, palette_mode="frame", cleaned=False):
    preview = Image.new("RGB", (960, 264), "#15171b")
    draw = ImageDraw.Draw(preview)
    titles = ["SOURCE (160x200)", "FIXED C64 PALETTE", "CUSTOM PALETTE / " + palette_mode.upper()]
    if cleaned:
        titles[1:] = ["FIXED C64 + CLEANUP", palette_mode.upper() + " PALETTE + CLEANUP"]
    for i, (title, rgb) in enumerate(zip(titles, images)):
        draw.text((i * 320 + 8, 6), title, fill="white")
        preview.paste(Image.fromarray(rgb).resize((320, 240), Image.Resampling.NEAREST),
                      (i * 320, 24))
    return preview


def run(args):
    source = args.input.resolve()
    if not source.is_file():
        raise ValueError("input must be a local video file")
    args.output.mkdir(parents=True, exist_ok=False)
    inputs = args.output / "input"
    previews = args.output / "preview"
    inputs.mkdir()
    previews.mkdir()
    filters = []
    if args.crop:
        filters.append("crop=" + args.crop)
    # Fit the picture into a 4:3 display, then sample its non-square VIC pixels.
    filters.extend([f"fps={args.fps}", "scale=320:240:force_original_aspect_ratio=decrease",
                    "pad=320:240:(ow-iw)/2:(oh-ih)/2", "scale=160:200:flags=area", "setsar=1"])
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", str(args.start),
                    "-i", str(source), "-t", str(args.seconds), "-vf", ",".join(filters),
                    str(inputs / "%05d.png")], check=True)
    paths = sorted(inputs.glob("*.png"))
    if not paths:
        raise ValueError("no frames in selected interval")
    source_paths = paths
    if args.preprocess == "gentle":
        cleaned = args.output / "cleaned"
        cleaned.mkdir()
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-framerate", str(args.fps),
                        "-i", str(inputs / "%05d.png"), "-vf", GENTLE_FILTER,
                        str(cleaned / "%05d.png")], check=True)
        paths = sorted(cleaned.glob("*.png"))
        if len(paths) != len(source_paths):
            raise ValueError("preprocessing changed the frame count")
    shots = []
    if args.palette_mode == "shot":
        starts = [int(value) for value in args.shot_starts.split(",")]
        shots = [{"start": start, "end": end, "palette": shot_palette(paths[start:end])}
                 for start, end in shot_ranges(starts, len(paths))]
        print("shot ranges:", [(s["start"], s["end"]) for s in shots], flush=True)
    shot_index = 0
    metrics = []
    with (args.output / "fixed.frames").open("wb") as fixed_file, \
            (args.output / "custom.frames").open("wb") as custom_file:
        for index, path in enumerate(paths):
            rgb = np.asarray(Image.open(path).convert("RGB"))
            original = np.asarray(Image.open(source_paths[index]).convert("RGB"))
            fixed = encode(rgb, PAL)
            if shots:
                while index >= shots[shot_index]["end"]:
                    shot_index += 1
                palette = shots[shot_index]["palette"]
            else:
                palette = custom_palette(rgb)
            custom = encode(rgb, palette)
            fixed_file.write(fixed)
            custom_file.write(custom)
            decoded = [decode(fixed), decode(custom)]
            metrics.append([float(np.mean((original.astype(np.float32) - d) ** 2)) for d in decoded])
            preview = panel([original, *decoded], args.palette_mode, args.preprocess != "none")
            preview.save(previews / path.name)
            if index % 24 == 0:
                print(f"encoded {index + 1}/{len(paths)}", flush=True)
    metadata = {
        "format": "c64-multicolor-rgb-v1", "fps": args.fps, "frame_count": len(paths),
        "bytes_per_frame": FRAME_BYTES, "start_seconds": args.start,
        "duration_seconds": len(paths) / args.fps, "crop": args.crop,
        "palette_mode": args.palette_mode,
        "preprocess": args.preprocess,
        "preprocess_filter": GENTLE_FILTER if args.preprocess == "gentle" else None,
        "shots": [{"start_frame": s["start"], "end_frame_exclusive": s["end"],
                   "palette_rgb": s["palette"].tolist()} for s in shots],
        "source_url": args.source_url, "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "layout": {"bitmap": [0, 8000], "screen": [8000, 1000], "color_ram": [9000, 1000],
                   "background": [10000, 1], "palette_rgb": [10001, 48]},
        "fixed_palette_rgb": PAL, "mean_rgb_mse_fixed_custom": np.mean(metrics, axis=0).tolist(),
        "frame_rgb_mse_fixed_custom": metrics,
        "limitations": "Offline preview; no hardware scanout, palette transition, or audio timing simulation.",
    }
    (args.output / "manifest.json").write_text(json.dumps(metadata, indent=2) + "\n")
    # Original audio accompanies the preview; a separate PCM file is REU-friendly.
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-framerate", str(args.fps),
                    "-i", str(previews / "%05d.png"), "-ss", str(args.start), "-i", str(source),
                    "-map", "0:v", "-map", "1:a:0?", "-t", str(len(paths) / args.fps),
                    "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "aac",
                    "-movflags", "+faststart", str(args.output / "comparison.mp4")], check=True)
    audio = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                            "stream=index", "-of", "csv=p=0", str(source)],
                           check=True, capture_output=True, text=True).stdout.strip()
    if audio:
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", str(args.start),
                        "-i", str(source), "-t", str(len(paths) / args.fps), "-vn", "-ac", "1",
                        "-ar", "16000", "-f", "s8", str(args.output / "audio-16000hz-mono.s8")], check=True)
    sample_indices = np.linspace(0, len(paths) - 1, 6, dtype=int)
    sheet = Image.new("RGB", (960, 264 * 6))
    for row, index in enumerate(sample_indices):
        sheet.paste(Image.open(previews / paths[index].name), (0, row * 264))
    sheet.save(args.output / "comparison.png")
    print(json.dumps({k: v for k, v in metadata.items()
                      if k in ("frame_count", "duration_seconds", "palette_mode", "preprocess",
                               "mean_rgb_mse_fixed_custom")}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path, help="new output directory (must not exist)")
    parser.add_argument("--start", type=float, default=0)
    parser.add_argument("--seconds", type=float, default=8)
    parser.add_argument("--fps", type=int, default=24)
    parser.add_argument("--crop", help="ffmpeg crop w:h:x:y, in source pixels")
    parser.add_argument("--source-url", default="")
    parser.add_argument("--palette-mode", choices=["frame", "shot"], default="frame")
    parser.add_argument("--preprocess", choices=["none", "gentle"], default="none",
                        help="edge-preserving spatial smoothing and RGB steps of 8")
    parser.add_argument("--shot-starts", default="0",
                        help="comma-separated zero-based frame numbers; shot mode only")
    args = parser.parse_args()
    if args.start < 0 or args.seconds <= 0 or not 1 <= args.fps <= 60:
        parser.error("start must be nonnegative, duration positive, fps 1..60")
    run(args)
