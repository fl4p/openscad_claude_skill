#!/usr/bin/env python3
"""List the down-facing faces of an STL that no material sits under.

A 45 deg gusset off a wall only fixes an arm's ROOT.  Everything from the top of
that ramp out to the tip is a flat ceiling with nothing beneath it, and that is
what droops.  The .scad cannot see this -- it is a property of the print, not of
the CSG -- so it gets its own check, and the numbers it prints are the ones that
decide whether a feature needs support or a redesign.

    openscad-overhang-audit.py <part.stl> [--angle=45] [--min-area=3] [--bridge=10]

Reports each cluster of down-facing facets: its z, its footprint, its area, and
whether solid model material lies directly below it.  A ceiling with material
under it is a POCKET ROOF: the slicer bridges it if its short span is under
--bridge.  A ceiling with nothing under it is a CANTILEVER, and no slicer can
bridge to a second anchor that does not exist -- it needs support or a redesign.

Faces are grouped by z, so two separate features at the same height are reported
as one row and its `span` is then the distance between them, not a real span.
Read the x/y range: if it straddles the part, the row is two features.
"""
import sys, math, re, struct
from collections import defaultdict


def read_stl(path):
    with open(path, "rb") as f:
        head = f.read(84)
        if head[:5] != b"solid" or b"facet" not in f.read(200):
            f.seek(80)
            n = struct.unpack("<I", f.read(4))[0]
            for _ in range(n):
                d = struct.unpack("<12fH", f.read(50))
                yield d[0:3], (d[3:6], d[6:9], d[9:12])
            return
    nrm, vs = None, []
    for line in open(path):
        line = line.strip()
        if line.startswith("facet normal"):
            nrm = tuple(float(v) for v in line.split()[2:5]); vs = []
        elif line.startswith("vertex"):
            vs.append(tuple(float(v) for v in line.split()[1:4]))
        elif line.startswith("endfacet"):
            yield nrm, tuple(vs)


def area(v):
    a = [v[1][i] - v[0][i] for i in range(3)]
    b = [v[2][i] - v[0][i] for i in range(3)]
    c = (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
    return 0.5 * math.sqrt(sum(x*x for x in c))


def main(argv):
    path = argv[1] if len(argv) > 1 else "stack-frame.stl"
    ang = float(next((a.split("=")[1] for a in argv if a.startswith("--angle=")), 45))
    amin = float(next((a.split("=")[1] for a in argv if a.startswith("--min-area=")), 3))
    bridge = float(next((a.split("=")[1] for a in argv if a.startswith("--bridge=")), 10))
    nz_max = -math.cos(math.radians(ang))          # nz <= this is steeper than `ang`

    faces = list(read_stl(path))
    zmin = min(p[2] for _, v in faces for p in v)   # the face ON the bed is not an overhang
    # every upward face, as a z-sorted list per 1 mm XY cell -- what could hold a
    # support up, and what tells a pocket roof apart from a cantilever
    up = defaultdict(list)
    for n, v in faces:
        if n[2] > 0.7:
            zs = min(p[2] for p in v)
            for cx in range(int(min(p[0] for p in v)), int(max(p[0] for p in v)) + 1):
                for cy in range(int(min(p[1] for p in v)), int(max(p[1] for p in v)) + 1):
                    up[(cx, cy)].append(zs)

    groups = defaultdict(lambda: [0.0, 1e9, -1e9, 1e9, -1e9, set()])
    for n, v in faces:
        if n[2] > nz_max:
            continue
        z = round(min(p[2] for p in v), 1)
        if abs(z - zmin) < 0.05:
            continue
        g = groups[z]
        g[0] += area(v)
        for p in v:
            g[1] = min(g[1], p[0]); g[2] = max(g[2], p[0])
            g[3] = min(g[3], p[1]); g[4] = max(g[4], p[1])
        for cx in range(int(min(p[0] for p in v)), int(max(p[0] for p in v)) + 1):
            for cy in range(int(min(p[1] for p in v)), int(max(p[1] for p in v)) + 1):
                g[5].add((cx, cy))

    print(f"{path}: down-facing faces steeper than {ang:g} deg, area >= {amin:g} mm2")
    print(f"{'z':>7} {'area':>8}  {'x range':>15} {'y range':>15}  under it")
    worst = 0.0
    for z in sorted(groups):
        a, x0, x1, y0, y1, cells = groups[z]
        if a < amin:
            continue
        drops = [z - max([s for s in up.get(c, []) if s < z - 0.05], default=-1e9)
                 for c in cells]
        drop = max(drops) if drops else 0
        span = min(x1 - x0, y1 - y0)      # the short axis: what a bridge has to cross
        if drop > 1e8:
            # nothing under any part of it -- a cantilever.  No slicer can bridge
            # to a second anchor that is not there.
            kind = f"CANTILEVER, open to the bed          -> SUPPORT"
            worst = max(worst, a)
        elif span <= bridge:
            kind = f"pocket roof, {drop:.1f} mm deep, {span:.1f} mm span -> bridges"
        else:
            kind = f"pocket roof, {drop:.1f} mm deep, {span:.1f} mm span -> SUPPORT"
            worst = max(worst, a)
        print(f"{z:7.1f} {a:8.1f}  {x0:6.1f}..{x1:6.1f} {y0:6.1f}..{y1:6.1f}  {kind}")
    print(f"\nlargest face needing support: {worst:.0f} mm2"
          f" -- {'slice WITH support' if worst else 'self-supporting'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
