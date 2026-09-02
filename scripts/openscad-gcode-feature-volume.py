#!/usr/bin/env python3
"""Break a sliced G-code down by feature type, in cm3 and percent.

    openscad-gcode-feature-volume.py <plate.gcode> [--dia=1.75]

Written to answer "is that a lot of support?" with a number.  Slicer estimates
report one total; this splits it, so the cost of a support setting is visible
before the print rather than after.  Works on any slicer that emits
`; FEATURE: <name>` (OrcaSlicer, BambuStudio, PrusaSlicer's `;TYPE:` is close
enough to add if you need it).

Assumes relative extrusion (M83), which those slicers emit.
"""
import sys, re, math


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    dia = float(next((a.split("=")[1] for a in argv if a.startswith("--dia=")), 1.75))
    if not args:
        sys.exit(__doc__)
    per_mm = math.pi * (dia / 2) ** 2 / 1000.0        # mm of filament -> cm3

    feat, e = None, {}
    for line in open(args[0], errors="ignore"):
        if line.startswith("; FEATURE:"):
            feat = line.split(":", 1)[1].strip()
        elif line[:2] in ("G1", "G0") and feat:
            m = re.search(r" E([-\d.]+)", line)
            if m:
                v = float(m.group(1))
                if v > 0:
                    e[feat] = e.get(feat, 0.0) + v
    if not e:
        sys.exit(f"{args[0]}: no '; FEATURE:' markers found")

    total = sum(e.values())
    print(f"{args[0]}  ({dia} mm filament)")
    for k, v in sorted(e.items(), key=lambda kv: -kv[1]):
        print(f"  {k:26s} {v*per_mm:6.2f} cm3  {100*v/total:5.1f}%")
    sup = sum(v for k, v in e.items() if k.lower().startswith("support"))
    print(f"\n  total {total*per_mm:.2f} cm3, of which support "
          f"{sup*per_mm:.2f} cm3 ({100*sup/total:.1f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
