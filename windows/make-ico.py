#!/usr/bin/env python3
"""Packs the PNGs from app/make-icon.swift into windows/Assets/AppleLabs.ico.

    swiftc -O app/make-icon.swift -o make-icon && ./make-icon AppIcon.iconset
    python3 windows/make-ico.py AppIcon.iconset

Also copies the 512 px picture to windows/Assets/Logo.png for the sidebar.
"""
import os
import shutil
import struct
import sys

iconset = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.iconset"
here = os.path.dirname(os.path.abspath(__file__))
sizes = [(16, "icon_16x16.png"), (32, "icon_32x32.png"), (48, None), (64, "icon_32x32@2x.png"),
         (128, "icon_128x128.png"), (256, "icon_256x256.png")]

images = []
for size, name in sizes:
    if name is None:
        continue
    with open(os.path.join(iconset, name), "rb") as f:
        images.append((size, f.read()))

# An ICO is a directory of entries; since Windows Vista each entry may be a whole PNG.
header = struct.pack("<HHH", 0, 1, len(images))
offset = 6 + 16 * len(images)
entries, data = b"", b""
for size, png in images:
    dim = 0 if size >= 256 else size
    entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(png), offset + len(data))
    data += png

with open(os.path.join(here, "Assets", "AppleLabs.ico"), "wb") as f:
    f.write(header + entries + data)
shutil.copy(os.path.join(iconset, "icon_256x256@2x.png"), os.path.join(here, "Assets", "Logo.png"))
print("wrote", os.path.join(here, "Assets", "AppleLabs.ico"))
