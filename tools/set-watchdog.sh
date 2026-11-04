#!/usr/bin/env bash
# The thresholds the cockpit watchdog recovers on, plus the consumer attach interval.
#
#   tools/set-watchdog.sh stall <s>       composition stalled while we keep pushing
#   tools/set-watchdog.sh nocapture <s>   DisplayManager has stopped capturing
#   tools/set-watchdog.sh attach <ms>     what a failed consumer attach costs, in MILLISECONDS
#   tools/set-watchdog.sh show
#   tools/set-watchdog.sh reset           back to the built-in 4 s, 60 s and 2000 ms
#
# All of them are read from their file while the library runs, so a change takes effect at
# once -- no reboot, no reconnect. The two in seconds accept 1 to 3600; anything outside
# the accepted range is ignored and the built-in value stands.
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
#
# "attach" is the odd one out: milliseconds, and it governs how long the cluster keeps
# showing the built-in map before our picture takes over. It was 30 s hard-coded, on the
# belief that a shorter retry would keep discarding priming; that measurement did not
# hold, so it is 2000 ms now. Raise it only if the push rate sticks at 0/s, which is the
# failure the old 30 s was guarding against.
set -e; . "$(dirname "$0")/_common.sh"; need_link
D=/tsd/var/cpvc
STALL=$D/stall-seconds
NOCAP=$D/nocapture-seconds
ATTACH=$D/mibr-alt111-attach-retry-ms

case "${1:-show}" in
show)
    u "echo \"stall:     \$(cat $STALL 2>/dev/null || echo '4 (built in)') s\"
       echo \"nocapture: \$(cat $NOCAP 2>/dev/null || echo '60 (built in)') s\"
       echo \"attach:    \$(cat $ATTACH 2>/dev/null || echo '2000 (built in)') ms\""
    exit 0 ;;
reset)
    u "rm -f $STALL $NOCAP $ATTACH && echo 'back to the built-in 4 s, 60 s and 2000 ms'"
    exit 0 ;;
attach)
    MS="${2:-}"
    [ -n "$MS" ] && [ "$MS" -ge 100 ] 2>/dev/null && [ "$MS" -le 120000 ] \
        || { echo "milliseconds must be 100 to 120000"; exit 1; }
    u "echo $MS > $ATTACH; echo \"attach: \$(cat $ATTACH) ms\""
    echo "Picked up within a second, while unattached."
    exit 0 ;;
stall)     T=$STALL; WHAT=stall ;;
nocapture) T=$NOCAP; WHAT=nocapture ;;
*) echo "usage: $0 stall <s> | nocapture <s> | attach <ms> | show | reset"; exit 1 ;;
esac

S="${2:-}"
[ -n "$S" ] && [ "$S" -ge 1 ] 2>/dev/null && [ "$S" -le 3600 ] \
    || { echo "seconds must be 1 to 3600"; exit 1; }

u "echo $S > $T; echo \"$WHAT: \$(cat $T) s\""
echo "In effect immediately."
