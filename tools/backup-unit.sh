#!/usr/bin/env bash
# Take a copy of everything that makes the current state work, before changing it.
#
#   tools/backup-unit.sh [label]
#
# Writes build/backup-<date>-<label>/ with the library actually running on the unit, the
# HMI override jar, and every configuration file. Run it BEFORE deploying anything.
#
# Why it matters: the library on the unit is not necessarily any commit in this tree --
# whatever was last deployed is what runs, and the only copy of it is the one on the car.
# The restore procedure is printed at the end and written next to the files.
set -e; . "$(dirname "$0")/_common.sh"; need_link
LABEL="${1:-}"
DIR="$R/build/backup-$(date +%Y%m%d-%H%M)${LABEL:+-$LABEL}"
mkdir -p "$DIR"

echo "== what is running"
u "ls -l /tsd/hmi/HMI/jar/NavActiveIgnore.jar; ls -l /tsd/var/cpvc/; pidin -p tsd.mibstd2.sal.main mem 2>/dev/null | grep -i altscreen || true" | tail -20 | tee "$DIR/state.txt"

echo
echo "== pulling files"
# The library: find where it was deployed to, then take it.
SO=$(tools/unit.py "ls /tsd/lib/mibr/libaltscreen111.so /tsd/var/cpvc/libaltscreen111.so /tsd/bin/libaltscreen111.so 2>/dev/null | head -1" | tr -d '\r' | grep '^/' | head -1 || true)
if [ -n "$SO" ]; then
    tools/unit_get.py "$SO" "$DIR/libaltscreen111.so" && echo "  library from $SO"
    echo "$SO" > "$DIR/library-path.txt"
else
    echo "  library not found in the usual places -- check state.txt and fetch it by hand"
fi

tools/unit_get.py /tsd/hmi/HMI/jar/NavActiveIgnore.jar "$DIR/NavActiveIgnore.jar" >/dev/null && echo "  HMI override jar"

for f in cpvc_111.url cpvc_111.prologue mibr-carplay111-safearea.conf \
         mibr-carplay111-nav.surface on-disconnect splash.h264 \
         mibr-alt111-keyframe-policy.enabled mibr-carplay111-nav-query.enabled \
         NavActiveIgnore.stock.jar; do
    tools/unit_get.py "/tsd/var/cpvc/$f" "$DIR/$f" >/dev/null 2>&1 && echo "  $f" || true
done

cat > "$DIR/RESTORE.md" <<MD
# Restoring this state

Taken $(date). Commit at the time: $(git -C "$R" rev-parse --short HEAD 2>/dev/null || echo unknown)

## Configuration only (no reboot)

    tools/unit_put.py $DIR/cpvc_111.url --to /tmp
    tools/unit.py "mv -f /tmp/cpvc_111.url /tsd/var/cpvc/"

Same for any other file in here that belongs in /tsd/var/cpvc.

## The library

    tools/unit_put.py $DIR/libaltscreen111.so --to /tmp
    tools/unit.py "mv -f /tmp/libaltscreen111.so \$(cat $DIR/library-path.txt)"

Then restart the CarPlay session, or reboot.

## The HMI override jar

The system partition takes writes only after a remount, and only over files that already
exist. The remount does not survive a reboot.

    tools/unit_put.py $DIR/NavActiveIgnore.jar --to /tmp
    tools/unit.py "mount -u -o rw /dev/hd0t177 /
                   cp /tmp/NavActiveIgnore.jar /tsd/hmi/HMI/jar/NavActiveIgnore.jar"

Reboot afterwards. NavActiveIgnore.stock.jar in here is the untouched original, from
before any patch of ours -- use that one to go back to stock entirely.
MD

echo
echo "saved to $DIR"
ls -l "$DIR"
echo
echo "Restore instructions: $DIR/RESTORE.md"
