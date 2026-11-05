#!/usr/bin/env bash
# Pull the persistent event log -- the one that survives the car being switched off.
#
#   tools/get-events.sh           fetch it and print the tail
#   tools/get-events.sh clear     start a fresh one (do this before a test drive)
#
# /tmp/altscreen111.log and /tmp/cpvc_111.log are wiped by the reboot that every ignition
# cycle performs, so a drive's verbose log is gone before it can be read. The events log
# lives on /tsd/var and holds only what is worth keeping: every teardown, every watchdog
# decision, the session coming and going, and a heartbeat once a minute.
#
# Reading a drive: find the heartbeat whose counter stops advancing, or the teardown line
# just before the dropout the driver reported. Each of the three paths that remove our
# window names itself:
#
#   "DisplayManager has not captured for Ns"   the cluster dropped its video connection
#   "still stalled Ns after the keyframe"      composition froze while we kept pushing
#   "no frames for N s -> releasing"           the phone stopped sending
#
# A dropout with none of those lines against it was not ours.
set -e; . "$(dirname "$0")/_common.sh"; need_link
E=/tsd/var/cpvc/events.log

if [ "${1:-}" = clear ]; then
    u "rm -f $E $E.1 && echo 'events log cleared'"
    exit 0
fi

STAMP=$(date +%Y%m%d-%H%M)
OUT="$R/unit-logs/events-$STAMP"
mkdir -p "$OUT"
got=0
for f in events.log events.log.1; do
    tools/unit_get.py "/tsd/var/cpvc/$f" "$OUT/$f" >/dev/null 2>&1 && { echo "  $f"; got=1; }
done
[ "$got" = 1 ] || { echo "No events log on the unit yet -- it is written by the build of 5 Nov onwards."; exit 1; }
echo "saved in unit-logs/events-$STAMP"
echo
echo "== teardowns and watchdog decisions =="
grep -E 'not captured|still stalled|releasing the cockpit|capturing again|composition stalled' \
    "$OUT"/events.log* 2>/dev/null | tail -20 || echo "  (none -- nothing removed our window)"
echo
echo "== last heartbeats =="
grep heartbeat "$OUT"/events.log 2>/dev/null | tail -10 || echo "  (none)"
