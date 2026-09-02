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
// A rectangular finger whose WIDTH tapers to a quarter at the tip carries ~1.16x
// the deflection for the same strain; pass taper=true.  Note WIDTH: the standard
// thickness-taper factor is a different and much larger number (~1.6), so naming
// the wrong one here silently moves the gate.  Do not claim 0.86 for a section
// whose thickness or shape changes along the length.
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
// 11 root_fill how much of the shaft above the head stays SOLID before the slot
//              starts.  It is a stiffness knob and it is the strong one: it
//              shortens the free length, which enters strain squared.  Use it
//              when a pin goes in and holds too weakly -- a thicker finger
//              (narrower slot) pushes the same way but only linearly.
// 12 tight_ok  deliberately allow slot < 2*y; see the gate in push_pin
// 13 web_t     thickness of the spring web tying the fingers under the barb;
//              0 = none.  See pin_spring_web for why it is a diagonal.
// slot_w0 == slot_w1 by default: the slot is PARALLEL, not tapered.  A taper is
// the textbook way to even out bending stress and it remains a legitimate
// technique -- what it cannot do is run the finger under the print floor.  The
// 1.6 -> 2.0 slot that failed on 2026-09-02 was rejected for going under the
// floor at its tip, not for being tapered.  Buying a parallel slot instead is
// not free either: it thickens the whole shaft, which RAISES strain (1.582 ->
// 2.023 % on the pin below) and raises insertion force.  Choose deliberately.
//
// NOTE also that snap_strain / the eps_ below are PRISMATIC-beam expressions.
// For slot_w0 < slot_w1 both I(x) and c(x) vary, the peak strain need not sit
// at the root, and evaluating at the root section is a heuristic -- generally
// conservative, but not a derivation.  Treat a tapered result as an estimate.
function pin_joint(grip = 5.6, board = 1.6, hole_d = 3.2, bore_d = 3.4,
                   head_d = 6, head_t = 1.2, barb_d = 4.0, barb_h = 0.8,
                   slot_w0 = 1.2, slot_w1 = 1.2, relief_d = 5.0,
                   root_fill = 0, tight_ok = false, web_t = 0) =
    assert(board > 0 && board < grip, "pin_joint: need 0 < board < grip")
    assert(hole_d < bore_d, "pin_joint: the frame bore must clear the board hole")
    assert(slot_w0 > 0 && slot_w0 <= slot_w1, "pin_joint: need 0 < slot_w0 <= slot_w1")
    assert(slot_w1 < hole_d - 0.2, "pin_joint: the slot is wider than the shaft")
    // POLICY, not geometry.  Radial ledge alone does not decide pull-out --
    // barb face angle, bore edge condition, friction, creep and layer
    // orientation all enter, and none of them are modelled here.  0.25 is a
    // house minimum to stop a ledge being specified at essentially zero; it is
    // uncalibrated, and a design sitting near it has not been shown to work.
    assert((barb_d - bore_d)/2 >= 0.25,
           str("pin_joint: retention ledge is only ", (barb_d - bore_d)/2,
               " mm, under the 0.25 house minimum (uncalibrated policy)"))
    // The relief, not the barb, sets the CEILING on retention.  A barb wider
    // than the relief does not gain ledge -- it simply seats against the relief
    // wall, so the effective ledge saturates at (relief_d - bore_d)/2.  An
    // earlier version of this demanded relief >= barb + 0.5, which was a made-up
    // margin: it capped the barb at 4.5 in a 5.0 relief and threw away 0.25 mm
    // of ledge that the hole was willing to give.
    //
    // What a barb WIDER than the relief does cost is a residual deflection of
    // (barb_d - relief_d)/2 held for the life of the joint, and PLA creeps under
    // sustained strain.  So barb_d == relief_d is the useful maximum: full ledge,
    // no locked-in stress.  Beyond it, the assert says so.
    assert(barb_d <= relief_d,
           str("pin_joint: barb ", barb_d, " exceeds the relief ", relief_d,
               " -- it cannot fully relax and would sit at ",
               (barb_d - relief_d)/2, " mm of permanent deflection, which PLA ",
               "creeps out of. Effective ledge is capped at ",
               (relief_d - bore_d)/2, " mm either way."))
    assert(root_fill >= 0 && root_fill < grip - board,
           str("pin_joint: root_fill ", root_fill, " must leave flexure above ",
               "the board face -- keep it under grip - board = ", grip - board))
    [grip, board, hole_d, bore_d, head_d, head_t, barb_d, barb_h,
     slot_w0, slot_w1, relief_d, root_fill, tight_ok, web_t];

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
// --- Spring web between a split pin's fingers -----------------------------
// A compliant tie across the slot, just under the barb, so the two fingers act
// as a coupled pair instead of two independent cantilevers.  It adds outward
// preload at the barb -- which is the thing a pin that "goes in but is loose"
// is short of -- and it resists the barbs being cammed inward under pull-out.
//
// It MUST be a rib that bends, not one that is compressed.  A straight strut
// across the slot is axially stiff, and the fingers have to close by nearly the
// whole slot width to enter the hole, so a straight tie does not stiffen the
// joint, it prevents assembly.  A DIAGONAL rib rotates and bends as the gap
// closes, which is a spring.
//
// Printed head-down the rib is a bridge over the slot.  Keep it at 45 deg or
// shallower to the bed so no support is needed -- which is also why `rise` is
// tied to the span rather than being free.
module pin_spring_web(slot_w, span_x, z_lo, thick = 0.8, bite = 0.25) {
    a    = slot_w/2 + bite;      // reach INTO each finger so the rib fuses
    rise = 2 * a;                // 45 deg across the gap: bridgeable, no support
    hull() {
        translate([0, -a, z_lo])        cube([span_x, thick, thick], center = true);
        translate([0,  a, z_lo + rise]) cube([span_x, thick, thick], center = true);
    }
}

