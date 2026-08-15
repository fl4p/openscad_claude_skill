#!/usr/bin/env bash
# openscad-validate.sh — Validate .scad files with structured error output
# Runs OpenSCAD in strict mode and parses errors into actionable categories
set -euo pipefail

OPENSCAD="${OPENSCAD_BIN:-$(command -v openscad || echo /opt/homebrew/bin/openscad)}"

# Let generated .scad files resolve `use <printable-lib.scad>` from any directory:
# OpenSCAD does NOT expand ~, so a tilde path in a source file silently fails to
# find the library. OPENSCADPATH is the supported way to add a search root.
_SKILL_TEMPLATES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates" && pwd)"
export OPENSCADPATH="${OPENSCADPATH:+$OPENSCADPATH:}$_SKILL_TEMPLATES"

usage() {
    echo "Usage: openscad-validate.sh <file.scad> [-D 'var=val' ...]"
    exit 1
}

[[ $# -lt 1 ]] && usage

scad_file="$1"
shift

if [[ ! -f "$scad_file" ]]; then
    echo "ERROR: File not found: $scad_file" >&2
    exit 1
fi

tmpdir=$(mktemp -d /tmp/openscad-validate-XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT

stl_out="$tmpdir/check.stl"
echo_out="$tmpdir/check.echo"

# Run OpenSCAD in strict mode
output=$("$OPENSCAD" \
    --check-parameters=true \
    --check-parameter-ranges=true \
    --hardwarnings \
    -o "$stl_out" \
    -o "$echo_out" \
    "$@" \
    "$scad_file" 2>&1) || exit_code=$?

exit_code="${exit_code:-0}"

echo "=== Validation Report ==="
echo "File: $scad_file"
echo "Exit code: $exit_code"

# Categorize errors.
#
# The exit status is consulted BEFORE the text patterns, and again in the final
# else. This is not decoration: every branch below keys off something OpenSCAD
# *printed*, so a run that was killed (OOM, timeout, SIGKILL) prints little or
# nothing, matches no pattern, and used to fall through to "Category: OK" —
# reporting success precisely when the check could not be performed at all.
# A run that did not evaluate must never report that it evaluated cleanly.
if [[ "$exit_code" -ge 128 ]]; then
    echo "Category: KILLED"
    echo "OpenSCAD was terminated by signal $((exit_code - 128)) — the file was"
    echo "NOT validated. This is 'unverified', not 'passed'."
    echo "Usual causes: out of memory, or a render too slow for the caller's timeout."
    echo "Retry with a lower \$fn, or render the parts separately."
    [[ -n "$output" ]] && echo "$output" | tail -5
elif echo "$output" | grep -q "Parser error"; then
    echo "Category: SYNTAX_ERROR"
    echo "$output" | grep "ERROR:" | head -5
    echo ""
    # Extract line number
    line=$(echo "$output" | sed -n 's/.*line \([0-9]*\).*/\1/p' | head -1)
    if [[ -n "$line" ]]; then
        echo "Error at line $line. Context:"
        sed -n "$((line > 3 ? line - 3 : 1)),${line}p" "$scad_file" 2>/dev/null | cat -n
    fi
elif echo "$output" | grep -q "Current top level object is empty"; then
    echo "Category: EMPTY_MODEL"
    echo "The model produces no geometry. Check:"
    echo "  - Are modules being called?"
    echo "  - Did a difference() remove everything?"
    echo "  - Are parameter values valid?"
elif echo "$output" | grep -q "NSOpenGLContext\|GLX\|Unable to create"; then
    echo "Category: HEADLESS_PREVIEW"
    echo "PNG preview unavailable (no OpenGL context)."
    echo "STL export should still work."
elif echo "$output" | grep -qi "warning"; then
    echo "Category: WARNING"
    echo "$output" | grep -i "warning" | head -10
elif [[ "$exit_code" -ne 0 ]]; then
    # Non-zero for a reason none of the patterns recognised. Unknown failure is
    # still failure; do not launder it into OK.
    echo "Category: FAILED"
    echo "OpenSCAD exited $exit_code with no recognised error pattern."
    [[ -n "$output" ]] && echo "$output" | tail -10
elif [[ ! -s "$stl_out" ]]; then
    # Exit 0 but nothing written — the run cannot be said to have produced a
    # valid model, so it is unverified rather than fine.
    echo "Category: UNVERIFIED"
    echo "Exited 0 but wrote no geometry to $stl_out."
else
    echo "Category: OK"
fi

# Show echo output if present
if [[ -f "$echo_out" ]] && [[ -s "$echo_out" ]]; then
    echo ""
    echo "=== Echo Output ==="
    cat "$echo_out"
fi

# Show geometry stats if STL was produced
if [[ -f "$stl_out" ]]; then
    stl_size=$(wc -c < "$stl_out" | tr -d ' ')
    if [[ "$stl_size" -gt 0 ]]; then
        echo ""
        echo "=== Geometry ==="
        echo "STL size: $stl_size bytes"
        # Extract stats from render output
        echo "$output" | grep -E "(Facets|Vertices|rendering time|Simple):" | head -10
    fi
fi

exit "$exit_code"
