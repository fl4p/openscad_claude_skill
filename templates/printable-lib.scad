// ============================================
// printable-lib.scad — Reusable modules for 3D printing
// Include with: use <printable-lib.scad>
// ============================================

eps = 0.01;  // epsilon for clean boolean operations

// Measured behaviour of the actual printer. Every fit in this library descends
// from here, so calibrating once fixes every part that comes after.
// How to measure it: see the header of printer-profile.scad.
include <printer-profile.scad>

// --- Clearance helpers ---
// Returns the clearance for a fit type, read from the printer profile.
// A part built on these numbers is only as trustworthy as profile_measured.
function fit_clearance(kind="close") =
    kind == "press"  ? clearance_press :
    kind == "close"  ? clearance_close :
    kind == "loose"  ? clearance_loose :
    kind == "slide"  ? clearance_slide : clearance_close;

// --- Shell / Hollow box ---
module shell_box(outer=[60,40,20], wall=2, floor=2) {
    assert(wall >= 1.2, "wall too thin for FDM (min 1.2mm)");
    assert(floor >= 0.8, "floor too thin (min 0.8mm)");
    difference() {
        cube(outer);
        translate([wall, wall, floor])
            cube([outer.x - 2*wall, outer.y - 2*wall, outer.z - floor + eps]);
    }
}

// --- Rounded box (hull-based) ---
module rounded_box(size, r=2) {
    hull() {
        for (x = [r, size.x - r])
            for (y = [r, size.y - r])
                translate([x, y, 0])
                    cylinder(r=r, h=size.z);
    }
}

// --- Screw clearance hole ---
module screw_clearance_hole(d=3, h=10, fit="close") {
    cylinder(h=h + 2*eps, d=d + fit_clearance(fit), $fn=48);
}

// --- Counterbore hole (for socket head cap screws) ---
// Head pocket at entry side (top), shaft goes through
module counterbore_hole(shaft_d=3, head_d=6, head_h=3, h=12) {
    union() {
        screw_clearance_hole(shaft_d, h);
        translate([0, 0, h - head_h + eps])
            cylinder(h=head_h + eps, d=head_d, $fn=48);
    }
}

// --- Countersink hole ---
module countersink_hole(d=3, cs_d=6, cs_h=2, h=10) {
    union() {
        cylinder(d=d, h=h + 2*eps, $fn=48);
        translate([0, 0, h - cs_h + eps])
            cylinder(d1=d, d2=cs_d, h=cs_h, $fn=48);
    }
}

// --- Heat-set insert boss ---
module heatset_boss(insert_d=4.6, insert_h=5, wall=2, h=8) {
    assert(wall >= 1.6, "boss wall too thin for heat-set insert");
    difference() {
        cylinder(h=h, d=insert_d + 2*wall, $fn=64);
        translate([0, 0, -eps])
            cylinder(h=insert_h + 2*eps, d=insert_d, $fn=64);
    }
}

// --- Screw post (solid post with hole) ---
module screw_post(outer_d=7, inner_d=3, h=10) {
    difference() {
        cylinder(d=outer_d, h=h, $fn=48);
        translate([0, 0, -eps])
            cylinder(d=inner_d, h=h + 2*eps, $fn=48);
    }
}

// --- Structural rib / gusset ---
module rib(len=20, height=12, thick=2) {
    linear_extrude(height=thick)
        polygon([[0, 0], [len, 0], [0, height]]);
}

// --- Chamfer edge (for print-friendly overhangs) ---
module chamfer_edge(length=10, size=1) {
    translate([0, 0, -eps])
        linear_extrude(height=length)
            polygon([[0, 0], [size, 0], [0, size]]);
}

// --- Snap-fit strain ---
// eps = 3*y*t / (2*L^2) for a straight cantilever of RECTANGULAR section, where
// y is the deflection the hook must make, t the finger thickness in bending and
// L the FREE length -- root to hook, excluding anything embedded in the parent.
// A rectangular finger tapering to half thickness at the tip carries ~1.16x the
// deflection for the same strain; pass taper=true.  That 0.86 factor is for a
// WIDTH-tapered rectangle and nothing else: do not claim it for a section whose
// thickness or shape changes along the length.
//
// The trap this exists to close: L is squared, so a clip that is a little too
// short is not a little too weak, it is broken.  The old default here --
// length=6, thick=1.5, overhang=0.8 -- computes to 5 % strain and snaps off a
// PLA part on first assembly.  L had to be 11 mm for those numbers to work.
//
// Domain-checked, because a negative y or t silently returns a negative strain
// that passes every <= gate.
function snap_strain(y, t, L, taper = false) =
    assert(y > 0, "snap_strain: deflection y must be > 0")
    assert(t > 0, "snap_strain: thickness t must be > 0")
    assert(L > 0, "snap_strain: free length L must be > 0")
    (taper ? 0.86 : 1) * 3 * y * t / (2 * L * L);

