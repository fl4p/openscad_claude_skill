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
// eps = 3*y*t / (2*L^2) for a straight cantilever, where y is the deflection the
// hook has to make (its overhang), t the finger thickness in bending and L the
// FREE length from the root to the hook.  A finger tapering to half thickness at
// the tip carries ~1.16x the deflection for the same strain; pass taper=true.
//
// The trap this exists to close: L is squared, so a clip that is a little too
// short is not a little too weak, it is broken.  The old default here --
// length=6, thick=1.5, overhang=0.8 -- computes to 5 % strain and snaps off a
// PLA part on first assembly.  L had to be 11 mm for those numbers to work.
function snap_strain(y, t, L, taper = false) = (taper ? 0.86 : 1) * 3 * y * t / (2 * L * L);

// --- Snap-fit tab ---
// Cantilever snap tab extending along Y with a hook at the end.  `length` is the
// free length and it is the parameter that matters: see snap_strain above.
module snap_tab(width=8, length=12, thick=1.5, overhang=0.8) {
    assert(snap_strain(overhang, thick, length) <= snap_strain_max,
           str("snap tab over the strain budget: ",
               snap_strain(overhang, thick, length)*100, " % > ",
               snap_strain_max*100, " %. Lengthen it (L is squared), ",
               "thin it, or reduce the hook."));
    union() {
        // Cantilever arm
        cube([width, length, thick]);
        // Hook at the end (rotated extrusion for clean manifold)
        translate([0, length - eps, 0])
            rotate([90, 0, 90])
                linear_extrude(height=width)
                    polygon([[0, 0], [thick + eps, 0], [thick/2, overhang]]);
    }
}

// --- Push-pin, and the bore that receives it ---
// A separate pin beats a snap post moulded into the frame whenever the mating
// part cannot be lowered straight down -- anything that slides, hinges or drops
// in at an offset.  A fixed post standing in a mounting hole can only be entered
// from directly above; a pin dropped in AFTER the part is seated does not care
// how the part got there.  It also keeps metal out of plated holes.
//
// `grip` is board thickness + the frame material under it, and it is the free
// length of the fingers, so it is what buys the strain budget.  Relieve any
// frame deeper than one chosen grip (pin_bore does it) and ONE pin serves every
// hole in the assembly.
//
// Print head-down: the head gives a wide first layer instead of balancing on the
// tip, and the only overhang is the barb's retention ledge.  Slice it WITHOUT
// support -- support would pack the split, which is both unreachable and the
// part that has to spring.
module push_pin(grip = 5.6, hole_d = 3.2, bore_d = 3.4, head_d = 6, head_t = 1.2,
                barb_d = 4.0, barb_h = 0.8, slot_w0 = 1.2, slot_w1 = 2.0) {
    shaft_d = hole_d - 0.2;
    y       = (barb_d - hole_d) / 2;          // deflection to pass the hole
    t       = (shaft_d - slot_w0) / 2;        // finger thickness at the root
    assert(snap_strain(y, t, grip, true) <= snap_strain_max,
           str("push pin over the strain budget: ",
               snap_strain(y, t, grip, true)*100, " %. Lengthen the grip, ",
               "widen the slot, or shrink the barb."));
    assert(barb_d > bore_d, "barb does not engage the bore -- no retention");
    difference() {
        union() {
            cylinder(h = head_t, d = head_d);
            translate([0, 0, head_t - eps]) cylinder(h = grip + eps, d = shaft_d);
            translate([0, 0, head_t + grip])
                cylinder(h = barb_h, d1 = barb_d, d2 = shaft_d - 2*y);
        }
        translate([0, 0, head_t]) hull() {
            translate([-head_d, -slot_w0/2, 0]) cube([2*head_d, slot_w0, eps]);
            translate([-head_d, -slot_w1/2, grip + barb_h])
                cube([2*head_d, slot_w1, eps]);
        }
    }
}

// The receiving bore, as a cut.  `depth` is the frame under the seat; anything
// past `grip - board` is relieved so the barb can spring out and the retention
// face lands at a fixed depth whatever the boss height.
module pin_bore(depth, board = 1.6, grip = 5.6, bore_d = 3.4, relief_d = 5.0) {
    keep = grip - board;
    assert(depth >= keep, "not enough frame under the seat for the pin to grip");
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
