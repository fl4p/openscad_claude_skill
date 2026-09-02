// ============================================
// printer-profile.scad — Measured behaviour of THE printer you actually own
// Included automatically by printable-lib.scad
// ============================================
//
// WHY THIS FILE EXISTS
//
// Generating a part takes seconds. Finding out that the 5mm hole does not accept
// a 5mm bolt takes a whole print cycle — 30 to 60 minutes. That single number is
// where the time goes, not the modelling.
//
// Generic clearance values are a guess about someone else's printer. The values
// below become real after you print templates/calibration-comb.scad ONCE and
// measure it. From then on every quick part fits on the first print.
//
// HOW TO CALIBRATE (once, ~40 minutes of printing, 5 minutes of measuring)
//
//   1. openscad -o comb.stl templates/calibration-comb.scad
//   2. Print it with the filament and profile you use for functional parts.
//   3. Take the 6.00mm test pin (printed alongside) and try it in each hole.
//      Read the label under the hole that behaves the way you want:
//        - press : goes in with force, stays put without glue
//        - close : goes in by hand, no wobble          <- the everyday default
//        - slide : moves freely, no play worth naming
//        - loose : drops in, obvious play
//   4. Measure the 20.00mm calibration block with a caliper, on X and on Y.
//   5. Write the numbers below and set profile_measured = true.
//
// UNTIL THEN the values are declared defaults, not measurements. The skill says
// so out loud whenever it emits a part that depends on a fit.

// --- Provenance -----------------------------------------------------------
profile_measured = false;          // set true only after the comb is printed and measured
profile_printer  = "Bambu Lab P1P";
profile_filament = "";             // clearances differ per material: PLA != PETG != ABS
profile_nozzle   = 0.4;
profile_date     = "";             // YYYY-MM-DD of the measurement

// --- Clearances (mm added to a hole diameter to reach the wanted fit) -----
// Measured as: hole_that_worked - 6.00
//
// PARTIAL CALIBRATION, 2026-08-16. The comb has NOT been printed, so
// profile_measured stays false and close/slide/loose below are still declared
// defaults. What HAS been measured on this machine is a single press fit:
//
//   PLA, 0.4 nozzle, 0.20 mm layers, textured PEI
//   Ø4.95 nominal bore, 5.3 mm deep, hole axis vertical, pin printed upright
//   pin ladder 4.65 / 4.72 / 4.79 / 4.86
//     -> 4.79 firm to seat and separable with deliberate force
//        4.86 and above too tight; 4.90 would not enter; 4.60 loose
//   => press clearance = 4.95 - 4.79 = 0.16
//
// One diameter, one orientation, one material. It does not license the other
// three fits and it says nothing about xy_expansion -- print the comb for those.
clearance_press  = 0.16;   // MEASURED (above)
clearance_close  = 0.25;   // declared default, unmeasured
clearance_slide  = 0.30;   // declared default, unmeasured
clearance_loose  = 0.40;   // declared default, unmeasured

// --- Horizontal expansion -------------------------------------------------
// How much wider the printer makes a part than the model says, per side.
// Measured as: (measured_block - 20.00) / 2. Positive means it prints fat.
// Holes come out that much SMALLER, which is why they need clearance at all.
xy_expansion = 0.00;

