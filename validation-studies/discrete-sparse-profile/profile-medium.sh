#!/bin/sh
# Reproduce the recorded profile, including process peak RSS.
#
# Fails closed. This file is the command that reproduces the evidence, so a
# failing Rscript or timing utility must stop it rather than let a later
# success make the run look complete.
#
# Peak RSS cannot be measured from inside the R process being measured, so it
# comes from an external timing utility. Each backend runs in its own fresh
# process: a process that had already run the other backend would report a peak
# covering both.
#
# The reported unit differs by platform, which is why the raw line is printed
# rather than only a converted number:
#
#   macOS  /usr/bin/time -l   "maximum resident set size"  in BYTES
#   Linux  /usr/bin/time -v   "Maximum resident set size"  in KBYTES
#
# Any other platform is refused rather than assumed to follow the GNU contract.
#
# Run from the project root.
set -eu

SCRIPT=validation-studies/discrete-sparse-profile/profile-medium.R
case "$(uname -s)" in
  Darwin)
    FLAG="-l"; PATTERN="maximum resident set size"; UNIT="bytes"; DIVISOR=1048576 ;;
  Linux)
    FLAG="-v"; PATTERN="Maximum resident set size"; UNIT="kbytes"; DIVISOR=1024 ;;
  *)
    echo "Unsupported platform for peak-RSS measurement: $(uname -s)." >&2
    echo "Run the R script directly for the figures that need no external measurement." >&2
    exit 2 ;;
esac

for backend in dense sparse; do
  echo "=== $backend ==="
  ERRFILE="/tmp/gt-profile-$backend.err"
  /usr/bin/time "$FLAG" Rscript "$SCRIPT" "$backend" timing 2>"$ERRFILE"

  # set -e gives no pipefail in POSIX sh, so a grep that finds nothing would
  # still leave a downstream sed or awk exiting zero and the wrapper would
  # finish without ever reproducing the headline figure. Capture and check the
  # line itself instead of piping through it.
  RSS_LINE=$(grep "$PATTERN" "$ERRFILE") || {
    echo "Peak-RSS line not found for $backend in $ERRFILE." >&2
    exit 3
  }
  [ -n "$RSS_LINE" ] || { echo "Empty peak-RSS line for $backend." >&2; exit 3; }
  echo "raw peak RSS line ($UNIT):"
  printf '%s\n' "$RSS_LINE" | sed 's/^/  /'

  CONVERTED=$(printf '%s\n' "$RSS_LINE" | awk -v d="$DIVISOR" '{
    for (i = 1; i <= NF; i++) if ($i + 0 > 0) { printf "%.0f", $i / d; exit } }')
  [ -n "$CONVERTED" ] || {
    echo "No positive numeric field in the peak-RSS line for $backend." >&2
    exit 3
  }
  echo "  converted: $CONVERTED MB (raw / $DIVISOR)"
  Rscript "$SCRIPT" "$backend" work
done
