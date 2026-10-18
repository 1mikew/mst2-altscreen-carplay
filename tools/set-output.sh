#!/usr/bin/env bash
# Change the cockpit output URL at runtime, without rebooting the unit. The library
# re-reads its configuration periodically; on a change it tears the context down and
# rebuilds it on the next keyframe.
#
#   tools/set-output.sh 'screen:/?index=1&overlay=0&dstx=0&dsty=0&dstw=1023&dsth=384&zorder=500'
set -e; . "$(dirname "$0")/_common.sh"; need_link
OUT="${1:?output URL required}"; W="${2:-1024}"; H="${3:-384}"
{ printf '%s\n' "$OUT"
  printf '1c 1 144a\n'
  printf 'mdevpush:/dev/name/local/mdev111?fourcc=AVC1&video.frame_rate=30&video.depth=16&video.width=%s&video.height=%s&video.duration=0\n' "$W" "$H"
  printf 'tmpl\n'; } > /tmp/_a.url
up /tmp/_a.url --to /tmp
u "mv -f /tmp/_a.url /tmp/cpvc_111.url; echo SET"
echo "== $OUT"
echo "Note: /tmp wins over the persistent copy, and is cleared on reboot."
