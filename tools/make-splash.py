#!/usr/bin/env python3
"""Build the cluster splash: a single H.264 keyframe the sink can push on its own.

    tools/make-splash.py                  draw the default and encode it
    tools/make-splash.py picture.png      use your own picture instead
    tools/make-splash.py --preview        write the PNG only, do not encode

Output: build/splash.h264 (SPS + PPS + one IDR, Annex-B) and build/splash.png.

Why a keyframe: the decoder produces nothing until it is given one, and Type-111 sends one
only about every 29 s. A frame of our own fills that gap, and clears the stale last frame
after the phone disconnects.

Only the middle of the canvas is visible on the cluster — the dials cover roughly the
outer quarter on each side — so the default keeps everything well inside that band.

Needs Pillow and ffmpeg with libx264.
"""
import os
import subprocess
import sys

W, H = 1024, 384

# Measured visible band on the AID 10": about 24%-71% of the panel width.
SAFE_L, SAFE_R = int(W * 0.24), int(W * 0.71)

BG = (10, 13, 18)
DIM = (34, 42, 56)
MARK = (96, 116, 142)


def draw_default(path):
    from PIL import Image, ImageDraw

    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    cx, cy = (SAFE_L + SAFE_R) // 2, H // 2

    # A navigation arrow, the one shape that reads instantly on a cluster and needs no
    # words — nothing here should ask the driver to read.
    s = 46
    d.polygon([(cx, cy - s), (cx + s * 0.62, cy + s * 0.72),
               (cx, cy + s * 0.36), (cx - s * 0.62, cy + s * 0.72)], fill=MARK)

    # Three dots: something is coming, the picture is not frozen.
    for i in (-1, 0, 1):
        x = cx + i * 26
        d.ellipse([x - 4, cy + s + 30, x + 4, cy + s + 38], fill=DIM)

    im.save(path)
    return path


def fit(src, path):
    from PIL import Image

    im = Image.open(src).convert("RGB")
    # Cover, then centre-crop: letterboxing would waste the little width there is.
    scale = max(W / im.width, H / im.height)
    im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))),
                   Image.LANCZOS)
    left, top = (im.width - W) // 2, (im.height - H) // 2
    im.crop((left, top, left + W, top + H)).save(path)
    return path


def encode(png, out):
    subprocess.run([
        "ffmpeg", "-v", "error", "-y",
        "-i", png,
        "-frames:v", "1",
        "-c:v", "libx264",
        "-profile:v", "high",
        "-pix_fmt", "yuv420p",
        # The unit decodes what the phone sends at this size; keep the splash identical so
        # the decoder is handed the same geometry either way.
        "-s", "%dx%d" % (W, H),
        "-f", "h264", out,
    ], check=True)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    build = os.path.join(root, "build")
    os.makedirs(build, exist_ok=True)
    png = os.path.join(build, "splash.png")
    out = os.path.join(build, "splash.h264")

    args = [a for a in sys.argv[1:] if a != "--preview"]
    preview = "--preview" in sys.argv[1:]

    if args:
        fit(args[0], png)
        print("picture: %s -> %s" % (args[0], png))
    else:
        draw_default(png)
        print("drew the default -> %s" % png)

    if preview:
        return 0

    encode(png, out)
    size = os.path.getsize(out)
    print("encoded: %s (%d B)" % (out, size))

    # A splash without parameter sets would never decode; say so here rather than let it
    # fail silently on the unit.
    data = open(out, "rb").read()
    kinds = set()
    i = 0
    while True:
        j = data.find(b"\x00\x00\x01", i)
        if j < 0:
            break
        kinds.add(data[j + 3] & 0x1f)
        i = j + 3
    missing = {7: "SPS", 8: "PPS", 5: "IDR"}
    gaps = [n for k, n in missing.items() if k not in kinds]
    if gaps:
        print("WARNING: no %s in the output — the unit will not decode this"
              % ", ".join(gaps), file=sys.stderr)
        return 1
    print("contains SPS, PPS and an IDR")
    return 0


if __name__ == "__main__":
    sys.exit(main())
