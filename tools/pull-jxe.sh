#!/usr/bin/env bash
# Pull the full MIBHMI.jxe (~42 MB) off the unit.
#
# It lives in /tsd/hmi/ifs, which is inside the boot image: FTP returns 0 bytes from there,
# so it has to be copied out first. Copy it to /tmp -- that is dev/shmem, i.e. RAM, and
# reads from it are far faster than from eMMC.
#
# Read-only as far as the unit's configuration goes: it only writes a temporary copy into
# RAM and removes it afterwards. /tmp is cleared on reboot anyway.
set -e; . "$(dirname "$0")/_common.sh"; need_link
O="$R/unit-logs/hmi"; mkdir -p "$O"
SRC=/tsd/hmi/ifs/MIBHMI.jxe

echo "== free space in /tmp (RAM)"
u "df -k /tmp | tail -1"

echo "== copying to RAM"
u --timeout 120 "rm -f /tmp/MIBHMI.jxe; cp $SRC /tmp/MIBHMI.jxe && ls -l /tmp/MIBHMI.jxe"

echo "== downloading"
S=$(date +%s)
"$R/tools/unit_get.py" /tmp/MIBHMI.jxe "$O/MIBHMI.jxe"
E=$(date +%s)

u "rm -f /tmp/MIBHMI.jxe; echo 'temporary copy removed'"

SZ=$(stat -f%z "$O/MIBHMI.jxe" 2>/dev/null || echo 0)
D=$((E-S)); [ "$D" -le 0 ] && D=1
echo
echo "got $((SZ/1024)) kB in $D s  =  $((SZ/1024/D)) kB/s"
[ "$SZ" -lt 40000000 ] && echo "WARNING: smaller than expected (~42 MB) -- the transfer was cut short"
