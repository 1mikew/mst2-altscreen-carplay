#!/usr/bin/env bash
# The forced-keyframe policy: on, off, or what it is now.
#
#   tools/set-d2.sh show
#   tools/set-d2.sh off     no forced keyframes at all, until turned back on
#   tools/set-d2.sh on
#
# Why you would turn it off: on every turns edge the library runs
# gen2_d2_schedule(G2_D2_SOURCE_TURNS), so a change in the number of reported turns forces
# an IDR. Slowing from 100 to 45 is typically the approach to a manoeuvre, which is exactly
# when turns changes and exactly when the dropouts were reported -- so the expensive
# keyframe may be ours, arriving at the worst moment. Off for one drive answers it, with no
# build and no reboot.
#
# What you lose while it is off: the watchdog no longer asks for a keyframe when frames go
# stale. The sink still asks on a composition stall, so recovery is reduced, not gone.
#
# Read the drive afterwards with tools/read-telemetry.py: drsy counts our own requests, so
# an episode marked "right after WE asked" is this policy and an episode with an
# unprompted keyframe is the phone redrawing the scene.
set -e; . "$(dirname "$0")/_common.sh"; need_link
S=/tmp/mibr-alt111-keyframe-policy.enabled
P=/tsd/var/cpvc/mibr-alt111-keyframe-policy.enabled

case "${1:-show}" in
show)
    u "[ -f $S ] && echo 'session marker:    present' || echo 'session marker:    -'
       [ -f $P ] && echo 'persistent marker: present' || echo 'persistent marker: -'
       { [ -f $S ] || [ -f $P ]; } && echo 'forced keyframes:  ON' || echo 'forced keyframes:  OFF'
       echo \"our requests so far: \$(grep -c 'RESYNC REQUEST' /tmp/altscreen111.log 2>/dev/null || echo '?')\""
    exit 0 ;;
off)
    u "rm -f $S $P && echo 'forced keyframes OFF (both markers removed)'"
    echo "In effect at once. Survives a reboot, so remember to turn it back on."
    exit 0 ;;
on)
    u "mkdir -p /tsd/var/cpvc; touch $P && echo 'forced keyframes ON (persistent marker set)'"
    echo "In effect at once."
    exit 0 ;;
*)
    echo "usage: $0 show | off | on"; exit 1 ;;
esac
