#!/usr/bin/env python3
"""Build a VID/PID -> {name, path} manifest from a local clone of the-via/keyboards.

Outputs a single JSON file: {"<vid_hex>:<pid_hex>": {"name": ..., "path": "v3/..."}, ...}
Multiple boards can share VID/PID (firmware variants); we keep all under a list.
"""
import json
import os
import sys
from pathlib import Path

REPO = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
OUT  = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("via_keyboards_manifest.json")

V3  = REPO / "v3"
SRC = REPO / "src"
ROOTS = [p for p in [V3, SRC] if p.exists()]
if not ROOTS:
    print(f"neither v3/ nor src/ found under {REPO}", file=sys.stderr); sys.exit(1)

def parse_hex16(v):
    if v is None: return None
    if isinstance(v, int): return v
    s = str(v).strip()
    if s.lower().startswith("0x"): s = s[2:]
    try:
        n = int(s, 16)
        return n & 0xFFFF
    except ValueError:
        return None

manifest = {}
total = 0
skipped_no_id = 0
skipped_bad_json = 0

seen_paths_per_key = {}  # key -> set of (vid, pid) seen, to dedupe across roots

# v3/ is scanned first so canonical entries win the dedupe; src/ fills in
# boards (e.g., Keychron Q1 Pro) that haven't been promoted to v3 yet.
for root in ROOTS:
    for path in sorted(root.rglob("*.json")):
        total += 1
        try:
            with open(path, encoding="utf-8") as f:
                d = json.load(f)
        except Exception as e:
            skipped_bad_json += 1
            continue

        vid = parse_hex16(d.get("vendorId"))
        pid = parse_hex16(d.get("productId"))
        if vid is None or pid is None:
            skipped_no_id += 1
            continue

        rel = path.relative_to(REPO).as_posix()
        key = f"{vid:04X}:{pid:04X}"

        # Skip if we already have an entry from v3/ for this VID:PID.
        existing = manifest.get(key, [])
        if any(e["path"].startswith("v3/") for e in existing):
            continue
        # Skip duplicate within the same root.
        if any(e["path"] == rel for e in existing):
            continue

        entry = {"name": d.get("name"), "path": rel}
        manifest.setdefault(key, []).append(entry)

# Sort each entry list for deterministic output.
for k in manifest:
    manifest[k].sort(key=lambda e: e["path"])

# Sort the top-level keys for diff stability.
ordered = {k: manifest[k] for k in sorted(manifest.keys())}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(ordered, f, indent=0, separators=(",", ":"))
    f.write("\n")

print(f"scanned: {total}", file=sys.stderr)
print(f"skipped no id: {skipped_no_id}", file=sys.stderr)
print(f"skipped bad json: {skipped_bad_json}", file=sys.stderr)
print(f"unique vid:pid keys: {len(manifest)}", file=sys.stderr)
print(f"total entries: {sum(len(v) for v in manifest.values())}", file=sys.stderr)
print(f"output: {OUT} ({OUT.stat().st_size} bytes)", file=sys.stderr)
