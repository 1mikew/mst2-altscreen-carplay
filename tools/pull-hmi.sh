#!/usr/bin/env bash
# Pull the HMI override jar and its launcher off the unit, for offline analysis.
#
# Zero risk: FTP reads only. Nothing is changed and no reboot is needed.
#
# Why: the cluster covers the picture with "navigation is running on the phone" as soon as
# CarPlay route guidance starts. The state behind it comes from BAP NavSD InfoStates, which
# is derived from activeNavigation == 2, set by CarPlayModeHandling.handleModeChanges.
# That class already lives in the override jar, so the whole 42 MB MIBHMI.jxe is not needed
# unless the fix has to move into ASLCarplayServicesImpl instead.
set -e; . "$(dirname "$0")/_common.sh"; need_link
O="$R/unit-logs/hmi"; mkdir -p "$O"

echo "== override jar (loaded via -Xbootclasspath/p)"
"$R/tools/unit_get.py" /tsd/hmi/HMI/jar/NavActiveIgnore.jar "$O/NavActiveIgnore.unit.jar"

echo "== launcher, to confirm how it is loaded"
"$R/tools/unit_get.py" /tsd/hmi/runHMI.sh "$O/runHMI.sh" || echo "  (not found; check /tsd/hmi)"

echo
ls -l "$O"
echo
echo "Keep NavActiveIgnore.unit.jar untouched -- it is the rollback copy."
