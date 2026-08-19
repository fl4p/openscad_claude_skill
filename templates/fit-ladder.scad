// ============================================
// fit-ladder.scad — size a pin to a hole that ALREADY EXISTS
// ============================================
//
// Render:  openscad -o ladder.stl -D 'socket_d=4.95' templates/fit-ladder.scad
// Print:   same filament and profile as the part it has to mate with. Minutes.
//
// NOT the same job as calibration-comb.scad. That one varies the HOLE against a
// fixed pin, to characterise the printer once. This one varies the PIN against a
// fixed hole, because the hole is on a part that is already printed and cannot
// be changed. Reach for it whenever you are fitting to an existing object --
// your own earlier print, a bought enclosure, a bearing seat.
//
// HOW TO USE
//
//   1. Measure the existing hole. If you have the STL that was printed, read the
//      nominal straight out of it -- exact, no caliper needed:
//        scripts/openscad-stl-bore.py part.stl --at <x>,<y>
//      Otherwise caliper it, and remember a printed hole reads UNDER nominal.
//   2. Write down the two endpoints you KNOW (see below) and set the rungs
//      inside them. Set engage_len to how deep the pin goes.
//   3. Print. Push each pin into the real hole, in the real orientation.
//   4. The winner is firm to seat and separable with deliberate force. Read its
//      embossed index and put diameters[index - label0] into your design.
//
// WHY THE RUNGS ARE ABSOLUTE DIAMETERS
//
// Because the socket's nominal diameter does not predict the fit. The bore
// prints undersize and the pin prints oversize, and the two errors ADD: a pin
// 0.05 mm UNDER a Ø4.95 nominal bore would not enter it at all. A ladder
// expressed as "nominal +/- x" therefore sits wherever those two unknown errors
// put it, which in one measured case was entirely inside the too-tight half --
// four rungs, one print, and a single bit of information returned.
//
// Anchor on what you have MEASURED instead, and make the ladder straddle it:
// one rung you expect to fail loose, one you expect to fail tight.

$fn = 64;
eps = 0.01;

// --- The fixed side: measured, not chosen --------------------------------
socket_d   = 5.00;   // MEASURED nominal bore of the existing part. Used for the
                     // asserts and for sanity, NOT to derive the rungs.
engage_len = 5.00;   // how far the pin enters it
seat_d     = 7.00;   // shoulder that bottoms on the existing part's face.
                     // Keep it inside whatever clearance surrounds the hole:
                     // a shoulder that fouls a wall never reaches the bore.
seat_h     = 4.50;   // shoulder height (stands in for the parent part)

// --- The measured bracket -------------------------------------------------
// Fill these in from parts you have actually handled. They are asserted below,
// so a ladder that does not straddle the answer refuses to render.
known_loose = 4.60;  // largest pin observed LOOSE in this hole
known_tight = 4.90;  // smallest pin observed NOT TO ENTER  (use socket_d + 1
                     // if you have not hit a tight one yet)

// --- The variable: ABSOLUTE pin diameters ---------------------------------
diameters  = [4.65, 4.72, 4.79, 4.86];

// First label. Continue the numbering across ladders -- both sets end up in the
// same drawer, and two pins stamped "1" is a measurement misattributed.
label0     = 1;

// --- Handle, so a small pin can be pushed by hand -------------------------
// It extends in ONE direction only. A round base looks tidier and is useless:
// hole centres usually sit close to a wall, and anything wider than the seat
// cannot reach the bore at all.
tab_w      = 7;
tab_l      = 20;
tab_t      = 1.6;
pitch      = 16;

lead       = 0.6;    // 45 deg lead-in. A press fit without one starts crooked
                     // and splits the receiving boss.
label_size = 3.4;
label_h    = 0.6;

module fit_pin(pin_d, label) {
    linear_extrude(tab_t) translate([-tab_w / 2, 0]) square([tab_w, tab_l]);

    cylinder(d = seat_d, h = seat_h);

    translate([0, 0, seat_h]) {
        cylinder(d = pin_d, h = engage_len - lead);
        translate([0, 0, engage_len - lead])
            cylinder(d1 = pin_d, d2 = pin_d - 2 * lead, h = lead);
    }

    // An index, not the value: 0.05 apart is illegible at this size, and the
    // mapping back to diameters[] lives in the render log below.
    translate([0, tab_l - 5.5, tab_t - eps])
        linear_extrude(label_h)
            text(label, size = label_size, halign = "center",
                 valign = "baseline", font = "Liberation Sans:style=Bold");
}

assert(seat_d > socket_d,
       "seat_d must exceed socket_d or the pin has no shoulder to bottom on");
assert(min(diameters) - 2 * lead > 0, "lead-in larger than the smallest pin");

// The bracketing rule, enforced rather than merely documented. A ladder whose
// rungs all sit on one side of the answer costs a full print and returns one
// bit; that has happened, so it is a render-time refusal and not a comment.
assert(known_loose < known_tight,
       "known_loose must be smaller than known_tight -- check the endpoints");
assert(min(diameters) > known_loose && min(diameters) < known_tight,
       "the smallest rung is outside the measured bracket: it is already known to be loose or already known not to fit");
assert(max(diameters) < known_tight,
       "the largest rung is at or above a diameter already measured NOT to enter -- that rung cannot teach anything");

for (i = [0 : len(diameters) - 1]) {
    translate([i * pitch, 0, 0]) fit_pin(diameters[i], str(i + label0));
    echo(str("pin ", i + label0, ": diameter ", diameters[i], " mm"));
}
echo(str("bracket: ", known_loose, " loose .. ", known_tight, " will not enter"));