// The strain limit is a MATERIAL number and the profile may not know the
// material.  Bound it, and say so when it is a handbook default rather than a
// measured one -- an unqualified 1.5 % is a starting point, not a guarantee.
function strain_limit() =
    assert(snap_strain_max > 0 && snap_strain_max <= 0.06,
           str("snap_strain_max = ", snap_strain_max, " is outside 0..0.06. ",
               "A bare '1' means 100 % strain, not 1 %."))
    snap_strain_max;

// --- Split-shaft finger section -------------------------------------------
// A pin split by a slot does NOT have a rectangular section.  Each finger is a
// circular segment, so its neutral axis sits toward the flat and the outer
// fibre is FARTHER from it than t/2.  Using t/2 understates strain by ~17 % on
// a 3 mm shaft, which is the difference between passing and failing a gate.
// Returns the outer-fibre distance c to use in eps = 3*y*c/L^2.
function seg_c_out(shaft_d, slot_w) =
    assert(slot_w > 0 && slot_w < shaft_d, "seg_c_out: need 0 < slot_w < shaft_d")
    let (R = shaft_d/2, a = slot_w/2,
         th = acos(a/R),                       // degrees
         A  = R*R * (th*PI/180 - sin(th)*cos(th)),
         yc = (2/3) * R*R*R * pow(sin(th), 3) / A)
    R - yc;

// --- Snap-fit tab ---
// Cantilever arm along +Y, bending in Z, with a barb standing proud in +Z at
// the free end: a vertical retention face on the root side and a lead-in ramp
// toward the tip.  The barb must protrude BEYOND the arm's own envelope or it
// is not a barb -- an earlier version of this module put the "hook" inside the
// arm's Z envelope, so `overhang` named a deflection the geometry never made.
//
// `free_length` is the root-to-barb length and it is what the strain gate uses.
// The root fillet is drawn at NEGATIVE y, outside that length, so the caller
// embeds everything at y <= 0 and the asserted length is the real one.
module snap_tab(width=8, free_length=12, thick=1.5, overhang=0.8, ramp=2, root_r=1) {
    assert(ramp > 0 && ramp < free_length, "snap_tab: need 0 < ramp < free_length");
    assert(root_r >= 0, "snap_tab: root_r must be >= 0");
    eps_ = snap_strain(overhang, thick, free_length);
    assert(eps_ <= strain_limit(),
           str("snap tab over the strain budget: ", eps_*100, " % > ",
               strain_limit()*100, " %. Lengthen it (L is squared), thin it, ",
               "or reduce the barb."));
    union() {
        cube([width, free_length, thick]);
        // barb: flat catch face at free_length-ramp, ramping down to the tip
        translate([0, 0, 0]) rotate([90, 0, 90])
            linear_extrude(height = width)
                polygon([[free_length - ramp, thick],
                         [free_length - ramp, thick + overhang],
                         [free_length,        thick]]);
        // root fillet, at y < 0 so it is not counted as free length
        if (root_r > 0)
            translate([0, 0, 0]) rotate([90, 0, 90])
                linear_extrude(height = width)
                    difference() {
                        translate([-root_r, 0]) square([root_r, root_r]);
                        translate([-root_r, root_r]) circle(r = root_r, $fn = 32);
                    }
    }
}

