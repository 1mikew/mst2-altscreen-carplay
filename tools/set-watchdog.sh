#!/usr/bin/env bash
# The two thresholds the cockpit watchdog recovers on, in seconds.
#
#   tools/set-watchdog.sh stall <s>       composition stalled while we keep pushing
#   tools/set-watchdog.sh nocapture <s>   DisplayManager has stopped capturing
#   tools/set-watchdog.sh show
#   tools/set-watchdog.sh reset           back to the built-in 4 s and 60 s
#
# Both are read from the file on every check, so a change takes effect at once -- no
# reboot, no reconnect. Accepted range is 1 to 3600; anything outside it is ignored by the
# library, which falls back to the built-in value.
#
# Recovery on a stall happens in two steps: a keyframe is requested first and our window
# is left alone, and only if that does not help after another <s> is the context torn down.
# A teardown is what makes the stock map visible again, so raising "stall" high enough that
# it can never fire is the way to tell our own teardown apart from anything else that
# removes our window:
#
#   tools/set-watchdog.sh stall 600
#
# Dropouts that continue after that are not ours.
set -e; . "$(dirname "$0")/_common.sh"; need_link
D=/tsd/var/cpvc
STALL=$D/stall-seconds
NOCAP=$D/nocapture-seconds

case "${1:-show}" in
show)
    u "echo \"stall:     \$(cat $STALL 2>/dev/null || echo '4 (built in)') s\"
       echo \"nocapture: \$(cat $NOCAP 2>/dev/null || echo '60 (built in)') s\""
    exit 0 ;;
reset)
    u "rm -f $STALL $NOCAP && echo 'back to the built-in 4 s and 60 s'"
    exit 0 ;;
stall)     T=$STALL; WHAT=stall ;;
nocapture) T=$NOCAP; WHAT=nocapture ;;
*) echo "usage: $0 stall <s> | nocapture <s> | show | reset"; exit 1 ;;
esac

S="${2:-}"
[ -n "$S" ] && [ "$S" -ge 1 ] 2>/dev/null && [ "$S" -le 3600 ] \
    || { echo "seconds must be 1 to 3600"; exit 1; }

u "echo $S > $T; echo \"$WHAT: \$(cat $T) s\""
echo "In effect immediately."
