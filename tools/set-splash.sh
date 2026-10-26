#!/usr/bin/env bash
# Put the splash keyframe on the unit, or take it away again.
#
#   tools/set-splash.sh            upload build/splash.h264 (persistent)
#   tools/set-splash.sh <file>     upload a different one
#   tools/set-splash.sh off        remove it
#   tools/set-splash.sh show
#
# Build one first with tools/make-splash.py. Without the file the sink behaves exactly as
# it did before the splash existed, so this is also the way to switch the feature off.
#
# It takes effect on the next connect or the next idle timeout -- no reboot, no reconnect.
set -e; . "$(dirname "$0")/_common.sh"; need_link
DST=/tsd/var/cpvc/splash.h264

case "${1:-}" in
show) u "ls -l $DST 2>/dev/null || echo 'no splash -- feature off'"; exit 0 ;;
off)  u "rm -f $DST && echo 'splash removed'"; exit 0 ;;
"")   SRC="$R/build/splash.h264" ;;
*)    SRC="$1" ;;
esac

[ -f "$SRC" ] || { echo "$SRC not found -- run tools/make-splash.py first"; exit 1; }

# A splash without parameter sets would leave the decoder with nothing to start from, and
# the failure would look like a dead cockpit rather than a bad file.
python3 - "$SRC" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
kinds, i = set(), 0
while True:
    j = d.find(b"\x00\x00\x01", i)
    if j < 0: break
    kinds.add(d[j+3] & 0x1f); i = j + 3
missing = [n for k, n in ((7, "SPS"), (8, "PPS"), (5, "IDR")) if k not in kinds]
if missing:
    sys.exit("not a usable splash: no " + ", ".join(missing))
PY

up "$SRC" --to /tmp
u "mv -f /tmp/$(basename "$SRC") $DST && ls -l $DST"
echo
echo "Active on the next connect, or after the idle timeout when the phone goes away."
