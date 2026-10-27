#!/usr/bin/env bash
# What the cockpit does once the phone stops sending.
#
#   keep      leave the last frame up                      (what it has always done)
#   splash    replace it with our own keyframe             (needs tools/set-splash.sh)
#   release   drop our context, let the built-in map back  (untested — see below)
#
#   tools/set-on-disconnect.sh keep|splash|release
#   tools/set-on-disconnect.sh idle <seconds>
#   tools/set-on-disconnect.sh show
#
# Takes effect at once. No reboot, no reconnect.
#
# The action runs on the session teardown hook, which is the real end of a CarPlay
# session. The idle timer is only the fallback for a disconnect that never reports
# itself -- a yanked cable. It defaults to 30 s, and the reason it is not shorter: the
# frames also stop for a few seconds when you leave the CarPlay window on the radio,
# and at 5 s that looked exactly like a disconnect, so the cluster flipped to the
# built-in map and back on every app switch.
#
# "release" is the interesting one and the one that may not work: while our window covers
# the cockpit the built-in map stops redrawing, and DisplayManager only captures when
# Screen reports a change — so letting go may simply leave the same frozen frame. Switching
# the cockpit view always brings the map back by hand.
set -e; . "$(dirname "$0")/_common.sh"; need_link
P=/tsd/var/cpvc/on-disconnect

IDLE=/tsd/var/cpvc/idle-seconds

case "${1:-show}" in
show)         u "cat $P 2>/dev/null || echo 'keep (default)'
                 echo \"idle fallback: \$(cat $IDLE 2>/dev/null || echo '30 s (default)')\""; exit 0 ;;
idle)
    [ $# -eq 2 ] || { echo "usage: $0 idle <seconds>"; exit 1; }
    [ "$2" -ge 1 ] && [ "$2" -le 600 ] || { echo "seconds must be 1-600"; exit 1; }
    u "echo $2 > $IDLE; cat $IDLE"
    echo
    echo "Read once per library start, so reboot to change it again."
    exit 0 ;;
keep)         u "rm -f $P && echo keep" ;;
splash|release) u "echo $1 > $P; cat $P" ;;
*) echo "usage: $0 keep|splash|release | show"; exit 1 ;;
esac
echo
echo "Applies at the next session teardown, or after the idle fallback."
