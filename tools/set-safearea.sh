#!/usr/bin/env bash
# Tell the phone which part of the cluster canvas is actually visible.
#
# The canvas is 1010x376, but on a Virtual Cockpit the dials cover the outer
# thirds, so UI drawn at the edges is hidden. The SafeArea rectangle keeps the
# navigation app's own elements (next-turn arrow, lane guidance, cards) inside
# the part you can see. The full canvas is still streamed -- only the layout
# the phone chooses changes.
#
# Calibrated on the AID 10" cluster (canvas 1010x376):
#
#   tools/set-safearea.sh 245 28 520 320
#
# Wider loses the manoeuvre card under the right dial -- it is drawn at the edge of
# the rectangle, so 700 hides it and 600 only just fits. 520 also survives the cluster
# views that show more data. The file lives on /tsd/var, so it survives a reboot.
#
# The phone lays the cluster out differently depending on what it is doing: it centres its
# content in the rectangle when idle, and pushes it to the right while guiding. One
# rectangle therefore cannot serve both, so a second one can be given for guiding and the
# two are declared as separate view areas, switched as the mode changes.
#
#   tools/set-safearea.sh <x> <y> <w> <h>       the idle rectangle
#   tools/set-safearea.sh nav <x> <y> <w> <h>   the guiding one
#   tools/set-safearea.sh nav off               drop it, back to one rectangle for both
#   tools/set-safearea.sh show
#   tools/set-safearea.sh reset                 back to the full canvas
#
# Measured on the AID 10": guiding wants 0 28 700 320 (the zone 155 px left of centre, so
# the phone's right-hand bias lands in the middle), idle wants 155 28 700 320 (the zone
# centred, because the phone centres within it).
#
# The phone reads this when the session starts, so reconnect it afterwards.
set -e; . "$(dirname "$0")/_common.sh"; need_link
CFG=/tsd/var/cpvc/mibr-carplay111-safearea.conf
NAV=/tsd/var/cpvc/mibr-carplay111-safearea-nav.conf
W=1010; H=376
TARGET=$CFG; WHICH=idle

case "${1:-show}" in
show)
    u "echo 'idle:'; cat $CFG 2>/dev/null || echo '  (none -- full canvas ${W}x${H})'
       echo 'guiding:'; cat $NAV 2>/dev/null || echo '  (none -- the idle one is used for both)'"
    exit 0 ;;
reset)
    u "rm -f $CFG $NAV && echo 'SafeArea reset to the full canvas'"
    echo "Reconnect the phone to apply."
    exit 0 ;;
nav)
    shift
    if [ "${1:-}" = "off" ]; then
        u "rm -f $NAV && echo 'guiding rectangle removed -- one view area again'"
        echo "Reconnect the phone to apply."
        exit 0
    fi
    TARGET=$NAV; WHICH=guiding ;;
esac

[ $# -eq 4 ] || { echo "usage: $0 <x> <y> <w> <h> | show | reset"; exit 1; }
X=$1; Y=$2; SW=$3; SH=$4

# The unit falls back to the full canvas on a bad rectangle, which looks like
# "nothing happened". Fail here instead, where the reason is visible.
[ "$X" -ge 0 ] && [ "$Y" -ge 0 ] && [ "$SW" -ge 1 ] && [ "$SH" -ge 1 ] \
    && [ $((X+SW)) -le $W ] && [ $((Y+SH)) -le $H ] \
    || { echo "Rectangle outside the ${W}x${H} canvas."; exit 1; }

# The unit's sh has no printf, so build the file with plain echo.
u "echo x=$X > $TARGET; echo y=$Y >> $TARGET; echo w=$SW >> $TARGET; echo h=$SH >> $TARGET; echo \"$WHICH:\"; cat $TARGET"
echo
echo "Reconnect the phone (unplug/replug or toggle CarPlay) to apply."