module push_pin(j = pin_joint()) {
    grip = j[0]; hole_d = j[2]; head_d = j[4]; head_t = j[5];
    barb_d = j[6]; barb_h = j[7]; slot_w0 = j[8]; slot_w1 = j[9];
    root_fill = j[11]; tight_ok = j[12]; web_t = j[13];
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
    // Free length ends at the barb and starts where the material stops being
    // continuous across the shaft -- which is the TOP of the root fill, not the
    // head, once root_fill > 0.  Filling the gap near the head is a stiffness
    // knob and it is the strong one, because L enters squared: 1 mm of fill on
    // a 5.6 mm grip is an 18 % cut in L and a 48 % rise in strain.
    L       = grip - root_fill;
    // No taper credit: 0.86 is a width-tapered RECTANGLE and this is a segment
    // whose thickness and shape both change along the slot.
    eps_    = 3 * y * c / (L * L);
    // PRINTABILITY SCREEN.  Read what this number is and is not.
    //
    // A diametral slot leaves each finger a circular SEGMENT.  At an axial
    // station of radius R with slot half-width a, the depth the slicer sees is
    // q(x) = sqrt(R^2 - x^2) - a, which is MAXIMUM on the centreline and falls
    // to zero at both chord edges.  So t_seg below is the segment's sagitta --
    // its deepest point, not its thinnest.  A pass means "there is a run down
    // the middle that can hold two paths", not "two paths everywhere": at the
    // 1.2 mm default the chord is 2.750 mm wide and only its central 1.077 mm
    // (39 %) is >= min_rib.  Screening heuristic, not a proof.
    //
    // It IS evaluated at the governing axial station.  The flexing length never
    // has an OD below shaft_d (the barb cone runs barb_d -> shaft_d, see below),
    // and the slot is widest at slot_w1, so shaft_d against slot_w1 is the worst
    // pairing on the part.
    //
    // The gate exists because the first printed pin passed manifoldness, passed
    // the overhang audit, and looked solid in the slicer's Prepare view, then
    // sliced to a single extrusion per layer and printed as a stack of loose
    // rings.  Nothing in the geometry was wrong; it simply could not be made.
    // A second revision "fixed" the shaft to 0.90 mm and STILL printed brittle,
    // because the barb cone then necked to shaft_d - 2*y and put a 0.50 mm
    // station back at the tip.  That neck was arbitrary and is gone; a lead-in
    // only has to start under hole_d, which barb_d -> shaft_d already does.
    t_seg   = (shaft_d - max(slot_w0, slot_w1)) / 2;
    assert(t_seg >= min_rib,
           str("push pin finger is ", t_seg, " mm at its deepest = ",
               t_seg / profile_nozzle, " extrusion widths, under the ",
               min_rib, " mm floor. It will slice to single unbonded lines. ",
               "Narrow the slot (this RAISES strain -- check both gates), or ",
               "lengthen the flexure, which lowers strain as 1/L^2."));
    // Finger-collision gate, and know what it is: a RIGID-BODY model.  It asks
    // whether two fingers translating straight at each other would touch before
    // the barb cleared the hole.  Real segments do not only translate -- the
    // shaft ovalises and the barb's chord edges are thin and compliant -- so the
    // model is conservative, and measurably so: a pin at slot 1.3 / barb 4.5
    // (2*y = 1.3, exactly the boundary) entered a real 3.2 mm board hole by hand
    // on 2026-09-02, and rev-2 pins below the boundary entered easily.
    //
    // It is kept as an assert rather than softened to a warning because going
    // under it raises insertion force by an unmodelled amount, and that is worth
    // stating out loud. Pass tight_ok = true to declare the violation deliberate.
    // Minimum GAP, warned not asserted: min_gap is declared, never measured, so
    // a hard gate here would block the very coupon that would calibrate it.
    if (min(slot_w0, slot_w1) < min_gap)
        echo(str("WARNING: slot is ", min(slot_w0, slot_w1), " mm = ",
                 min(slot_w0, slot_w1)/profile_nozzle, " nozzle widths, under the ",
                 min_gap, " mm declared minimum gap. The slicer may fuse it, and a ",
                 "fused slot is a solid pin that cannot flex. Check the sliced ",
                 "preview at a mid-shaft layer before printing."));
    assert(tight_ok || max(slot_w0, slot_w1) >= 2 * y,
           str("the slot is ", max(slot_w0, slot_w1), " mm but the two fingers ",
               "must close by ", 2*y, " mm to enter the hole -- by a rigid-body ",
               "model they collide before the barb passes. That model is known ",
               "conservative; pass tight_ok = true to allow it deliberately and ",
               "measure the insertion force."));
    assert(eps_ <= strain_limit(),
           str("push pin over the strain budget: ", eps_*100, " % > ",
               strain_limit()*100, " %. Run the slot further (L is squared), ",
               "widen it, or shrink the barb."));
    union() {
    difference() {
        union() {
            cylinder(h = head_t, d = head_d);
            translate([0, 0, head_t - eps]) cylinder(h = grip + eps, d = shaft_d);
            // Lead-in cone.  d2 is shaft_d and NOT shaft_d - 2*y: the tip only
            // has to start under hole_d to find the hole, and shaft_d already
            // does (3.0 into 3.2).  Necking it to 2.2 bought nothing and put
            // the part's thinnest, most-stressed section at its free end --
            // 0.50 mm, the same figure that printed as loose rings.
            translate([0, 0, head_t + grip])
                cylinder(h = barb_h, d1 = barb_d, d2 = shaft_d);
        }
        // The split starts at the top face of the head PLUS root_fill, and no
        // lower.  The head is what holds the two fingers together; cut into it
        // and there is no pin.  root_fill leaves that much shaft solid above the
        // head, which is the web the two fingers grow out of.
        hull() {
            translate([-head_d, -slot_w0/2, head_t + root_fill])
                cube([2*head_d, slot_w0, eps]);
            translate([-head_d, -slot_w1/2, head_t + grip + barb_h])
                cube([2*head_d, slot_w1, eps]);
        }
    }
    // The web is added AFTER the slot is cut -- put it inside the difference and
    // the slot deletes the very thing it is there to add.
    if (web_t > 0) {
        rise  = 2 * (max(slot_w0, slot_w1)/2 + 0.25);
        z_lo  = head_t + grip - rise - 0.3;
        // The web is a TIE between two fingers that move apart on insertion, so
        // it carries a relative transverse displacement and it must survive it.
        // Closure scales with distance from the flexure root, so where the web
        // sits decides whether it is a spring or a fuse.
        //   x/L   : how far along the flexure the web sits
        //   shape : cantilever deflection ratio (3*u^2 - u^3)/2 at u = x/L
        //   d     : relative closure the web actually sees = 2*y*shape
        //   L_web : its own developed length, corner to corner
        u     = ((z_lo + rise/2) - (head_t + root_fill)) / L;
        shape = (3*u*u - u*u*u) / 2;
        d     = 2 * y * shape;
        L_web = sqrt(2) * (max(slot_w0, slot_w1)/2 + 0.25) * 2;
        eps_w = 3 * web_t * d / (L_web * L_web);
        // Calibrated against a known-bad: a 0.8 mm web at u = 0.72 on this pin
        // computes to 201 %, and no thickness rescues it -- 0.2 mm, half an
        // extrusion width and unprintable, is still 50 %. Reaching 5 % at a
        // printable 0.8 mm needs a 6.7 mm rib to span a 1.0 mm gap. Near the
        // barb a compliant tie is not a tuning problem, it is unavailable; near
        // the ROOT the same rib sees ~0.02 mm and passes easily, which is what
        // root_fill already does more simply.
        assert(eps_w <= strain_limit(),
               str("spring web at u=", u, " of the flexure carries ", d,
                   " mm of closure across a ", L_web, " mm rib = ", eps_w*100,
                   " % strain, over the ", strain_limit()*100, " % budget. ",
                   "Move it toward the root (closure scales with distance from ",
                   "it) or use root_fill instead -- thinning it does not help, ",
                   "and below 2 extrusion widths it will not print anyway."));
        pin_spring_web(max(slot_w0, slot_w1), 1.2, z_lo, thick = web_t);
    }
    }
}

