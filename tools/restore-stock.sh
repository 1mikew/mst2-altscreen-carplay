#!/usr/bin/env bash
# Return the unit to stock behaviour. Everything opt-in lives under /tmp, which is
# RAM on this platform, so a reboot has the same effect for the session-local files.
# The persistent configuration under /tsd/var/cpvc is removed too.
#
# This leaves the hook library and its cpu.conf entry in place -- see docs/INSTALL.md
# for a full uninstall.
set -e; . "$(dirname "$0")/_common.sh"; need_link
u "rm -f /tmp/cpvc_111.url /tmp/cpvc_111.prologue /tmp/cpvc_off /tmp/cpvc_clone.url /tmp/cpvc_hijack.conf
rm -rf /tsd/var/cpvc
echo STOCK"
echo "== Done. Reconnect the iPhone -- a running session keeps its configuration."