// --- Push-pin, and the bore that receives it -------------------------------
// A separate pin beats a snap post moulded into the frame whenever the mating
// part cannot be lowered straight down -- anything that slides, hinges or drops
// in at an offset.  A fixed post standing in a mounting hole can only be entered
// from directly above; a pin dropped in AFTER the part is seated does not care
// how the part got there.  It also keeps metal out of plated holes.
//
// The pin and its bore are ONE joint and are described by ONE parameter set.
// They used to be two independent signatures, and two independently valid
// signatures can still describe a joint whose barb never leaves the narrow
// bore.  Build the vector once, hand it to both.
//
//  0 grip      board thickness + frame kept under the seat; the fingers' free
//              length is the SLOT length, which runs the whole pin (see below)
//  1 board     the part being pinned
//  2 hole_d    the board's hole
//  3 bore_d    the frame's bore
//  4 head_d    5 head_t   6 barb_d   7 barb_h   8 slot_w0   9 slot_w1
// 10 relief_d  the frame is opened out to this below the retention face
// slot_w0 == slot_w1 by default: the slot is PARALLEL, not tapered.  A taper
// is the textbook way to even out bending stress, but it thins the finger
// exactly where a circular segment is already thinnest, and the tip is the
// station the printability gate judges.  A parallel 1.2 mm slot in a 3.0 mm
// shaft leaves 0.90 mm of finger everywhere -- 2.25 extrusion widths.
function pin_joint(grip = 5.6, board = 1.6, hole_d = 3.2, bore_d = 3.4,
                   head_d = 6, head_t = 1.2, barb_d = 4.0, barb_h = 0.8,
                   slot_w0 = 1.2, slot_w1 = 1.2, relief_d = 5.0) =
    assert(board > 0 && board < grip, "pin_joint: need 0 < board < grip")
    assert(hole_d < bore_d, "pin_joint: the frame bore must clear the board hole")
    assert(slot_w0 > 0 && slot_w0 <= slot_w1, "pin_joint: need 0 < slot_w0 <= slot_w1")
    assert(slot_w1 < hole_d - 0.2, "pin_joint: the slot is wider than the shaft")
    assert((barb_d - bore_d)/2 >= 0.25,
           str("pin_joint: retention ledge is only ", (barb_d - bore_d)/2,
               " mm -- under 0.25 the barb rides back out of the bore"))
    assert(relief_d >= barb_d + 0.5,
           str("pin_joint: relief ", relief_d, " does not clear a ", barb_d,
               " barb -- it cannot spring out"))
    [grip, board, hole_d, bore_d, head_d, head_t, barb_d, barb_h,
     slot_w0, slot_w1, relief_d];

// Print head-down: the head gives a wide first layer instead of balancing on the
// tip, and the only overhang is the barb's retention ledge.  Slice it WITHOUT
// support -- support would pack the split, which is both unreachable and the
// part that has to spring.
//
// NOTE ON THE LIMIT: printed head-down, this finger bends across its layer
// interfaces.  snap_strain_max is a handbook design strain for MOULDED stock;
// layer-normal loading is a different and weaker failure mode that it does not
// cover.  Treat a passing number as necessary, not sufficient, until a coupon
// in the same orientation has been cycled.
module push_pin(j = pin_joint()) {
    grip = j[0]; hole_d = j[2]; head_d = j[4]; head_t = j[5];
    barb_d = j[6]; barb_h = j[7]; slot_w0 = j[8]; slot_w1 = j[9];
    shaft_d = hole_d - 0.2;
    y       = (barb_d - hole_d) / 2;          // deflection to pass the hole
    c       = seg_c_out(shaft_d, slot_w0);    // circular segment, NOT t/2
    // Free length: root where the slot starts -- the TOP face of the head --
    // to the barb, where the load acts.  Two ends, two traps, both hit here
    // once already:
    //   * the barb's own height is NOT free length.  Counting it understates
    //     the strain.
    //   * neither is the head.  Its 1.2 mm can only be added to L by running
    //     the slot down through it, and a slot through the head severs the pin
    //     into two loose halves -- it does not lengthen a cantilever, it
    //     deletes the part.  Rendering one and counting bodies says 2.
    L       = grip;
    // No taper credit: 0.86 is a width-tapered RECTANGLE and this is a segment
    // whose thickness and shape both change along the slot.
    eps_    = 3 * y * c / (L * L);
    // PRINTABILITY, checked at the THINNEST station.  A diametral slot leaves
    // each finger a circular SEGMENT: its thickness peaks at the centreline and
    // falls to zero at both edges, so the nominal figure flatters it badly.  If
    // the slot is tapered, the tip is thinner still -- check there.
    // This gate exists because the first printed pin passed manifoldness, passed
    // the overhang audit, and looked solid in the slicer's Prepare view, then
    // sliced to a single extrusion per layer and printed as a stack of loose
    // rings.  Nothing in the geometry was wrong; it simply could not be made.
    t_tip   = (shaft_d - max(slot_w0, slot_w1)) / 2;
    assert(t_tip >= min_rib,
           str("push pin finger is ", t_tip, " mm at its thinnest = ",
               t_tip / profile_nozzle, " extrusion widths, under the ",
               min_rib, " mm floor. It will slice to single unbonded lines. ",
               "Narrow the slot (this RAISES strain -- check both gates), or ",
               "lengthen the flexure, which lowers strain as 1/L^2."));
    assert(max(slot_w0, slot_w1) >= 2 * y,
           str("the slot is ", max(slot_w0, slot_w1), " mm but the two fingers ",
               "must close by ", 2*y, " mm to enter the hole -- they collide ",
               "before the barb passes."));
    assert(eps_ <= strain_limit(),
           str("push pin over the strain budget: ", eps_*100, " % > ",
               strain_limit()*100, " %. Run the slot further (L is squared), ",
               "widen it, or shrink the barb."));
    difference() {
        union() {
            cylinder(h = head_t, d = head_d);
            translate([0, 0, head_t - eps]) cylinder(h = grip + eps, d = shaft_d);
            translate([0, 0, head_t + grip])
                cylinder(h = barb_h, d1 = barb_d, d2 = shaft_d - 2*y);
        }
        // The split starts AT the top face of the head and no lower.  The head
        // is what holds the two fingers together; cut it and there is no pin.
        hull() {
            translate([-head_d, -slot_w0/2, head_t]) cube([2*head_d, slot_w0, eps]);
            translate([-head_d, -slot_w1/2, head_t + L + barb_h]) cube([2*head_d, slot_w1, eps]);
        }
    }
}

