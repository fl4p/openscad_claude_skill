---
name: openscad
description: >
  Programmatic 3D CAD with OpenSCAD. Fast path for simple printable parts (Quick mode) and for
  editing an existing STL without reconstructing it (Modify mode), plus full design, STL-to-
  parametric reconstruction, and export. Triggers on: 3D model, STL, 3D print, parametric
  design, openscad, CAD, enclosure, bracket, spacer, adapter, holder, "modifica questo STL",
  or any 3D modeling task.
argument-hint: "<description of object to design, or path to an existing .scad / .stl file>"
allowed-tools: "Bash(*),Read,Edit,Write,Glob,Grep,Agent"
metadata:
  version: 1.1.0
  category: 3d-cad
  tags: [openscad, 3d-printing, cad, parametric, stl, modeling, design, quick, modify]
---

# OpenSCAD Skill

Design, render, preview, and export 3D models using OpenSCAD's programmatic CAD engine.

**Speed comes from picking the right mode, not from cutting corners inside one.** Generating
code takes seconds in every mode; what costs time is asking questions that could have been
guessed, rendering four views when one answers, reconstructing a mesh that only needed a hole
moved, and printing a part whose clearances were never measured. The mode table below exists
to spend that time only where it buys something.

## Environment

- **OpenSCAD binary**: resolved at runtime by every script as `$OPENSCAD_BIN`, else
  `command -v openscad`. Linux: `sudo pacman -S openscad` (Arch) or the distro equivalent.
  macOS: `brew install openscad`. Never hardcode a path.
- **Python deps** (Reconstruct and Replicate only — Quick, Modify, Design and Export do not
  need them): `trimesh`, `numpy`, `scipy`, `shapely`, `rtree`. On Arch install them from the
  repos (`python-trimesh` and friends), not with pip: the interpreter is externally managed.
- **Working directory for designs**: `~/openscad-projects/`, one subdirectory per project.
  Quick mode is the exception and writes flat files into `~/openscad-projects/_quick/`.
- **Skill scripts**: `~/.claude/skills/openscad/scripts/`
- **Templates**: `~/.claude/skills/openscad/templates/`
- **Printer profile**: `~/.claude/skills/openscad/templates/printer-profile.scad` — the
  measured behaviour of the actual printer. Read it before emitting any part whose function
  depends on a fit, and say out loud when `profile_measured` is still false.
- **Two different fit problems, two different templates.** `calibration-comb.scad`
  varies the HOLE against a fixed pin, to characterise the printer once.
  `fit-ladder.scad` varies the PIN against a fixed hole, for mating to a part
  that already exists and cannot be changed. See *Fitting to a part that already
  exists* below — that case has its own rules and it is the one that bites.
- **Language reference**: `~/.claude/skills/openscad/references/`

## Modes

The skill operates in eight modes, auto-detected from the user's request. The first two are
the fast ones and cover most real requests — reach for the others only when they are the job.

| Mode | Use it when | Cost |
|---|---|---|
| **Quick** | "I need a simple part, now" — a spacer, a bracket, a holder, an adapter | minutes |
| **Modify** | An STL already exists and is nearly right: a hole to move, 2mm to add, a face to flatten | minutes |
| **Design** | A new part with real requirements, several features, dimensions that must be discussed | tens of minutes |
| **Replicate** | Reproduce a physical object starting from photographs | an hour or more |
| **Reconstruct** | Turn an STL mesh back into parametric code you can own and edit | hours |
| **Refine** | Iterate on an existing .scad (change, preview, repeat) | depends |
| **Export** | Render the final STL/3MF for printing | seconds |
| **Analyze** | Review an existing design for printability | minutes |

**Choosing between Quick, Modify and Design.** Quick guesses and shows; Design asks and then
shows. If the part is simple enough that wrong guesses are cheap to correct on screen, Quick
wins because it costs one round trip instead of two. If the user hands you an existing STL,
Modify beats both — and it beats Reconstruct too, unless they actually need the geometry to
become parametric.

---

## Workflow: Quick Mode

**The default for "I need a simple part".** The point is one round trip: the user describes
the object and gets back a rendered part plus the list of everything that was assumed. They
correct the assumptions that are wrong instead of answering a questionnaire first.

### Step 1: Do not ask. Infer, and write down what you inferred.

Skip the clarification round. Derive whatever can be derived from the request, pick defensible
defaults for the rest, and **keep an explicit list of every value you invented**. That list is
what you hand back, and it is what makes guessing safe.

Standing defaults, unless the request says otherwise: wall 2mm, floor 2mm, corner radius 2mm,
`fit_clearance("close")` for anything receiving a screw or a shaft, `$fn = 64`, flat bottom on
the bed, no support.

Only stop and ask when a missing number makes the part **meaningless** rather than merely
wrong — you cannot invent the diameter of the tube a holder has to hold. One question, then
proceed.

⚠️ **That licence to guess covers design choices ONLY.** There are two kinds of number and
they have opposite rules:

| Kind | Example | Guess? |
|---|---|---|
| **Design choice** | wall 2mm, corner radius, brim width, how tall the stand is | **Yes.** The user has no better answer than you; a wrong guess is cheap to fix on screen. |
| **Interface dimension to a part that already exists** | where the active area sits on a PCB, hole spacing, connector height, board thickness | **Never.** The object is in the user's hand, the number takes ten seconds with a caliper, and being wrong costs a whole print. |

An interface dimension is not "merely wrong" when guessed — the part fits, screws together,
and is silently misaligned. You find out an hour into a print.

**If you cannot download the source — ask. Every time.** A datasheet, drawing or spec page
you could not fetch is never grounds to invent the number.

1. **A non-200 means BLOCKED, not absent.** `WebFetch` returning 403/402 is a WAF rejecting
   its User-Agent. Escalate before concluding anything: UA-corrected `curl` first, then the
   asset/media host rather than `www` (WAFs are per-hostname), then Playwright, then
   `search_rag_context`. Full playbook: `~/.claude/skills/kicad-design/SETUP.md`
   §*Getting the PDF: vendor WAFs* — it is cross-cutting, not datasheet-specific.
2. **Only when that is genuinely exhausted**, say so plainly and ask for a measurement.
   Name the reference edge and the feature: "from the −X board edge to the near edge of the
   white active area", never "can you check the dimensions".

**Make the gap structural, not a comment.** A flagged assumption still gets printed — being
labelled `// ASSUMED` in the source and listed in the README stops nothing. Leave the value
`undef` so the render refuses in seconds:

```openscad
active_x0 = undef;   // MEASURE: PCB -X edge -> near edge of the white active area
assert(!is_undef(active_x0),
       "UNMEASURED: active_x0 — measure PCB -X edge to the active area's near edge");
```

Use `-D 'active_x0=5.36'` for a deliberately provisional render. The default state must be
refusal, not a plausible number.

**Do not derive an interface dimension from guesses.** `active_x0 = panel_x0 + (panel_w -
active_w)/2` turns two invented inputs into a two-decimal result that reads as computed.
Prefer one directly measured input over a chain that launders guesses into authority.

### Step 2: Start from the library, not from an empty file

```bash
mkdir -p ~/openscad-projects/_quick
```

Write a single file `~/openscad-projects/_quick/<name>.scad`. No project scaffolding, no `src/`
and `output/` tree: a quick part that needs a directory structure is not quick.

```openscad
use <printable-lib.scad>   // resolved via OPENSCADPATH, set by the skill scripts
```

⚠️ **Never write a `~` inside `use <>` or `include <>`.** OpenSCAD does not expand the tilde,
and the failure is silent: the library is simply not found and every module call errors out.
The skill scripts export `OPENSCADPATH` pointing at `templates/`, so the bare filename works
from any directory. If you invoke `openscad` by hand outside those scripts, export it yourself:

```bash
export OPENSCADPATH=~/.claude/skills/openscad/templates
```

**Snap fits and press-in fasteners.** `snap_strain(y, t, L)` = `3yt/(2L²)`, checked against
`snap_strain_max` in the printer profile (PLA 1.5 %). `snap_tab` and `push_pin` assert on it,
because **L is squared**: a clip a little too short is not a little weak, it is broken. The
library's own former default — `length=6, thick=1.5, overhang=0.8` — computed to 5 % and would
snap off a PLA part on first assembly; it needed L = 11 mm.

Do not eyeball this, and **mind which section you are in**. `3yt/(2L²)` is the RECTANGULAR
form: it is `3yc/L²` with `c = t/2`, which holds only when the neutral axis sits at mid
thickness. A cylinder split by a slot leaves each finger a circular **segment**, whose
neutral axis sits toward the flat, so `c > t/2` and the rectangular form understates strain —
by 0.30 points on the pin below (1.72 % against the true 2.02 %). Use `seg_c_out(shaft_d,
slot_w)` and `3yc/L²` for anything split, and let the assert do it rather than hand-computing.

Both forms are **prismatic**: they assume the section is constant along `L`. For a tapered
slot `I(x)` and `c(x)` vary, the peak strain need not sit at the root, and evaluating at the
root is a conservative heuristic, not a derivation.

**Prefer a press fit when the joint does not have to come apart.** A stepped solid pin —
small through the part's hole, interference into the frame bore — has no finger, so no thin
section, no bending across layer interfaces, and no strain budget to blow. `press_pin` does
this and is the right default at small diameters; `push_pin` earns its slot only when the
joint gets opened again. Interference is not derivable from the profile: print the sweep.

**A moulded snap post can only be entered from directly above.** If the mating part slides,
hinges, or drops in at an offset, a post standing in its mounting hole is impossible no matter
how good the clip is — check the assembly *route* before designing the fastener. A separate
`push_pin`, dropped in after the part is seated, decouples the fastener from the route entirely,
and lets one pin serve every hole in the assembly if you relieve each bore to a common grip.
It also keeps metal out of plated holes.

The library already carries counterbores, heat-set bosses, screw posts, ribs, snap tabs,
rounded boxes, shells, vents and lid lips, and those modules already read the printer profile.
Keep the Feature Tree structure from Design mode (parameters, derived, profile, body, add, cut,
assembly): it costs nothing and makes the next change trivial.

### Step 3: Deterministic gate, before you look at anything

