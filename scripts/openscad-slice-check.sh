#!/usr/bin/env bash
# openscad-slice-check.sh — assert a sliced G-code matches the physical setup
#
#   openscad-slice-check.sh <file.gcode> --plate "<plate name>" [--filament PLA]
#
# WHY THIS EXISTS
#
# Slicer presets carry a build-plate assumption, and it is silent. The stock
# Bambu "0.20mm Standard @BBL P1P" preset is a Cool Plate profile: it emits
# M140 S35 for PLA. Print that onto textured PEI and nothing adheres — and the
# failure looks exactly like a dirty plate, so you clean the plate, reprint, and
# lose another hour. A whole print was lost to precisely this.
#
# The plate is the one thing most printers cannot detect (no RFID in the sheet),
# so it must be DECLARED and then checked against what the slicer actually did.
#
# WHAT IT REFUSES TO DO
#
# Every path that cannot evaluate its input exits non-zero. A missing field, an
# unreadable file, an unknown plate name — all are FAILURES, never "probably
# fine". Absence of evidence must not encode absence of the problem.

set -euo pipefail

gcode=""; plate=""; want_filament=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --plate)    plate="${2:-}";    shift 2 ;;
        --filament) want_filament="${2:-}"; shift 2 ;;
        -h|--help)  sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          gcode="$1";        shift ;;
    esac
done

fail() { echo "SLICE-CHECK FAIL: $*" >&2; exit 1; }

[[ -n "$gcode" ]] || fail "no G-code file given"
[[ -f "$gcode" ]] || fail "no such file: $gcode"
[[ -s "$gcode" ]] || fail "empty file: $gcode — the slice produced nothing"
[[ -n "$plate" ]] || fail "--plate is required; the plate cannot be auto-detected"

# Pull a '; key = value' header field. Empty result means ABSENT, which is a
# failure: we cannot verify a setting the slicer did not record.
# CRLF must be stripped here. A trailing \r survives into the value and then
# 'Textured PEI Plate\r' != 'Textured PEI Plate' — producing a comparison that
# fails while printing two identical-looking strings.
field() {
    local v
    v=$(grep -aoE "^; $1 = .*" "$gcode" | head -1 | sed 's/^; [^=]*= *//' | tr -d '\r' || true)
    printf '%s' "$v"
}

bed_type=$(field curr_bed_type)
bed_temp=$(field first_layer_bed_temperature)
filament=$(field filament_type)

[[ -n "$bed_type" ]] || fail "curr_bed_type absent from $gcode — cannot verify the plate"
[[ -n "$bed_temp" ]] || fail "first_layer_bed_temperature absent — cannot verify the temperature"

# 1. The slice must have been made for the plate that is physically fitted.
[[ "$bed_type" == "$plate" ]] || fail \
    "sliced for '$bed_type' but the fitted plate is '$plate'. Re-slice with the correct plate."

# 2. The first-layer bed temperature must equal this filament's temperature for
#    that plate. Reading the expected value out of the same G-code keeps the
#    check filament-agnostic: a PETG profile carries its own per-plate numbers.
#    A blanket ">= 55" would abort a legitimate Cool Plate job — the check must
#    be correct in both directions, not just the one that bit us.
case "$plate" in
    "Cool Plate"|"Textured Cool Plate")            key=cool_plate_temp ;;
    "Engineering Plate")                            key=eng_plate_temp ;;
    "Textured PEI Plate")                           key=textured_plate_temp ;;
    "High Temp Plate"|"Smooth PEI Plate")           key=hot_plate_temp ;;
    *) fail "unknown plate '$plate' — add it to the table in $(basename "$0")" ;;
esac

expect=$(field "$key")
[[ -n "$expect" ]] || fail "$key absent from $gcode — cannot verify the temperature"

# Temperatures must be numbers (decimals allowed). A header field is free text;
# without this, 'banana' compares equal to 'banana' and the check passes.
num_re='^[0-9]+(\.[0-9]+)?$'
[[ "$bed_temp" =~ $num_re ]] || fail "first_layer_bed_temperature '$bed_temp' is not a number"
[[ "$expect"   =~ $num_re ]] || fail "$key '$expect' is not a number"

awk -v a="$bed_temp" -v b="$expect" 'BEGIN{exit !(a+0 == b+0)}' || fail \
    "first-layer bed is ${bed_temp}C but $key for this filament is ${expect}C"

# The header fields above are the slicer's INTENT. What actually heats the bed
# is the M140/M190 stream, and custom start-G-code can override the intent
# without touching the comments.
#
# Checking only the FIRST bed command is not enough either: `M140 S55` followed
# by `M190 S35` before the first extrusion prints the first layer at 35C while
# the first match reads 55. So walk the commands CHRONOLOGICALLY and take the
# target in force at the moment the first extrusion happens. Also accept the R
# parameter (M190 R70 is a real target), match complete G-code words so S55.9
# cannot be read as 55, and tolerate CRLF.
effective=$(python3 - "$gcode" <<'PY'
import re, sys
target = None
# M140/M190 as whole words, S or R, signed/decimal value
cmd = re.compile(r'^\s*M1(?:40|90)(?=\s|$)(.*)$')
par = re.compile(r'\b([SR])\s*(-?\d+(?:\.\d+)?)')
# first real extrusion: a move with a positive E
ext = re.compile(r'^\s*G[01](?=\s)(?=.*\bE\s*\+?(\d+(?:\.\d+)?))')
try:
    with open(sys.argv[1], 'r', errors='replace') as f:
        for line in f:
            line = line.rstrip('\r\n')
            m = cmd.match(line)
            if m:
                vals = par.findall(m.group(1))
                if vals:
                    target = float(vals[-1][1])
                continue
            e = ext.match(line)
            if e and float(e.group(1)) > 0:
                break
except OSError:
    sys.exit(1)
print('' if target is None else repr(target))
PY
) || fail "could not parse the G-code body of $gcode"

[[ -n "$effective" ]] || fail \
    "no M140/M190 target is in force when the first extrusion starts — the bed is cold"
awk -v a="$effective" -v b="$expect" 'BEGIN{exit !(a+0 == b+0)}' || fail \
    "header says ${bed_temp}C but the bed target in force at first extrusion is ${effective}C — the G-code body wins"

# 3. Optional: the sliced material must match what is actually loaded. Pass the
#    value read from the printer, not a value typed by a human.
if [[ -n "$want_filament" ]]; then
    [[ -n "$filament" ]] || fail "filament_type absent — cannot verify the material"
    [[ "$filament" == "$want_filament" ]] || fail \
        "sliced for $filament but the printer reports $want_filament loaded"
fi

echo "slice-check OK: plate='$bed_type' bed=${bed_temp}C filament=${filament:-unknown}"
