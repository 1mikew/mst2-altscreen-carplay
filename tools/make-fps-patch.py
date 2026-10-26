#!/usr/bin/env python3
"""Raise the cluster frame rate by patching one constant in the HMI.

    tools/make-fps-patch.py ChangeDataRateSequence.class 30 [out.class]

The cluster asks for a *mode*, not a rate. For mode 2 — map visible — the head unit
substitutes a number of its own:

    de.vw.mib.asl.internal.mostkombi.streamsink.usecases.ChangeDataRateSequence
        case 2: getDisplayManagementService().setDataFrameRate(10);

That 10 is the ceiling, and it is a `bipush`, so any value up to 127 is a single byte.
Nothing else in the class pushes 10, which is what makes this safe to find.

Where the class comes from: your own unit. `/tsd/hmi/ifs/MIBHMI.jxe` converted with
jxe2jar — see docs/HMI-OVERLAY.md for how the HMI is read. No firmware is shipped here.

Whether the cluster accepts more than 10 is unknown. The constant being reachable is not
the same as the panel agreeing, and nobody has tried it on MST2.
"""
import re
import sys

# bipush <n> ; invokeinterface #77, 2  -- the call right after is what identifies it
CALL = bytes.fromhex("b9004d0200")


def main():
    if len(sys.argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    src, fps = sys.argv[1], int(sys.argv[2])
    dst = sys.argv[3] if len(sys.argv) > 3 else src.replace(".class", ".patched.class")

    if not 1 <= fps <= 127:
        print("fps must be 1-127: bipush takes a signed byte", file=sys.stderr)
        return 1

    data = bytearray(open(src, "rb").read())

    hits = [m.start() for m in re.finditer(
        re.escape(b"\x10") + b"." + re.escape(CALL), bytes(data), re.S)]
    if len(hits) != 1:
        print("expected exactly one setDataFrameRate(<const>) site, found %d — "
              "this is not the class this tool knows" % len(hits), file=sys.stderr)
        return 1

    at = hits[0] + 1
    was = data[at]
    if was == fps:
        print("already %d, nothing to do" % fps)
        return 0

    data[at] = fps
    open(dst, "wb").write(bytes(data))
    print("setDataFrameRate(%d) -> setDataFrameRate(%d)" % (was, fps))
    print("one byte at offset %d" % at)
    print("wrote %s" % dst)
    print()
    print("Check it before shipping it:")
    print("  javap -p -c %s | grep -B2 setDataFrameRate" % dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
