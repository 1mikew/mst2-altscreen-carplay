#!/usr/bin/env bash
# Overview: kill switch, which configuration is in effect, running contexts,
# whether DisplayManager is capturing, and the cockpit composition rate.
set -e; . "$(dirname "$0")/_common.sh"; need_link
u "echo '== kill switch'
[ -f /tmp/cpvc_off ] && echo '  /tmp/cpvc_off        DISABLED until reboot' || echo '  /tmp/cpvc_off        -'
[ -f /tsd/var/cpvc/off ] && echo '  /tsd/var/cpvc/off    DISABLED permanently' || echo '  /tsd/var/cpvc/off    -'
echo '== configuration (first one found wins)'
[ -f /tmp/cpvc_111.url ] && echo \"  session:    \$(head -1 /tmp/cpvc_111.url)\" || echo '  session:    -'
[ -f /tsd/var/cpvc/cpvc_111.url ] && echo \"  persistent: \$(head -1 /tsd/var/cpvc/cpvc_111.url)\" || echo '  persistent: -'
echo '== mm-renderer contexts'
ls /pps/services/multimedia/renderer/context/
echo '== cockpit capture'
grep 'capture buffer' /dev/screen/0/dpy-6
echo '== last log lines (sink)'
tail -3 /tmp/cpvc_111.log 2>/dev/null || echo '  (no log yet)'
echo '== view areas and guidance (library)'
grep -E 'ViewArea|guidance turns' /tmp/altscreen111.log 2>/dev/null | tail -6 || echo '  (nothing logged)'"
C1=$(u "grep counter /dev/screen/0/dpy-6" 2>/dev/null | grep -oE '[0-9]+$'); sleep 8
C2=$(u "grep counter /dev/screen/0/dpy-6" 2>/dev/null | grep -oE '[0-9]+$')
echo "== cockpit composition: $(echo "scale=1; ($C2-$C1)/8" | bc) fps"
