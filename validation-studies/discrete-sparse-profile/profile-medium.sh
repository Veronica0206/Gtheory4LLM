#!/bin/sh
# Reproduce the recorded profile, including process peak RSS.
#
# Peak RSS cannot be measured from inside the R process being measured, so it
# comes from an external timing utility. Each backend runs in its own fresh
# process: a process that had already run the other backend would report a peak
# covering both.
#
# The unit differs by platform, which is why the raw line is printed rather than
# only a converted number:
#
#   macOS  /usr/bin/time -l   "maximum resident set size"  in BYTES
#   Linux  /usr/bin/time -v   "Maximum resident set size"  in KBYTES
#
# Run from the project root.
SCRIPT=validation-studies/discrete-sparse-profile/profile-medium.R
case "$(uname -s)" in
  Darwin) FLAG="-l"; PATTERN="maximum resident set size"; UNIT="bytes"; DIVISOR=1048576 ;;
  *)      FLAG="-v"; PATTERN="Maximum resident set size"; UNIT="kbytes"; DIVISOR=1024 ;;
esac

for backend in dense sparse; do
  echo "=== $backend ==="
  /usr/bin/time $FLAG Rscript "$SCRIPT" "$backend" timing 2>"/tmp/gt-profile-$backend.err"
  echo "raw peak RSS line ($UNIT):"
  grep "$PATTERN" "/tmp/gt-profile-$backend.err" | sed 's/^/  /'
  grep "$PATTERN" "/tmp/gt-profile-$backend.err" |
    awk -v d="$DIVISOR" '{for (i=1;i<=NF;i++) if ($i+0>0) {printf "  converted: %.0f MB (raw / %d)\n", $i/d, d; break}}'
  Rscript "$SCRIPT" "$backend" work
done
