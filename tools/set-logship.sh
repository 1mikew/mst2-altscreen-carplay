#!/usr/bin/env bash
# Detailed logging onto a USB stick in the free port.
#
#   tools/set-logship.sh probe          what removable volumes the unit can see
#   tools/set-logship.sh show           where it is shipping, and what is on the stick
#   tools/set-logship.sh dir <path>     pin a directory instead of letting it scan
#   tools/set-logship.sh auto           back to scanning
#   tools/set-logship.sh off | on
#
# The shipper runs on its own thread, so USB latency never reaches the frame path. It
# writes one telemetry line a second plus both verbose logs every ten seconds, into
# <volume>/mst2-logs/. If no writable volume is there it does nothing and keeps looking;
# pull the stick mid-drive and it notices and resumes when it comes back.
#
# Read the result on a laptop, not over this link: FTP off the unit runs at about 3 kB/s.
# Put the stick in the Mac and:
#
#   tools/read-telemetry.py /Volumes/<stick>/mst2-logs/telemetry.log
set -e; . "$(dirname "$0")/_common.sh"; need_link
CFG=/tsd/var/cpvc/logship-dir
OFF=/tsd/var/cpvc/logship-off

case "${1:-show}" in
probe)
    u "echo '--- /media ---'; ls -l /media/ 2>/dev/null
       echo '--- /fs ---'; ls -l /fs/ 2>/dev/null
       echo '--- which of them are writable ---'
       for d in /media/* /fs/*; do
           [ -d \"\$d\" ] || continue
           if touch \"\$d/.wtest\" 2>/dev/null; then rm -f \"\$d/.wtest\"; echo \"  WRITABLE  \$d\"
           else echo \"  read-only \$d\"; fi
       done"
    echo
    echo "mp000 is the map card and is skipped by name even if it looks writable."
    echo "Pin whichever one is the stick:  $0 dir /media/mpXXX"
    exit 0 ;;
show)
    u "echo \"pinned dir: \$(cat $CFG 2>/dev/null || echo '(none -- scanning)')\"
       echo \"switched:   \$([ -f $OFF ] && echo OFF || echo on)\"
       echo '--- what the shipper found and wrote ---'
       for d in /media/*/mst2-logs /fs/*/mst2-logs; do
           [ -d \"\$d\" ] && ls -l \"\$d\"
       done
       echo '--- what it logged about itself ---'
       grep 'detailed logging to' /tsd/var/cpvc/events.log 2>/dev/null | tail -3 || echo '  (nothing yet)'"
    exit 0 ;;
dir)
    [ -n "${2:-}" ] || { echo "usage: $0 dir /media/mpXXX"; exit 1; }
    u "echo '$2' > $CFG; echo \"pinned: \$(cat $CFG)\""
    echo "Picked up within a second. The shipper creates <path>/mst2-logs itself."
    exit 0 ;;
auto)
    u "rm -f $CFG && echo 'back to scanning for a writable volume'"
    exit 0 ;;
off)
    u "touch $OFF && echo 'detailed logging OFF'"
    exit 0 ;;
on)
    u "rm -f $OFF && echo 'detailed logging on'"
    exit 0 ;;
*)
    echo "usage: $0 probe | show | dir <path> | auto | off | on"; exit 1 ;;
esac
