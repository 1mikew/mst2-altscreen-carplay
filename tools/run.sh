#!/usr/bin/env bash
# Bring the cockpit output up for a session-local test, print the log and context state.
#
# Prerequisites: current library installed, iPhone connected with a navigation app
# running, and the map enabled on the cockpit -- DisplayManager only captures dpy-6
# while it is actually streaming to the cluster.
set -e; . "$(dirname "$0")/_common.sh"; need_link
W="${1:-1024}"; H="${2:-384}"
"$R/tools/set-output.sh" "screen:/?index=1&overlay=0&dstx=0&dsty=0&dstw=1023&dsth=384&zorder=500" "$W" "$H"
up "$R/build/mst2/alt111-dump" --to /tmp
u "chmod 755 /tmp/alt111-dump; touch /tmp/mibr-alt111-keyframe-only"
echo "== waiting for a keyframe (Type-111 sends one about every 29 s)"
sleep 35
u "grep -E 'RUNNING|init subtype|NALs sent' /tmp/cpvc_111.log | tail -5
echo '--- context state ---'
cat /pps/services/multimedia/renderer/context/cpvc111/state 2>/dev/null | grep -E 'state::|error'"
