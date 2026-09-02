#!/usr/bin/env python3
"""Break a sliced G-code down by feature type, in cm3 and percent.

    openscad-gcode-feature-volume.py <plate.gcode> [--dia=1.75] [--by-layer]

Written to answer "is that a lot of support?" with a number.  Slicer estimates
report one total; this splits it, so the cost of a support setting is visible
before the print rather than after.  Works on any slicer that emits
`; FEATURE: <name>` (OrcaSlicer, BambuStudio, PrusaSlicer's `;TYPE:` is close
enough to add if you need it).

`--by-layer` splits the same volume by layer as well, which is how you answer
"is that 2 mm wall solid material?".  It is not: a nominal thickness is a
wall-to-wall dimension, and what fills it is some solid skins and some lattice.
The per-layer table names which is which.

Assumes relative extrusion (M83), which those slicers emit.
"""
import sys, re, math
from collections import defaultdict


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    dia = float(next((a.split("=")[1] for a in argv if a.startswith("--dia=")), 1.75))
    if not args:
        sys.exit(__doc__)
    per_mm = math.pi * (dia / 2) ** 2 / 1000.0        # mm of filament -> cm3

    # Extrusion bookkeeping, which the first version of this script did not do
    # and which is not a detail: a retract/unretract pair deposits nothing, but
    # counting only the positive half booked every unretraction as new material.
    # Support travels far more than perimeters do, so the error is not a
    # constant factor and it inflates exactly the number you are measuring.
    by_layer = "--by-layer" in argv
    feat, e = None, {}
    z = None                        # layer height, from the slicer's own marker
    per_layer = defaultdict(lambda: defaultdict(float))
    rel = False                     # G-code's default; M82/M83 override it
    pre = 0                         # E moves seen before any explicit mode
    last = defaultdict(float)       # per-tool absolute E
    debt = defaultdict(float)       # per-tool retracted filament, not yet redeposited
    tool = 0
    seen_mode = False
    for ln, line in enumerate(open(args[0], errors="ignore"), 1):
        c = line.split(";")[0].strip() if not line.startswith(";") else ""
        if line.startswith("; FEATURE:"):
            feat = line.split(":", 1)[1].strip()
            continue
        # Take the layer from the slicer's marker, never from a G1 Z.  A Z-hop is
        # also a G1 Z, and on the one plate measured (2026-09-02) the 0.4 mm hop
        # heights land on other layers' heights, so a mis-attribution would be
        # silent.  That is a hazard, not an observed bug: on that plate every one
        # of the 45,961 post-marker deposition moves happened after Z had returned
        # to the marker height, so the two methods agreed exactly.  The marker is
        # used anyway because it cannot go wrong, not because raw Z was caught.
        if line.startswith(("; Z_HEIGHT:", ";Z:")):
            try: z = float(line.split(":", 1)[1])
            except ValueError: pass
            continue
        if not c:
            continue
        w = c.split()[0]
        if w == "M83": rel, seen_mode = True, True
        elif w == "M82": rel, seen_mode = False, True
        elif w == "M200":
            sys.exit(f"{args[0]}:{ln}: volumetric E (M200) is not supported -- "
                     "this script would report nonsense, so it refuses.")
        elif re.fullmatch(r"T\d+", w):
            tool = int(w[1:])
        elif w == "G92":
            m = re.search(r"E(-?[\d.]+)", c)
            if m: last[tool] = float(m.group(1))
        elif w in ("G0", "G1"):
            m = re.search(r"E(-?[\d.]+)", c)
            if not m or feat is None:
                continue
            v = float(m.group(1))
            if not seen_mode:
                pre += 1        # start-G-code purge, before the slicer says M83
            d = v if rel else v - last[tool]
            if not rel:
                last[tool] = v
            if d < 0:                       # retraction: remember it as debt
                debt[tool] -= d
            else:                           # pay the debt off before depositing
                pay = min(debt[tool], d)
                debt[tool] -= pay
                net = d - pay
                if net:
                    e[feat] = e.get(feat, 0.0) + net
                    # "Custom" is dropped from the headline below as purge, so it
                    # must be dropped here too or the per-layer rows sum to more
                    # than the total.  On the measured plate all of it preceded
                    # the first layer marker and z was still None, which hid the
                    # inconsistency; a mid-print purge would have exposed it.
                    if z is not None and feat != "Custom":
                        per_layer[round(z, 3)][feat] += net
    if not e:
        sys.exit(f"{args[0]}: no '; FEATURE:' markers found")

    # The start-G-code purge is real filament but it is not the model, and the
    # slicer's own "filament used" excludes it.  Keep it visible, out of the
    # total, so this script reconciles with the slicer instead of beating it.
    purge = e.pop("Custom", 0.0)
    total = sum(e.values())
    if not total:
        sys.exit(f"{args[0]}: no model extrusion found under any '; FEATURE:'")
    print(f"{args[0]}  ({dia} mm filament)")
    for k, v in sorted(e.items(), key=lambda kv: -kv[1]):
        print(f"  {k:26s} {v*per_mm:6.2f} cm3  {100*v/total:5.1f}%")
    if purge:
        print(f"  {'(purge, not model)':26s} {purge*per_mm:6.2f} cm3")
    if pre:
        print(f"note: {pre} E move(s) before any M82/M83 -- read as absolute "
              f"(the G-code default). Usually the start-G-code purge.")
    if by_layer:
        print("\nper layer:")
        for zz in sorted(per_layer):
            d = per_layer[zz]
            tot = sum(d.values())
            shown = [(k, v) for k, v in sorted(d.items(), key=lambda kv: -kv[1])
                     if v * per_mm >= 0.01]
            parts = "  ".join(f"{k} {v*per_mm:.2f}" for k, v in shown)
            # A row is NOT a list of the features present -- anything under
            # 0.01 cm3 is hidden while still counting in the row total.  Say so,
            # or "this layer is only walls" gets read off a row that also had
            # infill in it.
            if len(shown) < len(d):
                parts += f"  (+{len(d)-len(shown)} under 0.01)"
            print(f"  z={zz:6.2f}  {tot*per_mm:6.2f} cm3   {parts}")

    sup = sum(v for k, v in e.items() if k.lower().startswith("support"))
    print(f"\n  total {total*per_mm:.2f} cm3, of which support "
          f"{sup*per_mm:.2f} cm3 ({100*sup/total:.1f}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
