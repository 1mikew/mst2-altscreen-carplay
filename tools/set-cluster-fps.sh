#!/usr/bin/env bash
# Put a patched ChangeDataRateSequence into the HMI override jar, or take it out again.
#
#   tools/set-cluster-fps.sh <patched.class>   add it, raising the cluster frame rate
#   tools/set-cluster-fps.sh off               remove it, back to the stock 10
#   tools/set-cluster-fps.sh show              what the jar currently carries
#
# Build the class with tools/make-fps-patch.py from your own unit's MIBHMI.jxe.
#
# The jar is edited here, not on the unit: it is downloaded, changed with zipfile, and
# written back whole, so what lands there is something you can inspect first. A reboot is
# needed for the HMI to load it.
#
# Two things about the system partition, both learned the hard way:
#   - it only accepts writes after `mount -u -o rw`, and only to files that already exist
#   - that remount does NOT survive a reboot, so it is redone here every time
set -e; . "$(dirname "$0")/_common.sh"; need_link
JAR=/tsd/hmi/HMI/jar/NavActiveIgnore.jar
STOCK=/tsd/var/cpvc/NavActiveIgnore.stock.jar
ENTRY=de/vw/mib/asl/internal/mostkombi/streamsink/usecases/ChangeDataRateSequence.class
W="$R/build/jar"; mkdir -p "$W"

"$R/tools/unit_get.py" "$JAR" "$W/current.jar" >/dev/null

case "${1:-show}" in
show)
    python3 - "$W/current.jar" "$ENTRY" <<'PY'
import sys, zipfile
jar, entry = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(jar) as z:
    names = z.namelist()
    print("classes in the jar:")
    for n in sorted(n for n in names if n.endswith(".class")):
        print("  %s%s" % (n, "   <- frame rate" if n == entry else ""))
    if entry not in names:
        print("\nno frame-rate patch present: the cluster runs at the stock 10")
PY
    exit 0 ;;
off)
    python3 - "$W/current.jar" "$W/new.jar" "$ENTRY" <<'PY'
import sys, zipfile
src, dst, entry = sys.argv[1], sys.argv[2], sys.argv[3]
with zipfile.ZipFile(src) as z:
    if entry not in z.namelist():
        sys.exit("not there anyway — nothing to remove")
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as o:
        for i in z.infolist():
            if i.filename != entry:
                o.writestr(i, z.read(i.filename))
print("removed %s" % entry)
PY
    ;;
*)
    [ -f "$1" ] || { echo "$1 not found"; exit 1; }
    python3 - "$W/current.jar" "$W/new.jar" "$ENTRY" "$1" <<'PY'
import sys, zipfile
src, dst, entry, cls = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
data = open(cls, "rb").read()
if data[:4] != b"\xca\xfe\xba\xbe":
    sys.exit("%s is not a class file" % cls)
with zipfile.ZipFile(src) as z:
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as o:
        for i in z.infolist():
            if i.filename != entry:
                o.writestr(i, z.read(i.filename))
        o.writestr(entry, data)
print("added %s (%d B)" % (entry, len(data)))
PY
    ;;
esac

# Keep a stock copy on the writable partition before touching the system one.
u "[ -f $STOCK ] || cp $JAR $STOCK; ls -l $STOCK" | tail -1

up "$W/new.jar" --to /tmp
u "mount -u -o rw /dev/hd0t177 /
cp /tmp/new.jar $JAR && echo COPY-OK || echo COPY-FAILED
rm -f /tmp/new.jar
ls -l $JAR" | tail -3

"$R/tools/unit_get.py" "$JAR" "$W/readback.jar" >/dev/null
if cmp -s "$W/readback.jar" "$W/new.jar"; then
    echo "verified: the jar on the unit matches what was built"
else
    echo "VERIFY FAILED — the jar on the unit differs. Restore with:"
    echo "  tools/unit.py \"mount -u -o rw /dev/hd0t177 /; cp $STOCK $JAR\""
    exit 1
fi
echo
echo "Reboot the unit for the HMI to pick it up."
