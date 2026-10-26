#!/usr/bin/env bash
# Appearance options the phone accepts for the cluster surface.
#
# The surface URL takes query parameters, and the phone honours them:
#
#   maneuverLayout   none | left | right | top    where the manoeuvre card sits
#   showETA          yes | no | user
#   showSpeedLimit   yes | no | user
#   showCompass      yes | no | user
#
# "user" leaves the choice to the phone's own setting. The parameters are off by default,
# so the URL stays exactly as stock until enabled here. They do not apply to the
# instructioncard surface, which is always sent bare.
#
#   tools/set-nav-appearance.sh on|off
#   tools/set-nav-appearance.sh maneuver none|left|right|top
#   tools/set-nav-appearance.sh eta|speedlimit|compass yes|no|user
#   tools/set-nav-appearance.sh show
#
# The phone reads this when the session starts, so reconnect it afterwards.
set -e; . "$(dirname "$0")/_common.sh"; need_link
D=/tsd/var/cpvc
EN=$D/mibr-carplay111-nav-query.enabled

case "${1:-show}" in
show)
    u "[ -f $EN ] && echo 'query params: ON' || echo 'query params: OFF (stock URL)'
       for f in maneuverLayout showETA showSpeedLimit showCompass; do
           echo \"  \$f = \$(cat $D/mibr-carplay111-nav.\$f 2>/dev/null || echo default)\"
       done"
    exit 0 ;;
on)       u "touch $EN && echo 'query params ON'" ;;
off)      u "rm -f $EN && echo 'query params OFF -- stock URL'" ;;
maneuver) [ -n "${2:-}" ] || { echo "none|left|right|top"; exit 1; }
          u "echo $2 > $D/mibr-carplay111-nav.maneuverLayout; touch $EN; cat $D/mibr-carplay111-nav.maneuverLayout" ;;
eta)        u "echo ${2:?yes|no|user} > $D/mibr-carplay111-nav.showETA; touch $EN" ;;
speedlimit) u "echo ${2:?yes|no|user} > $D/mibr-carplay111-nav.showSpeedLimit; touch $EN" ;;
compass)    u "echo ${2:?yes|no|user} > $D/mibr-carplay111-nav.showCompass; touch $EN" ;;
*) echo "usage: $0 on|off | maneuver <pos> | eta|speedlimit|compass <val> | show"; exit 1 ;;
esac
echo
echo "Reconnect the phone to apply."