// --- Print constraints ----------------------------------------------------
// Used by the deterministic pre-flight gate before any render is looked at.
min_wall        = 1.2;   // thinnest WALL that survives FDM
// The thinnest RIB, FINGER, or SPOKE -- a feature narrow in one direction that
// the slicer must fill with whole extrusion lines.  It is a different number
// from min_wall and it is the one that gets forgotten, because a model can be
// manifold, overhang-clean, and correct in the Prepare view while slicing into
// single unbonded lines.  Measured 2026-09-02: a snap finger 0.70 mm at its
// thickest, tapering to zero at its edges, sliced to ONE extrusion per layer
// and printed as a stack of loose rings -- a coil, not a beam.
//
// Two lines is the floor; anything load-bearing wants three.  Check the
// THINNEST station of the feature, not its nominal size: a tapered finger is
// only as good as its tip.
//
// WHY single lines fail here is NOT established.  "Nothing to bond to sideways"
// was the first explanation written down and it does not survive contact with
// vase mode, which is single-width and bonds perfectly well.  Candidates that
// remain open: cooling of a tiny island, seam start/stop behaviour, layer-to-
// layer overlap collapsing as the path shifts, under-extrusion of an adaptive
// thin path, or the nozzle knocking a weak tall feature.  Treat 2*nozzle as a
// CALIBRATED THRESHOLD with a known-bad on one side of it and a known-good on
// the other -- which is all a screening gate needs to be -- not as a mechanism.
// The transition is not located: 0.50 mm failed and 0.90 mm worked, and nothing
// was printed in between.  So the calibrated result is an INTERVAL, (0.50, 0.90],
// and 2*nozzle = 0.80 is a heuristic chosen inside it.  A feature at 0.80-0.89
// passes this gate on the heuristic alone, untested -- if you are sitting in
// that band, print the coupon rather than trusting the constant.
min_rib         = 2 * profile_nozzle;
// The constructive twin of min_rib.  min_rib says never fewer than two lines;
// this says LAND ON a whole number of them.  A wall sized to an exact multiple
// of the line width is all perimeter -- no infill lane, no top/bottom skins,
// no internal-bridge course -- so it is both lighter and stronger than a wall
// 0.3 mm thicker.  Measured 2026-09-02: a lid skirt at 1.8 mm -- exactly 4 x 0.45
// -- printed solid; the same skirt at 3.5 mm printed two walls with lattice
// between them.
//
// Line width is NOT the nozzle diameter.  Read it from the sliced file, where
// Orca states a resolved `; LINE_WIDTH:` before every feature; do NOT look in
// the profile (auto widths store 0) and do NOT reconstruct it from extrusion
// volume, which answers a different question -- an equivalent rectangle rather
// than a rounded bead -- and returns 0.399 where the slicer says 0.45.
//   wall = wall_lines(4);        // -> 4 * 0.45 = 1.80
// Treat the result as a target to land NEAR, not a product to trust: Arachne
// stretches perimeters to fill whatever you asked for, so nearby thicknesses
// keep the same path count and merely cost weight -- but far enough away the
// count, the gap fill and the stiffness all change together.
function wall_lines(n, w = profile_wall_line_width) = n * w;
// From the G-code body, not the nozzle diameter.  Re-read it if the profile,
// nozzle or layer height changes.
profile_wall_line_width = 0.45;
// The mirror of min_rib: the narrowest GAP the slicer will leave OPEN.  Two
// solids closer than about two line widths tend to fuse into one, and a split
// snap pin whose slot fuses is a solid rod -- it looks right and cannot flex.
// DECLARED, NOT MEASURED: no coupon has bracketed it on this machine, which is
// why push_pin warns rather than asserts below it.  pins-test-snap3 sweeps
// 0.6..1.0 mm to find it; write the answer here when it comes off the bed.
min_gap         = 2 * profile_nozzle;
min_floor       = 0.8;
max_overhang    = 45;    // degrees from vertical, beyond which support is needed

// Design strain for a snap-fit finger.  This is a MATERIAL property, not a
// printer one, and it is the number that decides whether a clip assembles or
// snaps off -- so it is here rather than buried in the module that uses it.
// PLA is brittle: 1.5 % for a fastener meant to be assembled more than once,
// 2 % for a one-time snap.  PETG ~2.5 %, ABS/ASA ~3 %, nylon ~5 %.
//
// PROVENANCE: these are handbook design strains for MOULDED stock.  They are
// not measured here, and profile_filament above is empty -- so a gate built on
// this number knows neither the material nor the print orientation it is
// judging.  A printed finger loaded ACROSS its layer interfaces fails by
// delamination, which this figure does not describe at all; calling it
// "conservative" for that case would be an assumption, not a derate.  Treat a
// pass as necessary and not sufficient until a coupon in the same orientation
// has been cycled, and set profile_filament before relying on it.
snap_strain_max = 0.015;
bed_size        = [256, 256, 256];   // Bambu Lab P1P build volume
