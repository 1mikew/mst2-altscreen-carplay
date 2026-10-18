#!/usr/bin/env bash
# Install the hook library and reboot. The library is only loaded when SAL starts,
# so a reboot is required -- there is no hot reload.
#
# This does NOT add the LD_PRELOAD entry to cpu.conf; see docs/INSTALL.md.
set -e; . "$(dirname "$0")/_common.sh"; need_link
echo "== upload"; up "$R/build/mst2/libaltscreen111.so" --to /tmp
echo "== install (remount rw -> copy -> remount ro)"
u --timeout 90 ". /tsd/etc/persistence/esd/scripts/util_mount.sh; mkdir -p /tsd/lib/mibr; cp -f /tmp/libaltscreen111.so /tsd/lib/mibr/libaltscreen111.so && echo INSTALLED; chmod 755 /tsd/lib/mibr/libaltscreen111.so; . /tsd/etc/persistence/esd/scripts/util_mount_ro.sh; ls -l /tsd/lib/mibr/libaltscreen111.so"
echo "== reboot (NEVER slay SAL -- the watchdog takes the whole unit down)"
u --timeout 30 "ksh /tsd/etc/persistence/esd/scripts/util_reboot.sh >/dev/null 2>&1 & echo REBOOT" || true
sleep 28; for i in $(seq 1 30); do nc -z -w 2 "$UNIT_HOST" 23 2>/dev/null && { echo "unit back"; break; }; sleep 5; done
sleep 8; u "pidin -p tsd.mibstd2.sal.main mem | grep altscreen | head -1"