// --- Press-fit pin -------------------------------------------------------
// The same joint WITHOUT a slot or a barb: a stepped solid pin, small through
// the board and interference-fit into the frame bore.  Retention is friction
// over the full grip instead of a ledge on a spring.
//
// Why this is usually the right answer for a printed pin at small diameters:
// there is no finger, so there is no thin section, no bending across layer
// interfaces, and no strain budget to blow.  PLA's brittleness stops being a
// design variable.  A split snap pin only earns its complexity when the joint
// has to come apart again.  (Proven in service on the zoe display.)
//
// The cost: it is not designed to be removable, and PLA creeps, so a joint held
// only by interference relaxes over months.  Do not use it where a boss will be
// opened and closed.
//
// `press_d` is the diameter of the interference section, measured against the
// frame's bore_d.  It is NOT derivable from the profile -- interference depends
// on bore shrinkage, material and wall stiffness, so print the sweep coupon and
// read the answer off the real frame.
module press_pin(j = pin_joint(), press_d = 3.5, lead = 0.5) {
    grip = j[0]; board = j[1]; hole_d = j[2]; bore_d = j[3];
    head_d = j[4]; head_t = j[5];
    shaft_d = hole_d - 0.2;
    keep    = grip - board;            // length inside the frame bore
    assert(press_d > shaft_d,
           str("press_pin: press section ", press_d, " must exceed the ",
               "through-board shaft ", shaft_d, " or there is no step"));
    assert(press_d - bore_d <= 0.6,
           str("press_pin: ", press_d - bore_d, " mm interference on a ",
               bore_d, " bore will split the boss before it seats"));
    assert(lead < keep, "press_pin: lead-in longer than the pressed length");
    union() {
        cylinder(h = head_t, d = head_d);
        // through the board
        translate([0, 0, head_t - eps]) cylinder(h = board + eps, d = shaft_d);
        // interference section, less the lead-in at the tip
        translate([0, 0, head_t + board])
            cylinder(h = keep - lead, d = press_d);
        // lead-in so it starts into the bore instead of stubbing on the edge
        translate([0, 0, head_t + board + keep - lead])
            cylinder(h = lead, d1 = press_d, d2 = press_d - 2*lead*tan(20));
    }
    // Print head-down like push_pin.  The only overhang is the step from
    // shaft_d up to press_d -- (press_d - shaft_d)/2 per side, a fraction of a
    // millimetre, which bridges without support.
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