// The receiving bore, as a cut, from the SAME joint vector as the pin.  `depth`
// is the frame under the seat; anything past grip - board is relieved so the
// barb can spring out and the retention face lands at a fixed depth whatever
// the boss height.
module pin_bore(depth, j = pin_joint()) {
    grip = j[0]; board = j[1]; bore_d = j[3]; relief_d = j[10];
    keep = grip - board;
    assert(depth >= keep,
           str("not enough frame under the seat: ", depth, " < ", keep));
    translate([0, 0, -depth - eps]) cylinder(h = depth + 2*eps, d = bore_d);
    if (depth > keep)
        translate([0, 0, -depth - eps]) cylinder(h = depth - keep + eps, d = relief_d);
}

// --- Text emboss/deboss helper ---
// Use with difference() to deboss or union() to emboss
module text_label(txt="Label", size=8, depth=1, font="Liberation Sans:style=Bold",
                  halign="center", valign="center") {
    linear_extrude(height=depth)
        text(txt, size=size, font=font, halign=halign, valign=valign);
}

// --- Ventilation grille ---
module vent_grille(area_w=30, area_h=15, slot_w=2, slot_gap=2, depth=2) {
    n_slots = floor(area_h / (slot_w + slot_gap));
    for (i = [0:n_slots-1])
        translate([0, i * (slot_w + slot_gap), 0])
            cube([area_w, slot_w, depth + 2*eps]);
}

// --- PCB standoff array ---
module pcb_standoffs(positions, height=5, outer_d=6, hole_d=2.5) {
    for (pos = positions)
        translate(pos)
            difference() {
                cylinder(d=outer_d, h=height, $fn=32);
                translate([0, 0, -eps])
                    cylinder(d=hole_d, h=height + 2*eps, $fn=32);
            }
}

// --- Profile with rounded corners (2D) ---
// Use with linear_extrude() — preferred over hull() of cylinders
module rounded_rect_2d(size, r=2) {
    offset(r=r)
        square([size.x - 2*r, size.y - 2*r], center=true);
}

// --- Lid lip (for box closures) ---
module lid_lip(outer_size, wall=2, lip_h=2, lip_w=1.2, tol=0.25) {
    difference() {
        rounded_box([outer_size.x, outer_size.y, lip_h], r=2);
        translate([lip_w + tol, lip_w + tol, -eps])
            rounded_box([
                outer_size.x - 2*(lip_w + tol),
                outer_size.y - 2*(lip_w + tol),
                lip_h + 2*eps
            ], r=max(2 - lip_w, 0.5));
    }
}
