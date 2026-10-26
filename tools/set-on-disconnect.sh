#!/usr/bin/env bash
# What the cockpit does once the phone stops sending.
#
#   keep      leave the last frame up                      (what it has always done)
#   splash    replace it with our own keyframe             (needs tools/set-splash.sh)
#   release   drop our context, let the built-in map back  (untested — see below)
#
#   tools/set-on-disconnect.sh keep|splash|release
#   tools/set-on-disconnect.sh show
#
# Takes effect on the next idle timeout. No reboot, no reconnect.
#
# "release" is the interesting one and the one that may not work: while our window covers
# the cockpit the built-in map stops redrawing, and DisplayManager only captures when
# Screen reports a change — so letting go may simply leave the same frozen frame. Switching
# the cockpit view always brings the map back by hand.
set -e; . "$(dirname "$0")/_common.sh"; need_link
P=/tsd/var/cpvc/on-disconnect

case "${1:-show}" in
show)         u "cat $P 2>/dev/null || echo 'keep (default)'"; exit 0 ;;
keep)         u "rm -f $P && echo keep" ;;
splash|release) u "echo $1 > $P; cat $P" ;;
*) echo "usage: $0 keep|splash|release | show"; exit 1 ;;
esac
echo
echo "Applies at the next idle timeout."