```bash
bash ~/.claude/skills/openscad/scripts/openscad-validate.sh ~/openscad-projects/_quick/<name>.scad
```

**What that script actually checks:** that OpenSCAD ran, and that it produced geometry. That is
all. It reads diagnostics — it does **not** derive your bounding box, wall thickness, overhangs or
bed fit, and it never has. Treating it as a dimensional gate means `cube([300,300,0.1])` sails
through as `Category: OK` on a 256 mm bed.

**The dimensional checks belong in the model**, as `assert()` — assertions are evaluated at render
time and abort the render, so they are a real gate rather than a list of intentions:

```openscad
include <printable-lib.scad>          // brings in the printer profile's limits

assert(wall  >= min_wall,  "wall below the printer's minimum");
assert(floor_t >= min_floor, "floor below the printer's minimum");
assert(rib_t >= min_rib,   "rib/finger under two extrusion widths");   // see below
assert(outer_w < bed_size[0] && outer_h < bed_size[1], "part exceeds the bed");

echo(str("Outer: ", outer_w, " x ", outer_h, " x ", total_h, " mm"));
```

Then read the `ECHO:` lines back and confirm the bounding box matches the dimensions the user
actually gave. Overhangs are not derivable from the `.scad` — but they **are** derivable from
the mesh, so derive them; do not assert them:

```sh
scripts/openscad-overhang-audit.py part.stl --min-area=15
```

It lists every down-facing face within 45° of horizontal, its area, its footprint, and whether
anything is under it. Read it as **evidence, not a verdict**:

| row | what it means |
|---|---|
| **no upward surface below part of it** | nothing is *directly under* it. That is a cantilever needing support **or** a roof spanning two walls, which bridges fine — the tool sees only downward, so both land here. Decide from the model. |
| material N mm below | *undecided.* It may be a pocket roof that bridges — or a one-sided shelf floating above an unrelated floor. Look at the sliced preview. |

Neither row is a verdict: the tool computes no anchor topology in **either** direction. It
finds the faces worth thinking about and refuses to think for you.

The audit runs on the mesh in **model coordinates** and knows nothing about placement, cooling,
speed or support settings. A slicer rotation about X or Y invalidates every row. It never says
a part is fine, and neither should you on its evidence alone — confirm in the sliced toolpaths.

What it is for is the mistake it was written after: **a root gusset does not support a residual
horizontal underside.** A 45° ramp off a wall that stops short of the tip leaves the flat from
the top of the ramp to the tip anchored on one side, and that flat droops — a 6 × 7 mm arm on a
beautiful 45° gusset still has a 7 mm one-sided ledge. The fixes, in order of preference:
carry the ramp all the way to the tip; taper the feature so there is no flat at all; anchor the
tip to a second wall so it is a real bridge; reorient the part; split it. Only when the empty
space under the feature is *deliberate* — a board, a cavity, a wire run — is there no second
anchor to reach, and then support is the answer. Say which rows you are choosing to support,
and check that the support is removable from where it lands.

### Manifold and overhang-clean is not the same as printable

Every check above asks about **shape**. None of them asks whether the shape can be made
out of 0.4 mm lines of plastic. That question has to be asked separately, and it is the
one that produces parts that pass every gate and come off the bed as garbage.

The failure, measured 2026-09-02. A split snap pin in a 3.2 mm hole: shaft 3.0 mm, a
diametral slot tapering 1.6 → 2.0 mm. It was manifold. `connected bodies: 5`, one per
pin. The overhang audit found nothing cantilevered. In the slicer's **Prepare** view it
was a clean, solid pin. It printed as a **stack of loose unbonded rings** — a coil, not
a beam.

The arithmetic was on the page the whole time. A diametral slot leaves each finger a
circular **segment**, whose thickness peaks on the centreline and falls to **zero** at
both edges:

```
finger thickness = (shaft - slot) / 2  =  (3.0 - 2.0) / 2  =  0.50 mm  =  1.25 nozzles
```

One extrusion line per layer. The G-code says it outright — count extruding moves per
layer, per part:

| revision | slot | segment depth | moves / pin / layer |
|---|---|---|---|
| tapered  | 1.6 → 2.0 | 0.50 mm = 1.25 lines | **4** |
| parallel | 1.2 flat  | 0.90 mm = 2.25 lines | **24–29** |
| press fit, no slot | — | solid | **44–66** |

*Why* a single line fails is **not** established — vase mode is single-width and bonds
fine, so "nothing to bond to sideways" is not the mechanism. What the table is, is a
threshold with a known-bad below it and a known-good above it. That is enough for a
screening gate and it is all it claims. The transition is not located: nothing was
printed between 0.50 and 0.90 mm.

**Rules that fall out of it:**

- **Check the thinnest station, not the nominal size.** A tapered slot, a draft angle, a
  fillet running out, *a lead-in cone* — whichever is thinnest decides. Rev 2 fixed the
  shaft to 0.90 mm and still printed brittle, because the barb cone necked the tip back
  to 0.50 mm. The gate was measuring a station that was no longer the worst one.
- **A taper is a legitimate technique; running under the print floor is the defect.**
  Reject an under-floor taper, not tapering. And know what the parallel slot costs:
  thickening the finger *raises* strain (1.582 → 2.023 % here) and raises insertion force.
- **`min_wall` is not `min_rib`.** A wall is fought over its area; a rib or finger is
  narrow in one direction and the slicer must fill it with whole lines. Two lines is the
  screening floor, three for anything load-bearing. Note this is a policy split, not a
  slicer-level distinction — the slicer does not know which of your features is a wall.
- **Prepare shows a shape; Preview shows what will exist.** They disagree exactly when it
  matters. If a feature is anywhere near the nozzle width, open the sliced preview and
  look at that layer, or count the moves.

**The gate, and it is cheap:**

Track Z, bucket the extruding moves by layer, and split them across the parts on the
plate. A whole-file `grep -c` will not do it — it counts every move in the print, and a
`G1` is a straight toolpath segment rather than an "extrusion line", so the number is only
ever a relative signal between revisions of the same plate.

```python
# extruding moves per layer, split into 10 mm bands = one part each
import re, collections
x = y = None; z = 0.0; layers = collections.defaultdict(list)
for ln in open('plate_1.gcode'):
    if not ln.startswith(('G1', 'G0')): continue
    d = dict(re.findall(r'([XYZE])(-?[\d.]+)', ln))
    if 'Z' in d: z = float(d['Z'])
    nx = float(d.get('X', x if x is not None else 'nan'))
    ny = float(d.get('Y', y if y is not None else 'nan'))
    if 'E' in d and float(d['E']) > 0 and x is not None and (nx, ny) != (x, y):
        layers[round(z, 2)].append((x, y))
    x, y = nx, ny
for z in sorted(layers):
    xs = [p[0] for p in layers[z]]; x0 = min(xs)
    print(z, len(layers[z]), collections.Counter(int((p[0]-x0)//10) for p in layers[z]))
```

Better, put it in the model where it aborts the render — `printable-lib.scad` now gates
`push_pin` on exactly this, and reports the failure in extrusion widths rather than mm,
because "0.5 mm" reads as a dimension while "1.25 extrusion widths" reads as a verdict.

**Two printability constraints can pull against each other.** Thickening a snap finger to
make it printable *raises* its strain, because `ε` is linear in `t`. At a 3.2 mm hole with
5.6 mm of grip, no slot width is simultaneously ≥ 2 lines thick, under PLA's 1.5 % handbook
strain, and retaining. `L` is the strongest lever because it enters squared — but it is not
the only one, and saying so once cost a working design. `y`, the barb diameter, the section
shape, the number of fingers, the print orientation and the material are all live, and the
cheapest lever of all is often **deleting the flexure**: a press fit has no finger and
therefore no strain budget to satisfy.

Note in hindsight that this whole trade was being run on the wrong constraint: none of
those pins were strain-limited or rib-limited in practice, they were limited by a barb that
could not retract at all. See the per-point rule below before spending effort here.

**Before concluding a mechanism is dead, check that the constraint is real.** The pin above
was declared infeasible on exactly this arithmetic. It was not infeasible; the model had an
arbitrary neck in the barb cone (`d2 = shaft_d - 2*y`) putting a 0.50 mm section at the free
end, and the 1.5 % ceiling is a handbook figure for *moulded* stock being applied to printed
PLA loaded across its layers. Two bad inputs, one confident "no solution exists". An empty
feasible set is a claim about your constraints before it is a claim about the world — so
name each constraint and say where it came from, and treat "not at this size" as the
conclusion you reach after that audit, not instead of it.

**A split pin's barb must be checked per POINT, not per diameter — a full ring never
retracts.** This one survived six revisions, three printed plates and every gate in the
library, and it is the most expensive mistake in this file. The fingers deflect *across*
the slot; call that Y. A barb point at `(x, y)` moves to `(x, y∓d)` and **its X coordinate
never changes**. On a 4.7 mm ring barb the chord edges sit at |x| ≤ 2.30 against a 3.2 mm
hole's 1.60 mm half-width, so no deflection whatsoever can move them through. Such pins do
not snap in; they are *ploughed* in, and PLA obligingly scrapes.

The tell is a limit that will not move. Insertion capped near 1.5 mm of closure no matter
what changed — slot width, root fill, nose angle, strain budget — because the only quantity
actually being measured was how much interference the material would scrape past. The
second tell is a lever with the wrong *sign*: a fatter shank made insertion **worse**,
because the "slop" being tightened was the ovalisation clearance that was getting the collar
through at all.

The condition is that a deflected point lands inside the hole:

```
x² + (y − d)² ≤ (hole_d/2)²
```

— a hole-sized cylinder shifted by `d`. Intersect the barb with it (`barb_mask()`) and keep
the lens on each finger, which is the shape a commercial nylon push rivet already has.
Two consequences worth stating before anyone sizes one:

- **`d` comes from the slot, not the barb.** The fingers meet after closing `slot_w`
  between them, so `d = slot_w/2`. Building the mask from the barb's *nominal* demand
  `(barb_d − hole_d)/2` just rebuilds the same unpassable collar in a prettier shape.
