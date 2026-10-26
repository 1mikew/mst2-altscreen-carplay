#!/usr/bin/env bash
# Choose which CarPlay cluster surface the phone sends.
#
# CarPlay splits the instrument-cluster view into three, and the phone lays each one out
# differently:
#
#   base              map and the manoeuvre card together  (the full view)
#   map               map only, no manoeuvre card
#   instructioncard   manoeuvre card only, no map
#
# On the AID 10" the full view is pushed to the right of the canvas while a route is
# running, which puts the manoeuvre card near the dials. "map" is laid out as if no route
# were active, so it sits centred -- at the cost of no turn arrows on the cluster. The
# radio display still shows them.
#
#   tools/set-surface.sh base|map|instructioncard   persistent, survives reboot
#   tools/set-surface.sh <surface> --try            session only, cleared on reboot
#   tools/set-surface.sh show
#
# The phone reads this when the session starts, so reconnect it afterwards.
set -e; . "$(dirname "$0")/_common.sh"; need_link
PERSIST=/tsd/var/cpvc/mibr-carplay111-nav.surface
VOLATILE=/tmp/mibr-alt111-url-mode

case "${1:-show}" in
show)
    u "echo \"session:    \$(cat $VOLATILE 2>/dev/null || echo -)\"
       echo \"persistent: \$(cat $PERSIST 2>/dev/null || echo '- (base)')\""
    exit 0 ;;
base|map|instructioncard) S="$1" ;;
*)  echo "usage: $0 base|map|instructioncard [--try] | show"; exit 1 ;;
esac

# The volatile file wins over the persistent one, so a forgotten --try would mask every
# later change. Clear it whenever we write the persistent choice.
if [ "${2:-}" = "--try" ]; then
    u "echo $S > $VOLATILE; cat $VOLATILE"
    echo "Session only -- a reboot restores the persistent setting."
else
    u "rm -f $VOLATILE; echo $S > $PERSIST; cat $PERSIST"
fi
echo
echo "Reconnect the phone (unplug/replug or toggle CarPlay) to apply."
