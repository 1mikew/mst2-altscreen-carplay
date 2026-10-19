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
#   tools/set-safearea.sh <x> <y> <w> <h>   set the rectangle
#   tools/set-safearea.sh show              print the current one
#   tools/set-safearea.sh reset             back to the full canvas
#
# The phone reads this when the session starts, so reconnect it afterwards.
set -e; . "$(dirname "$0")/_common.sh"; need_link
CFG=/tsd/var/cpvc/mibr-carplay111-safearea.conf
W=1010; H=376

case "${1:-show}" in
show)
    u "cat $CFG 2>/dev/null || echo '(no config -- full canvas ${W}x${H})'"
    exit 0 ;;
reset)
    u "rm -f $CFG && echo 'SafeArea reset to the full canvas'"
    echo "Reconnect the phone to apply."
    exit 0 ;;
esac

[ $# -eq 4 ] || { echo "usage: $0 <x> <y> <w> <h> | show | reset"; exit 1; }
X=$1; Y=$2; SW=$3; SH=$4

# The unit falls back to the full canvas on a bad rectangle, which looks like
# "nothing happened". Fail here instead, where the reason is visible.
[ "$X" -ge 0 ] && [ "$Y" -ge 0 ] && [ "$SW" -ge 1 ] && [ "$SH" -ge 1 ] \
    && [ $((X+SW)) -le $W ] && [ $((Y+SH)) -le $H ] \
    || { echo "Rectangle outside the ${W}x${H} canvas."; exit 1; }

# The unit's sh has no printf, so build the file with plain echo.
u "echo x=$X > $CFG; echo y=$Y >> $CFG; echo w=$SW >> $CFG; echo h=$SH >> $CFG; cat $CFG"
echo
echo "Reconnect the phone (unplug/replug or toggle CarPlay) to apply."
