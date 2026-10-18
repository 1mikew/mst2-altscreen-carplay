#!/usr/bin/env bash
# Fetch the two mm-renderer client libraries the linker needs, from your own unit.
#
# They are vendor firmware components and are NOT redistributed with this project. The
# build links against them only to resolve symbols; nothing from them is copied into the
# output.
set -e; . "$(dirname "$0")/_common.sh"; need_link
D="$R/src/linkstubs"; mkdir -p "$D"
for f in /usr/lib/libmmrndclient.so.1 /usr/lib/libstrm.so.1; do
    echo "== $f"
    "$R/tools/unit_get.py" "$f" "$D/$(basename "$f")"
done
ls -l "$D"
