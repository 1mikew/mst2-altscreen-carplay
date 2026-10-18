#!/usr/bin/env bash
# Kill switch.
#   tools/disable.sh              disable until the unit reboots
#   tools/disable.sh permanent    disable across reboots
#   tools/disable.sh off          enable again (clears both)
set -e; . "$(dirname "$0")/_common.sh"; need_link
case "${1:-session}" in
  permanent) u "mkdir -p /tsd/var/cpvc; touch /tsd/var/cpvc/off; echo 'DISABLED PERMANENTLY'" ;;
  off)       u "rm -f /tmp/cpvc_off /tsd/var/cpvc/off; echo 'ENABLED'" ;;
  *)         u "touch /tmp/cpvc_off; echo 'DISABLED UNTIL REBOOT'" ;;
esac
echo "(takes effect within seconds; the context is torn down and the window disappears)"
