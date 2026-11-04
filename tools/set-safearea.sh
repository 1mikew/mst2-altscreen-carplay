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
# rectangle therefore cannot serve both. A second one can be given for guiding, and the two
# are declared as separate view areas switched as the mode changes -- but MEASURED 4 Nov,
# that second rectangle does nothing: see the note below before spending time on it.
#
#   tools/set-safearea.sh <x> <y> <w> <h>       the idle rectangle
#   tools/set-safearea.sh nav <x> <y> <w> <h>   the guiding one
#   tools/set-safearea.sh nav off               drop it, back to one rectangle for both
#   tools/set-safearea.sh turns <n>             how many turns count as guiding
#   tools/set-safearea.sh show
#   tools/set-safearea.sh reset                 back to the full canvas
#
# The guiding rectangle is only reached once the phone reports at least <n> turns. The
# library's default is 2, and on the AID 10" a running route reports 1 -- so the switch
# never fired and every state used the idle rectangle. Unlike the rectangles, this is read
# when the library loads, so changing it needs a restart of the unit.
#
# MEASURED 4 Nov on the AID 10", and this retires the idea of two rectangles: the guiding
# rectangle is inert. With the idle one at 155 and the guiding one set to 0, then 155, then
# 310 -- a 310 px span -- the picture while guiding did not move by a pixel, and the switch
# itself was in the log 16 ms after the mode change. Setting the IDLE rectangle to 0 then
# centred the guiding picture, with the guiding rectangle still at 310. So the phone uses
# the first view area's rectangle in both states and accepts updateViewArea without acting
# on it.
#
# One rectangle therefore has to serve both, and the two states want different ones:
#
#   0 28 700 320     guiding centred, idle sits left   <- chosen; guiding is what matters
#   155 28 700 320   idle centred, guiding sits right
#
# Anything between is untested and would centre neither.
#
# The phone reads this when the session starts, so reconnect it afterwards.
set -e; . "$(dirname "$0")/_common.sh"; need_link
CFG=/tsd/var/cpvc/mibr-carplay111-safearea.conf
NAV=/tsd/var/cpvc/mibr-carplay111-safearea-nav.conf
TURNS=/tsd/var/cpvc/mibr-carplay111-turns-active
W=1010; H=376
TARGET=$CFG; WHICH=idle

case "${1:-show}" in
show)
    u "echo 'idle:'; cat $CFG 2>/dev/null || echo '  (none -- full canvas ${W}x${H})'
       echo 'guiding:'; cat $NAV 2>/dev/null || echo '  (none -- the idle one is used for both)'
       echo \"turns counting as guiding: \$(cat $TURNS 2>/dev/null || echo '2 (library default)')\""
    exit 0 ;;
reset)
    u "rm -f $CFG $NAV && echo 'SafeArea reset to the full canvas'"
    echo "Reconnect the phone to apply."
    exit 0 ;;
turns)
    shift
    [ $# -eq 1 ] && [ "$1" -ge 1 ] 2>/dev/null || { echo "usage: $0 turns <n>  (1 or more)"; exit 1; }
    u "echo $1 > $TURNS; echo \"turns counting as guiding: \$(cat $TURNS)\""
    echo "Read when the library loads -- restart the unit to apply."
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
