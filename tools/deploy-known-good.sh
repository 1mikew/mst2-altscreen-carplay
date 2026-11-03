#!/usr/bin/env bash
# One run at the car: take the logs, back the unit up, install the current library and
# splash, and set the layout that was road-tested on 26 Oct -- the map surface with a
# single rectangle placed so the map is centred while guiding.
#
#   tools/deploy-known-good.sh
#
# The logs go first because they live in /tmp: the library is only loaded when SAL starts,
# so installing it reboots the unit and wipes them.
#
# Only one rectangle is set. The second view area for the idle state is declared by the
# library but did not take effect on the road, and with both present everything used the
# idle one -- which is why the map sat right while guiding. Guiding is the state that
# matters in motion, so that is the one the rectangle is cut for; idle will sit off-centre.
#
# Reconnect the phone afterwards -- the rectangle is read when the session starts.
set -e; . "$(dirname "$0")/_common.sh"; need_link
cd "$R"
STAMP=$(date +%Y%m%d-%H%M)
LOGS="unit-logs/$STAMP"

echo "== logs, before the reboot wipes /tmp"
mkdir -p "$LOGS"
for f in altscreen111.log cpvc_111.log; do
    tools/unit_get.py "/tmp/$f" "$LOGS/$f" || echo "  /tmp/$f is not there"
done
u "grep 'capture buffer' /dev/screen/0/dpy-6; echo; ls -l /tsd/var/cpvc/" | tee "$LOGS/state.txt"

echo; echo "== backup"
tools/backup-unit.sh "pre-$STAMP"

echo; echo "== layout: map surface, one rectangle, cut for guiding"
tools/set-surface.sh map
tools/set-safearea.sh nav off
tools/set-safearea.sh 0 28 700 320

echo; echo "== library (reboots the unit, ~40 s)"
tools/deploy.sh

echo; echo "== splash"
tools/set-splash.sh

echo; echo "== what is in effect now"
tools/set-safearea.sh show
tools/status.sh

echo
echo "Done. Reconnect the phone, then check the cluster:"
echo "  map centred while a route is running  -> the rectangle is right"
echo "  logs saved in $LOGS"
