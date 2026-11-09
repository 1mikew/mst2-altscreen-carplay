#!/usr/bin/env python3
"""Find the dropouts in a telemetry.log taken off the USB stick.

    tools/read-telemetry.py /Volumes/<stick>/mst2-logs/telemetry.log
    tools/read-telemetry.py <file> --all        every sample, not just the suspicious ones
    tools/read-telemetry.py <file> --at 18:42   a window around a time the driver reported

One line a second, written by the library's shipper thread:

    <epoch> comp=<counter> dcomp=<delta> cap=<0|1|-1> sent=<NALs> dsent=<delta> fail=<n> state=<n>

comp   dpy-6 composition counter. Not advancing = the cockpit is not being recomposed.
cap    DisplayManager's capture buffer: 1 set, 0 none, -1 unreadable. 0 means nothing
       reaches the cluster however well the rest of the chain is working.
sent   access units we have pushed. Not advancing = we are not feeding.
state  1 = our context is up, 0 = not set up, -1 = disabled after errors. A dip to 0 and
       back is a teardown and rebuild, which is what a fallback to the built-in map looks
       like from in here.

A dropout the driver saw with none of these faulting is not ours, and that is a result
too -- it moves the search to the cluster and the MOST link.
"""
import sys
import time


def parse(line):
    parts = line.split()
    if not parts:
        return None
    try:
        row = {"t": int(parts[0])}
    except ValueError:
        return None
    for p in parts[1:]:
        k, _, v = p.partition("=")
        try:
            row[k] = int(v)
        except ValueError:
            pass
    return row if "comp" in row else None


def faults(r, prev_fail):
    out = []
    state = r.get("state", 0)
    cap = r.get("cap", -1)
    if state != 1:
        out.append(f"context-down(state={state})")
    if cap != 1:
        out.append(f"not-captured(cap={cap})")
    if state == 1 and r.get("dcomp", 0) <= 0:
        out.append("composition-stalled")
    if state == 1 and r.get("dsent", 0) <= 0:
        out.append("not-feeding")
    if r.get("fail", 0) > prev_fail:
        out.append(f"push-failed(+{r['fail'] - prev_fail})")
    return out


def hhmmss(t):
    return time.strftime("%H:%M:%S", time.localtime(t))


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    path = argv[1]
    show_all = "--all" in argv
    at = None
    if "--at" in argv:
        at = argv[argv.index("--at") + 1]

    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            r = parse(line)
            if r:
                rows.append(r)
    if not rows:
        print(f"no telemetry samples in {path}")
        return 1

    # A window asked for by clock time, so a driver's "about twenty to seven" is findable.
    if at:
        want = [i for i, r in enumerate(rows) if hhmmss(r["t"]).startswith(at)]
        if not want:
            print(f"no sample at {at}; the file covers "
                  f"{hhmmss(rows[0]['t'])} to {hhmmss(rows[-1]['t'])}")
            return 1
        lo = max(0, want[0] - 15)
        hi = min(len(rows), want[-1] + 16)
        rows = rows[lo:hi]
        show_all = True
        print(f"window around {at}\n")

    prev_fail = rows[0].get("fail", 0)
    bad = []
    gaps = []
    prev_t = None
    for r in rows:
        why = faults(r, prev_fail)
        prev_fail = r.get("fail", 0)
        if prev_t is not None and r["t"] - prev_t > 2:
            gaps.append((prev_t, r["t"]))
            why.append(f"gap-of-{r['t'] - prev_t}s")
        prev_t = r["t"]
        if why:
            bad.append(r["t"])
        if why or show_all:
            mark = " -> " + " ".join(why) if why else "   ok"
            print(f"{hhmmss(r['t'])}  comp={r.get('comp',0):<10} "
                  f"dcomp={r.get('dcomp',0):<5} cap={r.get('cap',-1):<3} "
                  f"sent={r.get('sent',0):<8} dsent={r.get('dsent',0):<5} "
                  f"state={r.get('state',0)}{mark}")

    print(f"\n{len(rows)} samples, {hhmmss(rows[0]['t'])} to {hhmmss(rows[-1]['t'])}")
    if gaps:
        print(f"{len(gaps)} gap(s) in the samples -- the unit was off, or the stick was out:")
        for a, b in gaps[:10]:
            print(f"  {hhmmss(a)} .. {hhmmss(b)}  ({b - a}s)")
    if bad:
        # Group neighbouring suspicious seconds into the episodes a driver would notice.
        eps, start, last = [], bad[0], bad[0]
        for t in bad[1:]:
            if t - last <= 2:
                last = t
            else:
                eps.append((start, last))
                start = last = t
        eps.append((start, last))
        print(f"{len(bad)} suspicious samples in {len(eps)} episode(s):")
        for a, b in eps:
            print(f"  {hhmmss(a)} .. {hhmmss(b)}  ({b - a + 1}s)")
    else:
        print("nothing suspicious: composition advanced, capture held, we kept feeding")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
