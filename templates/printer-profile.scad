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
min_wall        = 1.2;   // thinnest wall that survives FDM
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
