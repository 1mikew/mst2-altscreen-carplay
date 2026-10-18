#!/usr/bin/env bash
# Pull the mm-renderer plugins off the unit for offline analysis (disassembly).
#
# Zero risk: FTP reads only. Nothing is changed, no reboot, no phone needed.
#
# Why these: the exact wire format of the decoder initialisation lives in the consumer
# (mdev_streamer.so) and the decoder (imx6_video_decoder.so). Reading them is how the
# protocol in docs/PROTOCOL-MDEVPUSH.md was established -- including the fact that there
# is no "format" message type at all.
set -e; . "$(dirname "$0")/_common.sh"; need_link
O="$R/unit-logs/plugins"; mkdir -p "$O"
echo "== plugins on the unit"
u "ls -l /lib/dll/mmedia" | tee "$O/ls.txt"
for f in mdev_streamer.so imx6_video_decoder.so screen_writer.so; do
    echo "== $f"
    "$R/tools/unit_get.py" "/lib/dll/mmedia/$f" "$O/$f" || echo "  (not fetched)"
done
for f in /lib/dll/mmr-track-engine.so /usr/lib/libmmedia.so.1 /usr/lib/libmmfilter.so.1; do
    echo "== $f"
    "$R/tools/unit_get.py" "$f" "$O/$(basename "$f")" || echo "  (not fetched)"
done
ls -l "$O"