- **`barb_d` therefore stops being the retention knob; the slot is.** The mask clips at
  `hole_d/2 + slot_w/2` whatever `barb_d` says, so effective ledge is
  `(hole_d + slot_w − bore_d)/2` — and widening the slot moves it out one for one, against
  `min_rib` on the finger.

Generalise the habit, not the formula: for any flexure, write down the *displacement field*
the mechanism actually produces and check every point of the feature against it. A
characteristic dimension is a summary of that field, and a summary can be silent about the
part that does not move.

**Then size it.** "That looks like a lot of support" is answerable with a number:

```sh
scripts/openscad-gcode-feature-volume.py plate.gcode
```

It splits the sliced extrusion by feature type, so a support setting's cost is visible before
the print. Retraction is netted off — an unretraction is not new material, and support travels
far more than perimeters do, so counting it inflates the one number you are measuring.

What follows is **one part's numbers, not a policy.** It is a single 127 × 92 × 28 mm frame
with seven unanchored ceilings, OrcaSlicer 2.x / P1P / PLA / 0.20 mm. Treat each line as a
hypothesis to A/B on your own geometry, and re-measure rather than inheriting the ranking:

| `support_style` | support | share of the print | time |
|---|---|---|---|
| `grid` | 11.67 cm³ | 24.4 % | 2 h 18 m |
| `snug` | 4.73 cm³ | 11.5 % | 2 h 04 m |
| `organic` (tree) | 7.97 cm³ | 18.0 % | 2 h 52 m |

**Verify the setting was applied, in the sliced output, before you believe a row.**
OrcaSlicer does not reject an unknown `support_style`: it writes `support_style = default`
into the G-code and slices anyway. An earlier version of this table carried a `tree` row that
was byte-identical to `grid`, because `tree` is not a value — `organic` is, and it also needs
`support_type = tree(auto)`. A silently ignored setting does not fail; it returns a plausible
number for the wrong slice. `grep` the resolved key out of the G-code every time.

`snug` follows each overhang's own footprint instead of dropping a prism from it, which is why
it won *here*, where the overhangs are small and scattered — on a part with one large ceiling
there is no prism to save. On this part `support_base_pattern_spacing` and
`support_threshold_angle` each moved it by under 1 cm³, and tree did not help; that is a
result about flat scattered ledges, not a ranking of the settings in general. The volume
numbers say nothing about surface quality or strength, neither of which was measured — and on
removability they are actively misleading, which is the next section. Keep the sliced file or
its per-feature summary if you intend to cite them.

Two settings tend to matter more than density — verify both on your own slice:

- **`bridge_no_support = 1`.** Otherwise the slicer packs support into every blind nut trap and
  downward-opening pocket, where it cannot be dug out and no nut will seat. Anything anchored on
  two sides and under `max_bridge_length` then bridges instead. Check the resolved
  `max_bridge_length` in the sliced 3mf rather than trusting a profile's documented default —
  the inheritance chain does not always give you what the vendor page says.
- **`support_top_z_distance`** at one layer height was right on this part: less welded it on,
  more let the first layer over it droop. It is a starting point to test, not a constant. It is
  *not* the removal knob, and reaching for it first is the mistake below.

**Tune support for removal, and it is not the knob you reach for first.** The frame above came
off the bed with its support welded to the boss faces and was a fight to clean up — after the
volume table had already been measured, published, and believed. Volume was the wrong quantity.

The weld is in **`support_interface_spacing`**, and the trap is that it is a *line pitch*
measured against a line **width** that the profile never states. Measure the width out of the
sliced G-code — on this part the interface line was 0.350 mm across 1871 moves with no spread —
because until the pitch passes that number it opens **no gap at all**. At the profile's 0.2 the
lines overlapped by 0.15 mm: not an interface, a solid sheet fused to the part. And no
`support_top_z_distance` rescues it, because the weld lives in the interface's own extrusion,
not in the air gap above it.

Now look at what the sliced numbers do as that pitch opens (organic, same part):

| `support_interface_spacing` | interface coverage | support total |
|---|---|---|
| 0.2 | 100 % | 7.97 cm³ |
| 0.5 | 70 % | 7.68 |
| 0.7 | 50 % | 7.40 |
| 0.9 | 39 % | 7.67 |
| 1.2 | 29 % | 7.50 |

**Volume is nearly flat and non-monotonic** — organic re-routes its branches every slice, worth
about 0.3 cm³ of run-to-run noise, which is most of the spread in that column. A filament-led
search over this knob finds ~7 % and calls it a wash. The column that matters is coverage:
100 % → 50 % is the difference between chiselling and lifting. So do not confirm a support
setting on the quantity your script happens to print; name the quantity you are actually buying
first, and check the cheap one is not standing in for it.

What it costs is scalloping between the interface lines on the supported face. Where those
faces are functional — here the boards bolt to them — that sets a ceiling: 0.7 was as far as
this part went without a test coupon, and the seats still get dressed flat before assembly.

After trimming, **re-verify coverage** — a lighter setting can quietly stop reaching a feature.
Parse the sliced G-code for `Support` extrusions in the layers just below each ceiling you care
about, in that ceiling's own footprint. Trimming support by 45 % is only good news if every row
the audit flagged still has something under it.

⚠️ `openscad-validate.sh` is a **report, not a gate**. Read the `Category:` line — `OK` passes,
anything else stops the part here:

