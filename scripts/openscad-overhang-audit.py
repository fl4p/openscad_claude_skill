#!/usr/bin/env python3
"""List the down-facing faces of an STL and say what, if anything, is under them.

    openscad-overhang-audit.py <part.stl> [--angle=45] [--min-area=3]

A 45 deg gusset off a wall fixes an arm's ROOT and nothing else: from the top of
that ramp out to the tip the underside is horizontal and anchored on one side,
and that is what droops.  The .scad cannot see this -- it is a property of the
print -- so it gets measured here instead of asserted in a comment.

WHAT THIS IS AND IS NOT
  It reports geometry: for every down-facing face, its height, its area, its
  footprint, and whether any solid surface lies below it.
  It does NOT decide that a face is fine.  Deciding "this bridges" needs the
  ANCHOR topology -- where the ceiling meets material that continues down, and
  how far apart two such anchors are -- and this tool does not compute it.  A
  roof with material below it may still be a one-sided shelf floating above an
  unrelated floor.  So a face with material below it is reported as needing a
  look at the sliced preview, never as passing.
  It is ADVISORY and it runs on the mesh in MODEL coordinates.  The slicer
  places the part; a rotation about X or Y invalidates every row here (a
  rotation about Z does not).  Nothing replaces looking at the sliced toolpaths.

  --angle is measured FROM HORIZONTAL: a face is reported when its underside
  lies within `angle` degrees of horizontal.  45 is the usual line; at 45 the
  from-horizontal and from-vertical conventions coincide, which is exactly why
  a wrong convention hides there -- so it is spelled out.

  Faces are grouped by z, so two separate features at the same height share a
  row and its footprint is then their union, not one feature.  Read the x/y
  range: if it straddles the part, the row is two things.
"""
import sys, math, os, struct
from collections import defaultdict


def read_stl(path):
    """Yield (v0, v1, v2). Binary is identified by its length, not by a sniff:
    a binary header may begin with 'solid', and an ASCII name may be longer
    than any fixed peek."""
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        f.seek(80)
        head = f.read(4)
        if len(head) == 4:
            n = struct.unpack("<I", head)[0]
            if size == 84 + 50 * n:
                for _ in range(n):
                    d = struct.unpack("<12fH", f.read(50))
                    yield d[3:6], d[6:9], d[9:12]
                return
    vs = []
    with open(path, "r", errors="strict") as f:
        for line in f:
            line = line.strip()
            if line.startswith("vertex"):
                vs.append(tuple(float(v) for v in line.split()[1:4]))
            elif line.startswith("endfacet"):
                if len(vs) != 3:
                    raise ValueError(f"{path}: facet with {len(vs)} vertices")
                yield tuple(vs); vs = []


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    opt = lambda k, d: float(next((a.split("=")[1] for a in argv
                                   if a.startswith("--" + k + "=")), d))
    path = args[0] if args else "part.stl"
    ang, amin = opt("angle", 45), opt("min-area", 3)
    if not 0 < ang < 90:
        sys.exit("--angle must be strictly between 0 and 90 (degrees from horizontal)")
    nz_max = -math.cos(math.radians(ang))

    # normals recomputed from the vertices -- a stored STL normal is a hint, not
    # a guarantee, and some exporters write zeros
    tris = []
    for v in read_stl(path):
        a = [v[1][i] - v[0][i] for i in range(3)]
        b = [v[2][i] - v[0][i] for i in range(3)]
        c = cross(a, b)
        m = math.sqrt(sum(x*x for x in c))
        if m == 0:
            continue
        tris.append((v, [x/m for x in c], 0.5*m))

    zmin = min(p[2] for v, _, _ in tris for p in v)

    def cells(v):
        for cx in range(math.floor(min(p[0] for p in v)),
                        math.floor(max(p[0] for p in v)) + 1):
            for cy in range(math.floor(min(p[1] for p in v)),
                            math.floor(max(p[1] for p in v)) + 1):
                yield (cx, cy)

    up = defaultdict(list)
    for v, n, _ in tris:
        if n[2] > 0.05:                       # any upward tilt at all counts
            z = min(p[2] for p in v)
            for c in cells(v):
                up[c].append(z)

    groups = defaultdict(lambda: [0.0, 1e9, -1e9, 1e9, -1e9, set()])
    for v, n, a in tris:
        if n[2] > nz_max:
            continue
        z = round(min(p[2] for p in v), 1)
        if abs(z - zmin) < 0.05:              # the face lying ON the bed
            continue
        g = groups[z]
        g[0] += a
        for p in v:
            g[1] = min(g[1], p[0]); g[2] = max(g[2], p[0])
            g[3] = min(g[3], p[1]); g[4] = max(g[4], p[1])
        g[5].update(cells(v))

    print(f"{path}: down-facing faces within {ang:g} deg of horizontal "
          f"(model coordinates, advisory)")
    print(f"{'z':>7} {'area':>8}  {'x range':>15} {'y range':>15}  what is under it")
    unanchored = roofed = 0.0
    omitted = omitted_area = 0
    for z in sorted(groups):
        a, x0, x1, y0, y1, cs = groups[z]
        if a < amin:
            omitted += 1; omitted_area += a
            continue
        drops = [z - max([s for s in up.get(c, []) if s < z - 0.05], default=-1e9)
                 for c in cs]
        span = min(x1 - x0, y1 - y0)
        if max(drops) > 1e8:
            kind = "NOTHING under part of it -> SUPPORT"
            unanchored += a
        else:
            kind = (f"material {min(drops):.1f}-{max(drops):.1f} mm below, "
                    f"short axis {span:.1f} mm -> check the sliced preview")
            roofed += a
        print(f"{z:7.1f} {a:8.1f}  {x0:6.1f}..{x1:6.1f} {y0:6.1f}..{y1:6.1f}  {kind}")

    print(f"\n{unanchored:.0f} mm2 has nothing under it -- that cannot bridge, it "
          f"needs support or a redesign.")
    print(f"{roofed:.0f} mm2 has material below; whether those anchor a bridge is "
          f"NOT decided here -- read the slicer preview.")
    if omitted:
        print(f"{omitted} group(s), {omitted_area:.1f} mm2, omitted by "
              f"--min-area={amin:g} and NOT assessed.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
