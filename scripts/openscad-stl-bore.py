#!/usr/bin/env python3
"""openscad-stl-bore.py — recover the NOMINAL diameter of a round feature from an STL.

    openscad-stl-bore.py part.stl --at 25.9,18.4 [--zrange 0,10] [--max-r 8]

WHY THIS EXISTS

The .scad source describes the part you are about to print. It does NOT describe
the part already sitting on the bench — the source has moved on since, and the
mating dimension went with it. When you need to fit something to an object that
already exists, the STL you shipped to the slicer is the artifact of record, and
the source is only a proxy for it.

Measured cost of confusing the two: a case whose shell was printed with a Ø4.95
socket, while the source (three commits later) said Ø4.60. Every barrel sized
from the source would have rattled. Reading the shipped mesh gave 4.95 exactly.

WHY THE NUMBER COMES BACK EXACT

OpenSCAD's circle()/cylinder() place their vertices ON the nominal circle — the
polygon is inscribed. So the largest vertex radius about the axis IS the nominal
radius, to full precision, however coarse $fn was. That makes this a measurement
of design intent, not an estimate.

Two numbers are reported because both are real:
  nominal   2*max vertex radius     — what the model asked for
  inscribed 2*r*cos(pi/n)           — the tightest material, what a pin feels

Exact recovery holds for CYLINDERS. A cone (countersink, lead-in chamfer) has
its vertices interpolated along the taper, so its band reads a few hundredths
low — near enough to identify the feature, not a dimension to design against.

Any surface at a constant distance from the chosen axis lands in a band: a
rounded case corner will happily look like a Ø8.2 circle. Bands are therefore
kept only when their vertices wrap the axis with no angular gap wider than
--max-gap. Partial arcs are dropped, and --keep-arcs shows them when the thing
you are measuring genuinely is one.

WHAT IT REFUSES TO DO

No path returns a diameter it did not measure. An unreadable file, an axis with
no vertices near it, or a radius band containing a single stray point all exit
non-zero. A feature that cannot be found is reported as NOT FOUND, never as 0.
"""

import argparse
import math
import struct
import sys
from typing import NoReturn


def die(msg) -> NoReturn:
    print(f"BORE-MEASURE FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def load_stl(path):
    """Return an (N,3) list of vertices. Handles both ASCII and binary STL."""
    try:
        raw = open(path, "rb").read()
    except OSError as e:
        die(f"cannot read {path}: {e}")
    if not raw:
        die(f"empty file: {path}")

    # Binary STL: 80-byte header, uint32 count, then 50 bytes per triangle.
    # The ASCII sniff must not be fooled by a binary file whose header happens
    # to start with 'solid' — check the declared triangle count against the
    # actual length instead.
    if len(raw) >= 84:
        n = struct.unpack("<I", raw[80:84])[0]
        if len(raw) == 84 + n * 50 and n > 0:
            verts = []
            for i in range(n):
                off = 84 + i * 50 + 12
                verts.extend(struct.unpack("<9f", raw[off:off + 36])[j:j + 3]
                             for j in (0, 3, 6))
            return [tuple(v) for v in verts]

    verts = []
    try:
        text = raw.decode("utf-8", errors="replace")
    except Exception as e:
        die(f"cannot decode {path}: {e}")
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("vertex "):
            p = line.split()
            if len(p) < 4:
                die(f"malformed vertex line: {line!r}")
            verts.append((float(p[1]), float(p[2]), float(p[3])))
    if not verts:
        die(f"no vertices found in {path} — not an STL, or an empty solid")
    return verts


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("stl")
    ap.add_argument("--at", required=True, metavar="X,Y",
                    help="axis of the round feature, in model coordinates")
    ap.add_argument("--zrange", metavar="ZMIN,ZMAX",
                    help="restrict to this z band (default: whole part)")
    ap.add_argument("--max-r", type=float, default=12.0,
                    help="ignore vertices further than this from the axis")
    ap.add_argument("--min-count", type=int, default=6,
                    help="a radius band needs this many vertices to be a circle")
    ap.add_argument("--max-gap", type=float, default=60.0, metavar="DEG",
                    help="largest angular gap a band may have and still count "
                         "as a full circle (default 60)")
    ap.add_argument("--keep-arcs", action="store_true",
                    help="also report partial arcs, with their angular span")
    args = ap.parse_args()

    try:
        ax, ay = (float(v) for v in args.at.split(","))
    except ValueError:
        die(f"--at wants X,Y — got {args.at!r}")
    zmin, zmax = -math.inf, math.inf
    if args.zrange:
        try:
            zmin, zmax = (float(v) for v in args.zrange.split(","))
        except ValueError:
            die(f"--zrange wants ZMIN,ZMAX — got {args.zrange!r}")

    verts = load_stl(args.stl)

    # Bucket by radius. Vertices of one cylinder share a radius to ~1e-4.
    bands = {}
    for x, y, z in verts:
        if not (zmin <= z <= zmax):
            continue
        dx, dy = x - ax, y - ay
        r = math.hypot(dx, dy)
        if r < 1e-6 or r > args.max_r:
            continue
        bands.setdefault(round(r, 3), []).append((z, math.atan2(dy, dx)))

    def widest_gap(angles):
        """Largest angular gap, in degrees, walking the sorted angles once round."""
        a = sorted(set(round(t, 6) for t in angles))
        if len(a) < 2:
            return 360.0
        gaps = [b - c for b, c in zip(a[1:], a[:-1])]
        gaps.append(a[0] + 2 * math.pi - a[-1])   # wrap-around
        return math.degrees(max(gaps))

    scored = {r: (pts, widest_gap([t for _, t in pts]))
              for r, pts in bands.items() if len(pts) >= args.min_count}
    full = {r: v for r, v in scored.items() if v[1] <= args.max_gap}
    arcs = {r: v for r, v in scored.items() if v[1] > args.max_gap}

    shown = full if not args.keep_arcs else scored
    if not shown:
        die(f"no round feature at ({ax}, {ay}) within r<{args.max_r}"
            f"{'' if not args.zrange else ' in z ' + args.zrange}"
            f" — {len(bands)} radius band(s), {len(scored)} with enough vertices,"
            f" none closing a full circle. Wrong axis, wrong units, or the"
            f" feature is not there. Re-run with --keep-arcs to see the arcs.")

    print(f"{args.stl}  axis=({ax}, {ay})"
          f"{'' if not args.zrange else '  z=' + args.zrange}")
    print(f"{'nominal Ø':>11}  {'inscribed Ø':>11}  {'z from':>8}  {'z to':>8}"
          f"  {'verts':>6}  {'~$fn':>5}  {'gap°':>6}")
    for r in sorted(shown):
        pts, gap = shown[r]
        zs = [z for z, _ in pts]
        # Vertices per full turn: the band may span several z levels, so infer
        # $fn from the count at a single level rather than the total.
        levels = len(set(round(z, 3) for z in zs))
        fn = len(pts) // max(levels, 1)
        insc = 2 * r * math.cos(math.pi / fn) if fn >= 3 else float("nan")
        print(f"{2*r:11.3f}  {insc:11.3f}  {min(zs):8.3f}  {max(zs):8.3f}"
              f"  {len(pts):6d}  {fn:5d}  {gap:6.1f}")
    if arcs and not args.keep_arcs:
        print(f"\n{len(arcs)} partial arc(s) suppressed (gap > {args.max_gap}°)."
              " These are corner blends and wall tangents, not features."
              " --keep-arcs to see them.")


if __name__ == "__main__":
    main()