| Category | Meaning |
|---|---|
| `OK` | rendered, and geometry was actually written |
| `SYNTAX_ERROR` / `WARNING` / `EMPTY_MODEL` | the file is wrong — fix it |
| `ASSERTION_FAILED` | the model rejected its own parameters — the gate above working as intended |
| `KILLED` | terminated by a signal (OOM, or too slow for the caller's timeout). **Unverified, not passed.** Retry with a lower `$fn`, or render the parts separately |
| `FAILED` | non-zero exit, cause not recognised |
| `UNVERIFIED` | exited 0 but wrote no geometry |

The last three exist because every category keys off what OpenSCAD *prints*: a killed run prints
nothing, matches no pattern, and used to fall through to `OK` — announcing success exactly when the
check had not run at all. If you add a category, add it **before** the final `else`, and never let
an unrecognised state land on `OK`.

A part that fails here never reaches the render. The eye is for shape; these are arithmetic,
and arithmetic should not cost a vision call.

### Two failures that live upstream of the model

Both cost prints, neither is geometry, and the full write-ups moved to the `p1p` skill
(`~/dev/ee/p1p/doc/`) when this skill stopped being their right home. The rules that survive
the move, because they are not printer-specific:

- **Verify resolved values, never a preset name.** A slicer CLI that composes presets by
  `inherits` does not necessarily walk the chain: a vendor ASA preset produced a PLA plate at a
  45 °C bed, with the G-code header still naming the ASA preset. Any value you rely on from a
  layered config must be read back out of the artefact that was actually produced. Partial
  resolution that still validates is a failure mode a flat config does not have.
- **Parse the field, not the filename.** A survey matching `*ASA*P1P*` concluded no stock preset
  existed; eleven declared that printer in `compatible_printers`. A filename is a label someone
  chose; compatibility is a field.
- **A fault's text is the machine's hypothesis, not its measurement.** When a fault names a
  component, every upstream reason its sensor might see that is still open — a levelling
  force-sensor error was residue on the nozzle tip, which on a machine that levels by touch *is*
  the probe.
- **A control that differs in its preamble is not a control.** The one passing run differed from
  the failures not in the variable under test but in what ran before it. Compare what preceded
  the passing and failing operations, not just the operations.
- **Before overriding a guard, find out what else consumes the value it reads.** "The check is in
  my way" and "the check is wrong" are different findings; only one licenses a flag.
- **Reviewing a slice: open the `.gcode`, not the `.gcode.3mf`.** The `.3mf` opens as a project,
  so touching a preset in the GUI silently re-slices — with support off, whatever the file said.

### The orientation you model in is not the orientation it prints in

A part that has to be *checked* against an assembly must be modelled in assembly
coordinates — that is the only way an `intersection()` with the things it must clear
means anything. Nothing about that orientation makes it printable, and the slicer step in
this pipeline will not fix it: OrcaSlicer's `--arrange` places and rotates in XY only, and
will happily lay a lid down as a roof over its own air. (It does have a separate `--orient`
that rolls parts; the point is that arranging is not orienting, and a pipeline that calls
only the first gets no say in which face lands on the bed.)

Measured 2026-09-02, one 127 × 92 mm lid, 2.0 mm plate on an 8.3 mm skirt:

| orientation | unsupported down-facing area | support |
|---|---|---|
| as modelled (assembly) | 10,713 mm² down-facing, 8.3 mm up | everywhere |
| rolled 180° onto its roof | **94.9 mm²** — 89.9 of it four counterbore ledges, each a 1.5 mm annulus over a Ø6.4 pocket | **none** |

Keep both, in one file, and let a flag pick:

```openscad
print_orient = false;    // -D print_orient=true for the STL the slicer takes

if (cap_check >= 0) intersection() { cap(); cap_obstacle(cap_check); }
else if (print_orient) translate([0, 0, cap_top]) rotate([180, 0, 0]) cap();
else { cap(); if (show_frame) stack_frame(); }
```

Then `openscad -o cap.stl cap.scad -D print_orient=true` in the export script, so the
STL on disk is always the printable one and the gates always see assembly coordinates.

`cap_top` there is the part's own derived top, **not** a literal: the roll has to land
the part on z = 0, and re-typing that number is how a model silently decouples from
itself the next time a level moves. Re-run the overhang audit after the roll — it is a
different part as far as gravity is concerned.

### A thickness is not an amount of material

`wall = 2.0` is a wall-to-wall dimension. What fills it is some solid skins and some
lattice, and the split is decided by the slicer, not by the model. Ask the sliced file:

```sh
scripts/openscad-gcode-feature-volume.py plate.gcode --by-layer
```

The same 2.0 mm lid ceiling, ten layers at 0.20 mm:

```
  z=  0.20    2.30 cm3   Bottom surface 2.18        <- solid
  z=  0.40    2.26        Internal solid infill     <- solid
  z=  0.60    2.26        Internal solid infill     <- solid
  z=  0.80    0.30        Sparse infill 10%
  z=  1.00    0.30        Sparse infill 10%
  z=  1.20    0.30        Sparse infill 10%
  z=  1.40    0.32        Sparse infill 10%
  z=  1.60    3.11        Internal Bridge           <- solid
  z=  1.80    2.25        Internal solid infill     <- solid
  z=  2.00    2.25        Top surface               <- solid
```

Six solid layers, four of lattice: 1.2 mm of solid PLA in two skins with 0.8 mm of foam
between them. Commanded filament volume over CAD envelope volume is 68 % — which is a
material-budget ratio, not a measured porosity. If you needed 2 mm of material, you did not
get it.

Two things that table teaches, both of which change how you *pick* a thickness:

- **The layer that closes over sparse infill is a double-height layer.** 3.11 cm³ against
  2.25 for an ordinary solid layer, about 1.4×. The tempting explanation — a wider line, or
  a flow multiplier — is wrong on both counts: `internal_bridge_flow = 1`, and the feature
  block declares `; LINE_WIDTH: 0.4`, *narrower* than the 0.45 everything else uses. What it
  also declares is `; LAYER_HEIGHT: 0.4` on a 0.2 mm layer grid. Orca's thick-internal-bridge
  course reaches down into the void it is spanning, so it deposits two layers' worth of
  material in one z step. You pay it at any infill under 100 %, which makes the marginal
  saving from dropping infill smaller than it looks.

  The general lesson is the method, not the number: **read the feature block, do not
  reconstruct it.** Orca emits a resolved `; LINE_WIDTH:` and `; LAYER_HEIGHT:` before every
  feature in the body — which is where they live, since the *profile's* `*_line_width` keys
  read `0` (auto) and tell you nothing. Backing width out of the toolpaths as
  `E·A_filament / (layer_height · path_length)` does not recover them; it silently answers a
  different question, giving 0.399 mm where the slicer says 0.45. That gap is not error, it
  is definition: the formula returns the width of an equivalent *rectangle*, while the
  slicer means a bead with rounded sides, and the profile's 0.98 flow ratio sits on top.
  (0.45 × 0.2 − 0.2²(1−π/4) = 0.0814 mm², ÷ 0.2 × 0.98 = 0.399. The two agree exactly once
  you know they are different quantities.) Reconstructing a number the file already states
  is how you end up publishing the wrong one.
- **Size a wall to a whole number of extrusion lines and it has no inside.** The skirt at
  1.8 mm is exactly four 0.45 mm perimeters, and slices as four perimeters and nothing else.
  It is the constructive twin of the `min_rib` floor — that one says *never fewer than two
  lines*, this one says *land on a whole number of them*.

  Two cautions on reading that off a per-layer table. The rows hide features under
  0.01 cm³, so a row showing only walls is not proof the layer is only walls — the skirt-only
  layers here also carry ~0.007 cm³ of sparse infill inside the bolt bosses. And the rule
  holds only while the slicer can absorb your dimension into the same path count: Arachne
  varies perimeter width to fill what you asked for, so nearby thicknesses cost weight
  without changing path count, but go far enough and the count, the gap fill and the
  stiffness all change together. Land near a whole number; do not extrapolate a trend from
  it.

**Do not inherit a structural constant into a part that carries nothing.** The lid's skirt
began at `wall_t = 3.5`, `include`d from the frame it bolts to, where 3.5 mm is a load path.
A lid's skirt is a stiffening flange, and flange depth enters its bending stiffness far more
steeply than wall thickness does — 8.3 mm of depth is doing the work, so thinning the wall
is cheap. Three changes together took the part from 28.1 cm³ / 51 min to 22.5 / 39; sliced
one at a time, infill and top shell account for 3.74 cm³, the 2.5→2.0 mm plate for 0.70, and
`cap_wall` 3.5→1.8 for **1.16 cm³ and 4½ minutes**. Worth doing, an order of magnitude less
than the headline — attribute a saving to the lever you actually moved. Sharing a constant is right when the
*reason* is shared; when only the number is, it over-couples exactly like a copied literal,
just in the other direction.

### Step 4: One render, isometric

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh quick ~/openscad-projects/_quick/<name>.scad
```

One image, not four. Read it and check the shape is what was asked for. Four angles belong to
Design mode, where the geometry is complex enough to hide something.

### Step 5: Hand it back with the assumptions visible

Report, in this order:
1. the preview
2. **the assumptions list** — every invented number, one per line, so the wrong ones are
   obvious at a glance
3. the parametric knobs, so a change is a `-D` away and not a rewrite
4. ⚠️ if `profile_measured` is false and the part has a fit, say that the clearances are
   declared defaults and not measurements, and that the first print is the one that tells

Then stop. The user corrects an assumption or asks for the STL. Do not iterate on your own
initiative: in Quick mode a second unrequested render is wasted time.

### Step 6: Export, when asked

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh export ~/openscad-projects/_quick/<name>.scad
```

**When to abandon Quick mode:** the moment the part grows a third interacting feature, or a
dimension turns out to depend on a measurement nobody has, switch to Design mode and say so.
Quick mode that keeps iterating is Design mode with worse manners.

---

## Workflow: Modify Mode

**The fastest useful thing in this skill, and the most common real job.** A model already
exists — downloaded, or printed once and not quite right — and it needs one change: a hole
somewhere else, two millimetres more clearance, a boss added, a face flattened.

**Do not reconstruct it.** Reconstruction turns a mesh back into parametric code and costs
hours. Modify treats the mesh as a solid and cuts into it, which costs minutes and needs
nothing beyond `openscad` itself: no Python, no analysis pipeline.

### Step 1: Import and see it

```openscad
// modify.scad
$fn = 64;
eps = 0.01;
original = "/absolute/path/to/model.stl";

import(original, convexity = 10);
```

`convexity` matters: without it a preview of a mesh with internal cavities renders wrong.
Render once with `openscad-render.sh quick` and confirm you are looking at the right object.

### Step 2: Find the coordinates you need

The mesh arrives in its own coordinate system, which is rarely the one you want.

```bash
python3 ~/.claude/skills/openscad/scripts/openscad-profile-extract.py model.stl --json /tmp/m.json
```

If the Python stack is not available, the bounding box alone covers most edits, and OpenSCAD
gives it for free by rendering the model against a known reference cube. Do not guess
coordinates from a picture: that is Rule 2 of Reconstruct mode, and it applies here just as
hard.

### Step 3: Cut, add, or trim

```openscad
difference() {
    import(original, convexity = 10);

    // a new hole, positioned against a real reference, never a magic number
    translate([hole_x, hole_y, -eps])
        cylinder(h = part_h + 2*eps, d = 4 + fit_clearance("close"));
}
```

The three edits that cover almost everything:

| Need | Shape |
|---|---|
| New hole, or an existing one widened | `difference()` with a cylinder through it |
| Add material (boss, rib, tab, packing) | `union()` with a module from `printable-lib.scad` |
| Flatten a face, cut a part away | `intersection()` with a large cube, or `difference()` with one |

**Widening an existing hole is a subtraction, not an edit**: put a larger cylinder exactly on
the old axis. Finding that axis is the whole job, and it comes from measurement, not from the
render.

⚠️ **Booleans on an imported mesh are only as sound as the mesh.** If the STL is not manifold,
OpenSCAD will still produce something and it will be wrong. Check first:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-stl-analyze.sh model.stl
```

A non-manifold input is the one case where Modify is not the answer: repair the mesh first, or
reconstruct it.

### Step 4: Verify against the original

```bash
bash ~/.claude/skills/openscad/scripts/openscad-stl-compare.sh model.stl modified.stl /tmp/cmp/
```

The boolean difference should show **exactly** the change that was asked for and nothing else.
A surprise elsewhere in the diff means a coordinate is wrong, and seeing it here is far cheaper
than seeing it after the print.

### Step 5: Export

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh stl ~/openscad-projects/_quick/modify.scad
```

The result is a mesh, not parametric code: the change is repeatable by editing `modify.scad`,
but the original geometry stays opaque. **That is the trade** — minutes instead of hours, at
the price of not owning the shape. When the user needs to own it, that is Reconstruct mode, and
it should be chosen deliberately rather than fallen into.

---

## Workflow: Design Mode

When the user asks to create a new 3D object:

### Step 1: Understand Requirements

Clarify with the user:
- **What** is the object? (enclosure, bracket, gear, container, etc.)
- **Dimensions** — key measurements in mm
- **Purpose** — functional print, aesthetic, mechanical fit?
- **Constraints** — printer bed size, material, wall thickness preferences
- **Parametric?** — which dimensions should be adjustable?

### Step 2: Set Up Project

```bash
bash ~/.claude/skills/openscad/scripts/openscad-project.sh init "<project-name>"
```

This creates `~/openscad-projects/<project-name>/` with subdirectories for source, output, and previews.

### Step 3: Generate the .scad File

Write the OpenSCAD code to `~/openscad-projects/<project-name>/src/main.scad`.

**Mandatory file structure (Feature Tree pattern):**
```openscad
// 1. PARAMETERS (independent variables)
width = 60;  height = 30;  wall = 2;

// 2. DERIVED DIMENSIONS (calculated from parameters)
inner_width = width - 2 * wall;

// 3. BASE PROFILE (2D sketch — the core shape)
module sketch_base() {
    offset(r = corner_r)
        square([width - 2*corner_r, depth - 2*corner_r], center=true);
}

// 4. PRIMARY BODY (extrude the sketch)
module body() { linear_extrude(height = height) sketch_base(); }

// 5. ADDITIVE FEATURES (bosses, ribs, tabs)
module features_add() { ... }

// 6. SUBTRACTIVE FEATURES (holes, slots, pockets — ALWAYS LAST)
module features_cut() { ... }

// 7. ASSEMBLY (the Feature Tree)
difference() {
    union() { body(); features_add(); }
    features_cut();
}
```

**Profile-first design rules:**
- Prefer `polygon()` + `linear_extrude()` over `hull()` of 3D primitives
- Use `offset(r=radius)` for corner rounding instead of `hull()` with cylinders
- Use `rotate_extrude()` for axially symmetric parts (never stack cylinders)
- Define dimensions relative to edges/features, not absolute coordinates: `hole_x = total_length - edge_margin` (not magic numbers)
- Cascade tolerances from a single `fit_clearance` parameter

**Critical rules for generating OpenSCAD code:**
- Read `~/.claude/skills/openscad/references/language-reference.md` if unsure about syntax
- Always define parametric dimensions as variables at the top of the file
- Use `$fn = 64;` for smooth curves (or higher for final renders)
- Add comments explaining each section
- Use modules for reusable parts
- Keep wall thickness >= 1.2mm for FDM printing
- Design with the print orientation in mind (flat bottom, minimal overhangs)

### Step 4: Preview

Render a multi-angle PNG preview:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh preview ~/openscad-projects/<project-name>/src/main.scad
```

This generates 4 preview images (front, side, top, isometric) in the project's `previews/` directory.

### Step 5: Analyze Preview

Read each preview PNG using the Read tool to see the rendered object. Evaluate:
- Does the shape match the user's description?
- Are proportions correct?
- Are there visible artifacts or unintended geometry?
- Would this print well? (overhangs, bridging, thin walls)

Report findings to the user with the preview images.

### Step 6: Iterate

If changes are needed, edit the .scad file and re-render. Repeat Steps 4-5 until the user is satisfied. Each iteration should be targeted — change one aspect at a time.

### Step 7: Export

When the design is approved:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh export ~/openscad-projects/<project-name>/src/main.scad
```

This produces:
- `output/model.stl` — for slicing and printing
- `output/model.3mf` — alternative format (better metadata)
- `previews/final-preview.png` — high-res final render

---

## Workflow: Replicate Mode

When the user provides reference images of a physical object to reproduce in OpenSCAD:

### Step 1: Analyze Reference Images

Read ALL provided reference images using the Read tool. For each image, extract:
- **Overall shape**: What geometric primitives compose this object?
- **Proportions**: Relative dimensions (height-to-width ratio, etc.)
- **Features**: Holes, fillets, chamfers, textures, slots, lips, threads
- **Symmetry**: Is it symmetric along any axis?
- **Construction**: How would you decompose it into boolean operations?

If dimensions are provided, note them. If not, estimate proportions from the images and ask the user for at least one known measurement to establish scale.

### Step 2: Create Decomposition Plan

Before writing any code, describe the object as a series of OpenSCAD operations:

```
Object: Phone stand
Decomposition:
1. Base: flat rectangle with rounded corners (80x60x5mm)
2. Back support: angled plate (60x3mm, tilted 70 degrees)
3. Front lip: small ridge to hold phone (60x3x8mm)
4. Fillet: smooth transition between base and back support
5. Cable channel: cylinder subtracted from base center
```

Present this plan to the user for confirmation before coding.

### Step 3: Generate Initial .scad File

Write the OpenSCAD code based on the decomposition. Set up the project:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-project.sh init "<object-name>"
```

Write the .scad to the project's `src/main.scad`.

### Step 4: Render and Compare

Generate a preview from the **same angle** as the reference image:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh quick ~/openscad-projects/<name>/src/main.scad
```

Read both the reference image and the rendered preview. Compare them side by side mentally:
- Does the overall silhouette match?
- Are proportions correct?
- Are features (holes, edges, curves) in the right places?
- What's the biggest discrepancy?

### Step 5: Iterative Refinement Loop

For each discrepancy found:
1. Identify which part of the .scad code controls the mismatched feature
2. Make a **single targeted edit** to improve the match
3. Re-render from the same angle
4. Re-compare with the reference

**Refinement priorities** (fix in this order):
1. Overall shape and proportions
2. Major features (holes, cutouts, protrusions)
3. Angles and curves
4. Fillets, chamfers, and surface details
5. Fine details

### Step 6: Multi-Angle Validation

Once the primary angle looks good, render from all angles that have reference images:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh preview ~/openscad-projects/<name>/src/main.scad
```

Compare each rendered view against its corresponding reference image. Fix any angle-specific discrepancies.

### Step 7: Dimensional Verification

If the user provided measurements, add `echo()` statements to verify:

```openscad
echo("Total width:", width);
echo("Total height:", height);
echo("Wall thickness:", wall);
```

Render with echo capture to verify dimensions match specifications.

### Step 8: Export

When the user confirms the replication is satisfactory, export for printing.

### Tips for Accurate Replication

- **Start simple**: Begin with bounding-box primitives, then refine
- **Use reference dimensions**: If user says "it's about 10cm tall", anchor ALL proportions to that
- **Match camera angle**: Use `--camera` to match the reference photo's perspective
- **Organic shapes**: Approximate with hull(), minkowski(), or rotate_extrude() of a profile
- **Iterate small**: Change one thing per render cycle
- **Ask when unsure**: If a feature is ambiguous from the images, ask the user rather than guessing

---

## Workflow: Reconstruct Mode (STL-to-SCAD)

When the user provides an STL file and wants it converted to parametric OpenSCAD code:

### Overview

STL files are triangle meshes with no semantic information about the original primitives or operations that created them. Reconstruction is the process of analyzing the mesh geometry and re-expressing it as clean, parametric OpenSCAD code. This is valuable because:
- Parametric code can be modified (change dimensions, add features)
- OpenSCAD code is human-readable and version-controllable
- The resulting model can be adapted to different use cases

### Critical Rules for Reconstruction

**Read `references/reconstruction-guide.md` before starting any reconstruction.** It contains the complete best practices guide learned from real reconstructions.

**Rule 1: SCULPTOR APPROACH (mandatory).** Start from a full solid block, subtract ALL features. Never build up from pieces — CSG ordering bugs cause added material to cover previously-cut holes. Structure: `difference() { solid_body(); channels(); tapers(); ALL_holes_LAST(); }`

**Rule 2: NEVER add features based on assumptions.** Always verify with SVG contour data AND reference images. If a feature doesn't appear as a separate contour in the SVG slices, IT DOES NOT EXIST. Known hallucinations to avoid:
- Pyramids/cones from render shadows
- Cylinders from curved wall edges
- Top holes from through-hole exit points

**Rule 3: Bounding box match ≠ correct model.** 0.000mm bbox delta can mean only 70% geometric accuracy. Always use mesh comparison (`openscad-stl-compare.sh`) with boolean diff images.

**Rule 4: ANALYZE FIRST, DECOMPOSE, THEN CHOOSE per-component approach.**
Do NOT jump to code. The analysis phase must answer these questions:
1. **What are the dominant features?** (diagonal arm, clips, channels, holes)
2. **What is the thinnest axis?** That's the likely extrusion direction — NOT necessarily the stability score winner
3. **Can the object be decomposed into simpler sub-objects?** Model each with its best technique
4. **Where are internal channels/gaps?** Slice along Z to find multi-body cross-sections

**Rule 5: Choose the extrusion axis by geometry, not just stability score.**

The profile extractor's stability score finds the axis with the most uniform cross-section. But this is misleading for models with diagonal features — slicing along Z for a diagonal bracket produces staircase artifacts. Instead:

| Model Type | Best Extrusion Axis | Why |
|-----------|-------------------|-----|
| Flat bracket/plate | Thinnest axis (smallest extent) | Profile in the wide plane captures all detail |
| Diagonal/angled arm | Thinnest axis | Diagonals live in the plane of the two longest axes |
| Clean extrusion (stability < 0.1) | Stability-score axis | Profiles are identical → stability is reliable |
| Cylindrical (stability > 0.3) | Object's rotational axis | Use rotate_extrude or parametric primitives |
| Truly complex (no good axis) | Dense multi-axis slabbing | 2mm slabs along thinnest axis |

```bash
# Always run ALL analysis tools before writing any code:
bash ~/.claude/skills/openscad/scripts/openscad-stl-reconstruct.sh model.stl analysis/
python3 ~/.claude/skills/openscad/scripts/openscad-profile-extract.py model.stl --json analysis/profile.json
python3 ~/.claude/skills/openscad/scripts/openscad-adaptive-slice.py model.stl analysis/
```

After analysis, compare: **thinnest axis extent** vs **stability-score axis**. If they differ, the thinnest axis is usually better for models with angled features.

**Rule 6: Choose the right technique for each component:**

| Geometry | Best Approach | Expected Accuracy |
|----------|--------------|-------------------|
| Flat/angular (brackets, plates) | Profile extraction + linear_extrude | 90-96% |
| Diagonal features (angled arms, tapers) | Profile along thinnest axis + linear_extrude | 85-92% |
| Simple known shapes (stadium, box) | Parametric primitives + SDF optimizer | 90-96% |
| Cylindrical features (puzzle tabs, bosses) | Parametric circle() + square() | 85-95% |
| Smooth transitions (convex shapes only) | hull() between boundary profiles | 85-90% |
| Multi-width models (width varies along axis) | Dense X-slab (2mm profiles along thinnest axis) | ~92% |
| Mixed (curves + flats) | Polygon profile (hi-res, tol=0.02) | 70-80% |
| Complex organic shapes | import() original STL + parametric modifications | N/A |

**Rule 7: hull() ONLY for convex profiles.** Hull between two profiles creates the convex hull — it fills in ALL concavities (channels, clips, U-forks, hooks). Only use hull for simple solid zones with 1 contour and no holes. For concave profiles, use linear_extrude of a representative profile instead.

**Rule 8: Dense X-slab approach for complex models.**
When no single extrusion works, slice every 2mm along the thinnest axis:
1. At each X position, extract the full Y-Z cross-section (ALL bodies, not just the largest)
2. Extrude each slab for 2mm width
3. Union all slabs — gaps between bodies are naturally preserved
4. Note: this approach has a ~6% volume overestimate floor from polygon extraction artifacts. Below 6% requires hand-modeled parametric geometry.

**Use the automated reconstruction analysis FIRST — before writing any code:**
```bash
bash ~/.claude/skills/openscad/scripts/openscad-stl-reconstruct.sh model.stl output_dir/
```

This runs the full pipeline: mesh stats (trimesh), 2D profile slices (OpenSCAD projection), primitive detection (RANSAC/normal analysis), and generates SVG profiles at multiple Z levels. The SVG profile analysis is the MOST IMPORTANT output — it reveals the complete cross-section structure at each height level.

**The SVG Profile Method** (preferred over vertex analysis):
1. `projection(cut=true)` slices the STL at a Z height → exports 2D SVG
2. Parse the SVG to count contours: BODY (large area) vs HOLES (small area)
3. Compare contours at different Z levels to understand how the shape changes with height
4. This reveals: channels, slots, holes, wall thickness, taper angles — all from 2D data

**After analysis, verify with mesh comparison:**
```bash
bash ~/.claude/skills/openscad/scripts/openscad-stl-compare.sh original.stl reconstruction.stl output_dir/
```
Target: >95% geometric accuracy. Use diff images to identify remaining discrepancies.

### Step 1: Automated Analysis (run ALL tools)

```bash
# Tool 1: SVG profiling + primitive detection
bash ~/.claude/skills/openscad/scripts/openscad-stl-reconstruct.sh model.stl analysis/

# Tool 2: Profile extraction + extrusion axis detection
python3 ~/.claude/skills/openscad/scripts/openscad-profile-extract.py model.stl \
    --output analysis/profile.scad --json analysis/profile.json

# Tool 3: Adaptive multi-axis feature map
python3 ~/.claude/skills/openscad/scripts/openscad-adaptive-slice.py model.stl analysis/
```

**Key outputs to examine:**
- `analysis/slices/*.svg` — 2D profiles at 5 Z levels
- `analysis/profile.json` — extrusion axis, stability score, profile points, hole count
- `analysis/adaptive-slicing.json` — feature zones on all 3 axes, transition locations
- `analysis/primitives.json` — detected cylinders/planes
- `analysis/mesh-info.json` — volume, dimensions, symmetry

### Step 1b: Understand the Object (BEFORE writing code)

After running analysis tools, render multi-angle previews and answer:

1. **What are the main components?** (e.g. "bottom clip + diagonal arm + top clip")
2. **Which axis is thinnest?** Compare extents — the thinnest is likely the extrusion direction
3. **Are there diagonal/angled features?** If yes, the stability-score axis is probably WRONG
4. **Where do cross-sections change?** Check the adaptive slicer's transition zones
5. **Are there multi-body zones?** (channels, rails, gaps between parts)

**Decision tree — axis selection:**
1. If `stability_score < 0.1` AND thinnest axis matches stability axis → clean extrusion, use `profile.scad`
2. If model has **diagonal features** → use the **thinnest axis** regardless of stability score
3. If `stability_score < 0.3` AND no diagonals → stability axis + feature variations
4. If `stability_score > 0.3` → complex shape. Try dense X-slab along thinnest axis, or decompose into sub-objects

**Decision tree — technique per component:**
- Simple extruded body → profile + linear_extrude along extrusion axis
- Diagonal arm/strut → profile along thinnest axis captures it naturally
- Clips, hooks, U-channels → profile extraction (NOT hull — hull fills concavities)
- Cylindrical features → parametric circle() + square(), NOT polygon profiles
- Smooth convex transitions → hull() between boundary profiles (ONLY if convex)
- Complex multi-width → dense 2mm slabs along thinnest axis

**For models with cylindrical features** (stability > 0.3 or SVG shows circular contours):
- Do NOT rely on polygon profiles — they approximate curves poorly
- Identify circle centers and radii from the SVG contour data
- Model with `circle()` + `square()` in 2D, then extrude

Then render multi-angle previews:

```openscad
// Temporary viewer file
import("path/to/model.stl");
```

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh preview /tmp/stl-viewer.scad
```

Read all preview images to understand the 3D shape from multiple angles.

### Step 1b: Auto-Reconstruction — NOT IMPLEMENTED

⚠️ **`openscad-auto-reconstruct.py` does not exist in this repo.** The commands below fail with
"No such file or directory". They are kept as a specification of what the tool should do, not as
instructions you can follow. Skip to Step 2 and reconstruct by hand.

~~After running the adaptive slicer, use the auto-reconstructor to generate parametric .scad directly:~~

```bash
# Option A: With pre-computed analysis
python3 ~/.claude/skills/openscad/scripts/openscad-auto-reconstruct.py model.stl \
    --analysis analysis/ --output project/src/main.scad

# Option B: Run analysis + reconstruction in one step
python3 ~/.claude/skills/openscad/scripts/openscad-auto-reconstruct.py model.stl \
    --output project/src/main.scad --run-analysis

# Option C: Tighter circle fitting for precision parts
python3 ~/.claude/skills/openscad/scripts/openscad-auto-reconstruct.py model.stl \
    --analysis analysis/ --output project/src/main.scad --circle-threshold 0.3
```

This automatically:
1. Parses the feature map JSON into zones
2. Extracts profiles at zone boundaries
3. Fits circles/arcs to replace polygon approximations (Feature 3)
4. Generates hull() blends for transition zones (Feature 2)
5. Emits one OpenSCAD module per zone with sculptor assembly (Feature 1)

The output is a good starting point — review and refine the generated .scad, then verify with mesh comparison. For models with cylindrical features, this typically achieves >85% accuracy automatically (vs 75% with polygon-only).

### Step 2: Detailed Structure Mapping

**For simple models** (5 SVG slices are enough):
Parse the SVG contours to count bodies vs holes at each Z level.

**For complex models** (brackets, enclosures with multiple features):
Use the adaptive multi-axis slicer for efficient feature detection:
```bash
python3 ~/.claude/skills/openscad/scripts/openscad-adaptive-slice.py model.stl analysis/
```
This automatically: scans all 3 axes with coarse pass (5mm) → detects transitions → fine pass (0.5mm) around transitions. Produces a feature map classifying each zone as `solid`, `shell_or_channel`, `multi_body`, or `complex`.

For manual fine-grained slicing at specific heights:
```bash
for z in $(seq 0.5 1 <max_z>); do
    echo "projection(cut=true) translate([0,0,-$z]) import(\"model.stl\");" > /tmp/s.scad
    openscad -o "slices/z${z}.svg" /tmp/s.scad
done
```

Parse each SVG to build a structural map:
```
Z=0-5:   1 body (full width) + 8 holes     → Solid base with screw holes
Z=5-10:  2 bodies + 8 holes                → Channel appeared, walls split
Z=10-20: 2 bodies narrowing                → Taper zone (measure rate)
Z=20-33: 2 bodies constant width           → Top section
Z=25-27: Bodies interrupted                → Counterbore pockets at this depth
```

**Hole positions from SVG centroids** — for each hole contour at a given Z, compute the centroid. This gives exact X,Y positions far more reliably than vertex analysis.

**Feature verification rule:** If a feature doesn't appear as a distinct contour in the SVG data, IT DOES NOT EXIST in the model. Never add features based on visual interpretation of 3D renders alone.

### Step 3: Choose Approach and Decompose

Based on the analysis data, choose the reconstruction approach:

**Approach A — Profile Extrusion** (for extruded parts, stability < 0.3):
```bash
# The profile extractor already generated the .scad — use it as a starting point
cat analysis/profile.scad
# Adjust: add cavity with offset(delta=-wall), add floor, add features
```

**Approach B — Parametric Primitives** (for known shapes or cylindrical features):
Create a decomposition plan using measured dimensions from SVG data:
```
Decomposition:
1. Base: square([80, 80]) + circle tabs — from SVG outer contour at Z=mid
2. Cavity: offset(delta=-wall) of base — from SVG inner contour
3. Floor: solid at Z=0 to floor_h — from SVG at Z=0 (1 contour = solid)
4. Holes: cylinder(d=3) at SVG hole centroids
5. Counterbores: cylinder(d=8, h=2) at same positions
```

**Approach C — Hybrid** (for complex shapes with both flat and curved features):
1. Extract polygon profile for the overall outline
2. Identify which curves in the profile are circles (regular spacing, arc-like)
3. Replace those polygon sections with parametric `circle(r)` operations
4. Assemble: `square() + circle()` union for tabs, `difference()` for slots

**Counterbore vs Countersink** — always verify from reference images:
- **Counterbore**: flat cylindrical pocket (`cylinder(d=cb_d, h=cb_depth)`)
- **Countersink**: conical taper (`cylinder(d1=cs_d, d2=hole_d, h=cs_depth)`)
- Most 3D-printed parts use counterbores, not countersinks

### Step 4: Write Parametric .scad Code

Create a new project and write the reconstructed code:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-project.sh init "<name>-reconstructed"
```

**Key principles for reconstruction:**
- Extract ALL dimensions as named variables at the top
- Use meaningful variable names that describe the physical feature
- Add comments linking each section to the original STL features
- Include `echo()` statements for bounding box verification
- Add `assert()` for parameter ranges

### Step 5: Visual Comparison Loop

Render the reconstructed .scad and compare side-by-side with the original STL renders:

1. Render the reconstruction from the same camera angles as Step 1
2. Read both sets of images
3. Compare silhouettes, proportions, and feature placement
4. Identify the biggest discrepancy
5. Fix it and re-render
6. Repeat until the reconstruction matches the original

### Step 6: Overlay Verification

For precise verification, create an overlay .scad file:

```openscad
// Overlay: original STL (transparent) vs reconstruction
%import("path/to/original.stl");  // % = transparent background
color("red", 0.6) reconstructed_model();
```

Render this overlay — any RED areas visible through the transparent original indicate reconstruction errors. Any grey areas not covered by red indicate missing geometry.

### Step 7: Mesh-to-Mesh Comparison

**This is the most important verification step.** Export the reconstruction as STL and compare it against the original using boolean difference:

```bash
# Export reconstruction
bash ~/.claude/skills/openscad/scripts/openscad-render.sh stl ~/openscad-projects/<name>/src/main.scad

# Run mesh comparison
bash ~/.claude/skills/openscad/scripts/openscad-stl-compare.sh \
    path/to/original.stl \
    ~/openscad-projects/<name>/output/main.stl \
    ~/openscad-projects/<name>/previews/comparison
```

This produces:
- **diff-A-minus-B.png** — geometry in original but MISSING from reconstruction (what you need to add)
- **diff-B-minus-A.png** — EXTRA geometry in reconstruction not in original (what you need to remove)
- **overlay.png** — both models overlaid for visual check
- **Geometric accuracy %** — based on volume of boolean differences vs original volume

**Target: >95% geometric accuracy.** If below 95%, examine the diff images to identify which features are wrong, fix them, re-export, and re-compare. Iterate until accuracy is satisfactory.

**Important:** Bounding box delta can be 0.000mm while geometric accuracy is only 78% — internal features matter more than outer dimensions.

### Step 8: Dimensional Verification

Compare echo output from the reconstruction with the STL bounding box:

```openscad
echo(str("Reconstructed BBOX: ", width, " x ", depth, " x ", height));
```

### Step 9: SDF Parameter Optimization (Advanced)

If the SVG profile method doesn't achieve >95% accuracy, use the SDF optimizer for automatic parameter tuning:

```bash
python3 ~/.claude/skills/openscad/scripts/openscad-sdf-optimize.py \
    path/to/original.stl \
    stadium-slot \
    --verbose \
    --output analysis/sdf-result.json
```

This works by:
1. Sampling 30,000 random points in the bounding box
2. Computing target occupancy (inside/outside original mesh) via trimesh
3. Defining the reconstruction as a parametric SDF (Signed Distance Field)
4. Using `scipy.optimize.minimize(method="Powell")` to maximize IoU (Intersection over Union)
5. Generating OpenSCAD code with optimized parameters

**When to use**: When you know the correct model topology (e.g., "stadium body with cylindrical slot") but can't find the exact parameters. The optimizer finds them automatically.

**Supported model types**: `stadium-slot`, `box-holes`. Add new types by defining an SDF function in the script.

**Workflow**: Run `openscad-stl-reconstruct.sh` first (to identify the model topology), then `openscad-sdf-optimize.py` (to find exact parameters), then `openscad-stl-compare.sh` (to verify).

**Prerequisites**: `pip3 install trimesh numpy scipy rtree`

### Common Pitfalls

- **Bounding box match ≠ correct model.** A model with completely wrong internal geometry can still have a 0.000mm bounding box delta. Always verify visually from multiple angles.
- **Don't assume features from renders alone.** What looks like a cylinder in a top-down view might just be a curved wall edge. Always verify with vertex analysis.
- **Coincident faces cause Z-fighting.** If a feature touches the body boundary exactly, use `intersection()` to clip it cleanly rather than making it the exact same size.
- **Don't flip between adding and removing features.** If unsure whether a feature exists, run cross-section analysis before deciding. Oscillating between "add bar" and "remove bar" wastes iterations.
- **Offset features are common.** Cylinders, holes, and channels are often NOT centered. Always calculate the actual center from vertex data rather than assuming symmetry.

### Limitations

- **Organic shapes** (sculpted, freeform surfaces) cannot be fully reconstructed as primitives. For these, keep the STL import and wrap it in a module.
- **Very complex models** (1000+ features) should be reconstructed incrementally, starting with the major body and adding features one group at a time.
- **Thread geometry** in STL is extremely difficult to reconstruct. Use `threads.scad` library instead of trying to match individual thread faces.
- **Text/engravings** embedded in STL meshes are very hard to extract. It's better to re-add text using OpenSCAD's `text()` module.

### Hybrid Approach

For complex models, use a hybrid strategy:
```openscad
// Import the complex organic base from STL
module original_base() {
    import("base-section.stl");
}

// Reconstruct and parameterize the mechanical features
module mounting_bracket(width=30, hole_d=5) {
    difference() {
        original_base();
        // Add parametric mounting holes
        for (pos = hole_positions)
            translate(pos) cylinder(d=hole_d, h=50, center=true);
    }
}
```

This lets the user modify the parametric parts while keeping the complex geometry intact.

---

## Workflow: Refine Mode

When the user wants to modify an existing design:

### Step 1: Read the Existing File

```bash
# Find .scad files in the project
```
Read the .scad source to understand the current design.

### Step 2: Render Current State

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh preview /path/to/file.scad
```

Read the preview images to see what currently exists.

### Step 3: Apply Changes

Edit the .scad file with the requested modifications. Use the Edit tool for surgical changes.

### Step 4: Re-render and Compare

Generate new previews and visually compare with the previous version. Report what changed.

### Step 5: Repeat or Export

Continue iterating or export when satisfied.

---

## Workflow: Export Mode

Quick export of an existing .scad file:

```bash
# Single format
bash ~/.claude/skills/openscad/scripts/openscad-render.sh stl /path/to/file.scad

# Multiple formats
bash ~/.claude/skills/openscad/scripts/openscad-render.sh export /path/to/file.scad

# With parameter overrides
bash ~/.claude/skills/openscad/scripts/openscad-render.sh stl /path/to/file.scad -D 'width=50' -D 'height=30'
```

---

## Workflow: Analyze Mode

Review a design for printability:

```bash
bash ~/.claude/skills/openscad/scripts/openscad-render.sh analyze /path/to/file.scad
```

This renders cross-section views and reports:
- Object bounding box dimensions
- Whether the mesh is manifold (watertight)
- Estimated print time indicators (volume, surface area from STL)
- Visual check of overhangs via bottom-up view

---

## Script Reference

All scripts live in `~/.claude/skills/openscad/scripts/`:

| Script | Purpose |
|--------|---------|
| `openscad-render.sh` | Core render/export/preview engine |
| `openscad-project.sh` | Project scaffolding and management |
| `openscad-validate.sh` | Strict validation with categorized error output |
| `openscad-stl-analyze.sh` | STL mesh analysis: bbox, cross-sections, gap detection |
| `openscad-stl-compare.sh` | Mesh comparison: boolean diff, volume delta, accuracy % |
| `openscad-stl-bore.py` | Recover the NOMINAL diameter of a round feature from a shipped STL — what a part you already printed actually measures, when the source has moved on |
| `openscad-slice-check.sh` | Assert a sliced G-code matches the physical plate and filament |
| `openscad-stl-reconstruct.sh` | Automated STL analysis: profiles, primitives, CSG inference |
| `openscad-sdf-optimize.py` | SDF-based parameter optimizer (IoU scoring, no OpenSCAD in loop) |
| `openscad-adaptive-slice.py` | Adaptive multi-axis slicing (coarse→transitions→fine on X,Y,Z) |
| `openscad-auto-reconstruct.py` | **MISSING — not implemented.** Referenced by Reconstruct mode Step 1b; do not call it |

### openscad-render.sh Commands

```bash
# Quick single preview (isometric)
openscad-render.sh quick <file.scad>

# Multi-angle preview (4 views)
openscad-render.sh preview <file.scad>

# Export STL only
openscad-render.sh stl <file.scad> [-D 'var=val' ...]

# Export all formats (STL + 3MF + PNG)
openscad-render.sh export <file.scad> [-D 'var=val' ...]

# Analyze printability
openscad-render.sh analyze <file.scad>

# Custom render
openscad-render.sh custom <file.scad> --format png --imgsize 1920,1080 --camera 0,0,0,45,0,30,200
```

### openscad-project.sh Commands

```bash
# Initialize new project
openscad-project.sh init <project-name>

# List projects
openscad-project.sh list

# Clean build artifacts
openscad-project.sh clean <project-name>
```

---

## OpenSCAD Code Guidelines

### File Structure Convention

```openscad
// ============================================
// Project: <name>
// Description: <what this models>
// Author: Claude Code + User
// ============================================

// --- Parameters (user-configurable) ---
width = 50;        // [mm] overall width
height = 30;       // [mm] overall height
depth = 20;        // [mm] overall depth
wall = 2.0;        // [mm] wall thickness
tolerance = 0.3;   // [mm] printer tolerance

// --- Rendering quality ---
$fn = 64;          // curve smoothness (use 128+ for final export)
eps = 0.01;        // epsilon for clean boolean operations

// --- Derived dimensions ---
inner_width = width - 2 * wall;
inner_height = height - 2 * wall;

// --- Main model ---
main_assembly();

// --- Modules ---
module main_assembly() {
    // ...
}
```

### 3D Printing Best Practices in OpenSCAD

- **Wall thickness**: minimum 1.2mm for FDM (2-3 perimeters with 0.4mm nozzle)
- **Tolerance**: 0.2-0.3mm clearance for fitting parts together (peg-in-hole, snap fits)
- **Overhangs**: keep below 45 degrees from vertical, or add support. Get the evidence from
  `openscad-overhang-audit.py` and the verdict from the sliced preview — a root gusset does
  not support a residual horizontal underside.
- **Chamfer vs fillet**: prefer chamfers on downward-facing surfaces (avoids supports); use fillets on top surfaces
- **Bridging**: max ~10mm unsupported spans
- **First layer**: design flat bottoms for bed adhesion; largest flat surface on build plate
- **Epsilon constant**: always define `eps = 0.01;` and use it in boolean operations to prevent Z-fighting / coplanar faces
- **Manifold geometry**: always ensure boolean operations produce valid solids; operands must overlap
- **Resolution**: use `$fn = 64` for preview, `$fn = 128` for export
- **Design intent**: Define hole positions relative to edges (`hole_x = length - margin`), never as absolute coordinates
- **Tolerance chains**: Define a single `fit_clearance` parameter and derive all clearances from it
- **Assert validation**: Use `assert()` to validate parameters: `assert(wall >= 1.2)`, `assert(boss_d > hole_d + 2*wall)`
- **Profile-first**: Use `offset(r=corner_r)` on 2D `polygon()` instead of `hull()` with 3D cylinders

### Designing for FDM: geometry rules

The bullets above are the defaults. These are the shape decisions that change what the
slicer can do, and most of them are cheaper to make in the model than in the slicer.

**Chamfer, then fillet.** A fillet on a bottom edge starts as a near-horizontal overhang
and prints badly at any size. A chamfer is a constant 45° and prints clean. To get a
fillet's look without the overhang, chamfer first and then fillet the chamfer. As a
finishing pass on the whole part: fillets first, then chamfers, gives the nicest
transitions.

**Orientation is a strength decision, not just an adhesion one.** Layer adhesion is the
weak direction. Orient so the weak direction carries the largest cross-section. A handle
printed lying flat, layers running along it, is strong; the same handle standing up snaps.
Record the intended orientation in the source next to the geometry that depends on it.

**Angle the whole part** before adding supports. Rotating a part is often enough to bring
every overhang under 45° and is free.

**Teardrop holes on vertical walls.** A circular hole in a side wall has a horizontal
overhang at its crown, so large holes come out undersized and rough. Cut the crown away
and replace it with a roof of two flat faces at 60° from horizontal, i.e. 30° from
vertical. A 45° roof is the conservative version if the printer has not been tested:

```openscad
module teardrop_hole(d, h, eps = 0.01) {
    r = d / 2;
    rotate([-90, 0, 0])
        linear_extrude(height = h + 2*eps, center = true)
            union() {
                circle(r = r, $fn = 64);
                // 60 deg from horizontal roof over the crown
                polygon([[-r, 0], [r, 0], [0, r / tan(30)]]);
            }
}
```

**Sacrificial bridging surfaces over a nut pocket.** When the bolt hole opens into a nut
pocket in the bottom face, the hole prints in midair and the bore is ragged. Leave two
0.2 mm surfaces, one per bridging direction, so the printer bridges first and prints the
hole on a foundation.

**Nut pockets entered from the side** need two of the pocket's parallel faces vertical,
otherwise the remaining faces want support. A square nut in a rectangular side pocket is
a good alternative to a heat-set insert when the back of the part is inaccessible.

**Blocky beats lightweighted.** Injection-molding style weight-saving pockets make a
printed part less rigid without saving material, and slower to print: infill already
provides the internal stiffening, and every pocket trades fast infill for slow perimeters.
Do not port a die-cast or molded part's ribbing pattern into a printed one.

**Clearances are anisotropic.** A single `fit_clearance` is still the right structure, but
sides need more gap than top and bottom faces, and small screw holes in vertical walls
print undersize because of the crown overhang. If a part has fits in more than one
orientation, derive from `fit_clearance` with an orientation factor rather than one number.

**Model your own breakaway supports** for large, thin, awkward parts. Geometry in the model
that is snapped off afterwards is more repeatable than slicer supports.

**Print-in-place** is not only for toys. Interlocked geometry that prints in one go removes
assembly steps entirely, up to and including ball bearings printed inside their cage.

**Text: model the surround, not the glyphs.** For two-color text, put the face down on the
bed, make the first layer the background and the second the contrasting fill. This is
crisper than raised or engraved text at small sizes, because the minimum extrusion width
limits how thin a printed stroke can be, while the *gap* between two adjacent extrusions
can be much finer.

**Iterate on a section.** When testing a large design, print only the region you changed.

Source for these: Alexandre Chappel, "Everything I know about 3D Printing"
(https://www.youtube.com/watch?v=gPW_mitgosw).

### Fitting to a part that already exists

The moment one half of a mating pair has been printed, the problem stops being
"choose a clearance" and becomes "hit a dimension that is already fixed". Four
rules, each of which cost a print cycle to learn:

**1. The printed part's interface is FROZEN. Adjust the other half.**
Interference can be taken out of the pin or out of the hole — arithmetically
identical for a matched pair printed together, and *useless* if the hole is
already sitting on the bench. Put the adjustment on the half you are about to
print, and say so in the source, because the next edit will not remember:

```openscad
// FROZEN: this is what the shell ON THE BENCH was printed with (commit 72bb89e),
// verified by measuring the shipped STL. Changing it orphans a printed part.
spigot_socket_d = 4.95;
spigot_d = spigot_socket_d + spigot_press;   // every adjustment lands here
```

Prefer freezing the dimension of the part that is **expensive to reprint** — a
3-hour shell outranks a 3-minute pin.

**2. Measure the shipped STL, not the .scad.**
The source describes the part you are *about to* print; it has moved on since the
one you printed. Read the artifact:

```bash
python3 ~/.claude/skills/openscad/scripts/openscad-stl-bore.py \
        output/shell.stl --at 25.9,18.4 --max-r 6
```

OpenSCAD inscribes its polygons, so the largest vertex radius **is** the nominal
radius to full precision — this recovers design intent exactly, not an estimate.
Measured cost of skipping it: a socket the source called Ø4.60 and the printed
part had at Ø4.95, a 0.35 mm error in the one dimension that mattered.

Do not compare two renders by `md5` or by volume to decide whether geometry
changed — a `$fn` difference alone moves both. Compare the bounding box and the
specific feature, or use `openscad-stl-compare.sh`.

**3. A test coupon must vary exactly ONE thing, from a verified baseline.**
A coupon that shrinks the hole *and* grows the pin cannot tell you which one was
wrong when it seizes; its failure carries no information. Reproduce the real
feature exactly — same diameters, same engagement depth, same print orientation,
same shoulder — and change one number across the samples.

**4. Anchor the ladder on MEASURED endpoints, not on the nominal.**
A ladder must straddle the answer: one rung you expect to fail *loose*, one you
expect to fail *tight*. Otherwise every sample fails the same way and a whole
print returns a single bit — "all too tight" — which you could have predicted.

The nominal diameter is not an anchor. It is exactly the number that misleads
here, because the bore prints undersize while the pin prints oversize and the
two errors add: a pin 0.05 *under* a Ø4.95 nominal bore would not enter it.
Measured cost: a ladder spanning nominal −0.05…+0.10 in which all four rungs
bound, while the datum that would have placed it correctly — an earlier pin at
4.60 that was *loose in that same hole* — was already in hand and unused.

So before choosing rungs, write down the two endpoints you actually know:
```
4.60  LOOSE          (measured: the as-printed part)
4.90  WILL NOT ENTER (measured: ladder 1, rung 1)
```
and put the rungs inside them. If you only have one endpoint, make the far rung
deliberately extreme to establish the other — an unbracketed ladder is a guess
with four decimal places.

Label the samples: at 0.05 mm apart they are identical to the eye, and an
unlabelled winner teaches nothing. **Continue the numbering across ladders**
(5,6,7,8 after 1,2,3,4) — both sets end up in the same drawer, and two pucks
stamped "1" is a measurement waiting to be misattributed.
`templates/fit-ladder.scad` does all of this.

### Common Patterns

**Rounded box:**
```openscad
module rounded_box(size, radius) {
    minkowski() {
        cube([size.x - 2*radius, size.y - 2*radius, size.z - radius]);
        cylinder(r=radius, h=radius);
    }
}
```

**Shell (hollow object):**
```openscad
module shell(outer_size, wall) {
    difference() {
        cube(outer_size);
        translate([wall, wall, wall])
            cube([outer_size.x - 2*wall, outer_size.y - 2*wall, outer_size.z]);
    }
}
```

**Screw hole with countersink:**
```openscad
module screw_hole(d=3, h=10, cs_d=6, cs_h=2) {
    union() {
        cylinder(d=d, h=h);
        translate([0, 0, h - cs_h])
            cylinder(d1=d, d2=cs_d, h=cs_h);
    }
}
```

---

## Available Libraries

Popular libraries that can be installed for advanced features:

| Library | Use Case | Install |
|---------|----------|---------|
| **BOSL2** | Swiss-army knife: attachments, shapes, threading, paths | `git clone https://github.com/BelfrySCAD/BOSL2 ~/.local/share/OpenSCAD/libraries/BOSL2` |
| **NopSCADlib** | Vitamins (screws, nuts, electronics, bearings) | `git clone https://github.com/nophead/NopSCADlib ~/.local/share/OpenSCAD/libraries/NopSCADlib` |
| **threads.scad** | Metric threads, hex bolts, nuts | `git clone https://github.com/rcolyer/threads-scad ~/.local/share/OpenSCAD/libraries/threads` |
| **Round-Anything** | Smooth fillets and rounding | `git clone https://github.com/Irev-Dev/Round-Anything ~/.local/share/OpenSCAD/libraries/Round-Anything` |
| **YAPP_Box** | Parametric project enclosures | `git clone https://github.com/mrWheel/YAPP_Box ~/.local/share/OpenSCAD/libraries/YAPP_Box` |
| **Catch'n'Hole** | Nut catches, screw holes | `git clone https://github.com/mmalecki/catchnhole ~/.local/share/OpenSCAD/libraries/catchnhole` |

Check installed libraries:
```bash
ls ~/.local/share/OpenSCAD/libraries/ 2>/dev/null      # user libraries, both platforms
ls /usr/share/openscad/libraries/ 2>/dev/null          # system libraries, Linux
ls /opt/homebrew/share/openscad/libraries/ 2>/dev/null # system libraries, macOS
```

When user needs a library, install it and add `use <library/file.scad>` to the .scad source.

---

## Error Handling

When OpenSCAD fails:

1. **Parse errors** — `ERROR: Parser error: syntax error in file X, line Y`
   - Read the .scad file at the reported line
   - Fix syntax (common: missing semicolons, unmatched braces/parens, wrong function names)
   - Re-render

2. **Geometry errors** — `WARNING: Object may not be a valid 2-manifold`
   - Check boolean operations aren't creating degenerate geometry
   - Ensure shapes overlap properly for difference/intersection
   - Add small epsilon offsets (0.01mm) to prevent coplanar faces

3. **Rendering timeouts** — complex models with high `$fn`
   - Lower `$fn` for preview (32), raise for export (128)
   - Simplify geometry where possible
   - Use `render()` to cache intermediate results

4. **Empty output** — model produces no geometry
   - Check that modules are actually called
   - Verify boolean operations don't subtract everything
   - Use `echo()` statements to debug variable values

Always capture stderr when rendering — it contains warnings and errors:
```bash
openscad -o output.stl input.scad 2>&1
```

---

## Camera Presets for Multi-View

| View | Camera Parameters |
|------|-------------------|
| Front | `--camera 0,0,0,90,0,0,<dist>` |
| Back | `--camera 0,0,0,90,0,180,<dist>` |
| Right | `--camera 0,0,0,90,0,90,<dist>` |
| Left | `--camera 0,0,0,90,0,270,<dist>` |
| Top | `--camera 0,0,0,0,0,0,<dist>` |
| Bottom | `--camera 0,0,0,180,0,0,<dist>` |
| Isometric | `--autocenter --viewall` (default) |
| 3/4 view | `--camera 0,0,0,55,0,25,<dist>` |

Use `--autocenter --viewall` to auto-calculate distance, or specify explicit distance for consistent framing across iterations.
