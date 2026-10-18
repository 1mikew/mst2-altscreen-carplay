#!/usr/bin/env bash
# Build the MST2 artifacts inside the public QNX 6.5 ARMv7 toolchain image
# (mhi2-qnx65-armv7-public:4.9, QNX 6.5 armle-v7, GCC 4.9.4).
#
#   libaltscreen111.so  the hook, LD_PRELOADed into SAL
#   alt111-dump         captures the Type-111 stream for offline analysis
set -euo pipefail
cd "$(dirname "$0")"

# The linker needs two libraries from the head unit. They are vendor firmware and are not
# redistributed with this project -- fetch them from your own unit.
for f in src/linkstubs/libmmrndclient.so.1 src/linkstubs/libstrm.so.1; do
    [ -f "$f" ] || { echo "missing $f -- run: tools/pull-linkstubs.sh"; exit 1; }
done
docker run --rm --platform=linux/amd64 -v "$PWD:/w" -w /w mhi2-qnx65-armv7-public:4.9 bash -c '
set -e
S=src/altscreen111-mst2; O=build/mst2; mkdir -p $O
qcc -shared -fPIC -mfloat-abi=softfp -O2 -g -std=gnu99 -Wall -Wextra -DMST2 -I$S/include \
    $S/libaltscreen111_gen2.c $S/src/alt111_profile.c $S/src/alt111_control.c $S/src/alt111_video.c $S/src/alt111_resync.c $S/src/alt111_trace.c $S/src/alt111_vc111.c \
    -Wl,-soname,libaltscreen111.so -Lsrc/linkstubs -Wl,-rpath-link,src/linkstubs -l:libmmrndclient.so.1 -l:libstrm.so.1 -lsocket -o $O/libaltscreen111.so 2> $O/warn_hook.txt || { cat $O/warn_hook.txt; exit 1; }
qcc -mfloat-abi=softfp -O2 -g -std=gnu99 -Wall -Wextra src/alt111-dump/alt111_dump.c -lsocket -o $O/alt111-dump 2> $O/warn_dump.txt || { cat $O/warn_dump.txt; exit 1; }
for f in $O/libaltscreen111.so $O/alt111-dump; do
  echo "== $f"; arm-unknown-nto-qnx6.5.0eabi-readelf -h $f | grep -E "Class|Machine|Type|Flags"
  arm-unknown-nto-qnx6.5.0eabi-readelf -d $f | grep -E "NEEDED|SONAME"
done
arm-unknown-nto-qnx6.5.0eabi-readelf -A $O/libaltscreen111.so | grep -E "CPU_arch|FP_arch|VFP_args|ABI_VFP" || true
sha256sum $O/libaltscreen111.so $O/alt111-dump
echo "warnings hook=$(grep -c warning $O/warn_hook.txt) dump=$(grep -c warning $O/warn_dump.txt)"
'
