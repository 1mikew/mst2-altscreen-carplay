#!/usr/bin/env bash
# Store the current configuration so it survives a reboot.
#
# The library looks for its configuration in this order:
#   1. /tmp/cpvc_111.url            session-local, wins, cleared on reboot (experiments)
#   2. /tsd/var/cpvc/cpvc_111.url   persistent
# Same for the decoder init sequence. /tsd/var is a separate writable partition, so
# the system partition is never remounted read-write for this.
set -e; . "$(dirname "$0")/_common.sh"; need_link
OUT="${1:-screen:/?index=1&overlay=0&dstx=0&dsty=0&dstw=1023&dsth=384&zorder=500}"
W="${2:-1024}"; H="${3:-384}"
[ -f "$R/build/cpvc_111.prologue" ] || {
    python3 "$R/tools/mk-avcc.py" "$R/captures/t111_1024x384.h264" "$R/build/t111.avcc" >/dev/null
    python3 "$R/tools/mk-init.py" "$R/build/t111.avcc" "$R/build/cpvc_111.prologue" "$W" "$H" >/dev/null
}
{ printf '%s\n' "$OUT"
  printf '1c 1 144a\n'
  printf 'mdevpush:/dev/name/local/mdev111?fourcc=AVC1&video.frame_rate=30&video.depth=16&video.width=%s&video.height=%s&video.duration=0\n' "$W" "$H"
  printf 'tmpl\n'; } > /tmp/_p.url
up /tmp/_p.url "$R/build/cpvc_111.prologue" --to /tmp
u "mkdir -p /tsd/var/cpvc
mv -f /tmp/_p.url /tsd/var/cpvc/cpvc_111.url
cp -f /tmp/cpvc_111.prologue /tsd/var/cpvc/cpvc_111.prologue
rm -f /tsd/var/cpvc/off
touch /tsd/var/cpvc/mibr-alt111-keyframe-policy.enabled
ls -l /tsd/var/cpvc/"
echo
echo "Stored. It comes up on its own after a reboot."
echo "The keyframe policy is enabled too -- it shortens the delay when switching"
echo "navigation apps (Type-111 sends an IDR only about once every 29 s)."
