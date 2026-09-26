#!/usr/bin/env python3
"""Emits small screenshots from the self-test as base64 notice annotations.

GitHub keeps annotations on the run's page (readable without signing in),
each up to 4 KB, at most 10 per step. Each step prints its share:

    python3 windows/tests/previews.py SCREENS_DIR STEP
"""
import base64
import glob
import os
import sys

folder, step = sys.argv[1], int(sys.argv[2])
wanted = ["play", "graphics-presets", "graphics-engine", "style-cursor", "launcher-look", "launcher-general", "link-window"]
chunks = []
for path in sorted(glob.glob(os.path.join(folder, "small", "*.jpg"))):
    name = os.path.basename(path)[3:-4]
    if name not in wanted:
        continue
    data = base64.b64encode(open(path, "rb").read()).decode()
    parts = [data[i:i + 3900] for i in range(0, len(data), 3900)]
    for i, part in enumerate(parts):
        chunks.append((f"shot {name} {i + 1}/{len(parts)}", part))
print(f"{len(chunks)} pieces in total", file=sys.stderr)
for title, part in chunks[step * 10:(step + 1) * 10]:
    print(f"::notice title={title}::{part}")
