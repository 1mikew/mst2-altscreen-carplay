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


def faults(r, prev_fail, burst):
    """Faults are what went wrong. Markers are what else happened at the same second and
    say where the cause came from, so they are reported but never counted as faults."""
    bad, marks = [], []
    state = r.get("state", 0)
    cap = r.get("cap", -1)
    if state != 1:
        bad.append(f"context-down(state={state})")
    if cap != 1:
        bad.append(f"not-captured(cap={cap})")
    if state == 1 and r.get("dcomp", 0) <= 0:
        bad.append("composition-stalled")
    if state == 1 and r.get("dsent", 0) <= 0:
        bad.append("not-feeding")
    if state == 1 and "daus" in r and r["daus"] <= 0:
        bad.append("phone-stopped-sending")
    if r.get("fail", 0) > prev_fail:
        bad.append(f"push-failed(+{r['fail'] - prev_fail})")
    if r.get("didrs", 0) > 0:
        marks.append(f"keyframe(+{r['didrs']})")
    if r.get("drsy", 0) > 0:
        marks.append(f"we-asked-resync(+{r['drsy']})")
    if burst and r.get("daus", 0) > burst:
        marks.append(f"frame-burst({r['daus']})")
    if r.get("ddrop", 0) > 0:
        marks.append(f"frames-dropped(+{r['ddrop']})")
    return bad, marks


def verdict(reasons, marks):
    """Name the stage that broke, then where the cause looks like it came from."""
    if "not-captured" in reasons:
        what = "DisplayManager stopped capturing -- nothing reached the cluster"
    elif "composition-stalled" in reasons:
        what = "dpy-6 stopped being recomposed"
    elif "phone-stopped-sending" in reasons:
        what = "the phone stopped sending"
    elif "not-feeding" in reasons or "push-failed" in reasons:
        what = "we stopped feeding"
    elif "context-down" in reasons:
        what = "our context was down"
    else:
        what = "nothing faulted"
    # Order matters: a keyframe we asked for ourselves is not the phone redrawing the
    # scene, and on a turns edge we do ask for one -- so our own request is checked first
    # or every manoeuvre would be blamed on the phone.
    if "we-asked-resync" in marks:
        where = ("right after WE asked for a keyframe -- ours, not the phone's"
                 if "keyframe" in marks else
                 "right after we asked for a resync, so our side moved first")
    # Dropped frames come first among the phone-side markers: that we could not take the
    # burst says more than that it arrived, and it is the half we can do something about.
    elif "frames-dropped" in marks:
        extra = []
        if "keyframe" in marks:
            extra.append("a keyframe")
        if "frame-burst" in marks:
            extra.append("a burst of frames")
        with_what = " and ".join(extra) if extra else "frames still arriving"
        where = (f"while we were throwing frames away, with {with_what} -- the phone "
                 "redrew the scene and our queue could not take it")
    elif "keyframe" in marks and "frame-burst" in marks:
        where = "with an unprompted keyframe and a burst of frames -- the phone redrew the scene"
    elif "keyframe" in marks:
        where = "with an unprompted keyframe -- the phone redrew the scene"
    elif "frame-burst" in marks:
        where = "with a burst of frames from the phone"
    else:
        where = "with the phone sending evenly, so the cause is on this side"
    return f"{what}, {where}"


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

    # A burst is judged against this drive, not a fixed number: the normal rate is about
    # 30 access units a second but the phone is free to send fewer.
    rates = sorted(r["daus"] for r in rows if r.get("daus", 0) > 0)
    burst = rates[len(rates) // 2] * 3 if rates else 0

    prev_fail = rows[0].get("fail", 0)
    bad = []
    marks_at = {}
    gaps = []
    prev_t = None
    for r in rows:
        why, marks = faults(r, prev_fail, burst)
        if marks:
            marks_at[r["t"]] = marks
        why = why + marks
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
                  f"state={r.get('state',0)} daus={r.get('daus',0):<4} "
                  f"didrs={r.get('didrs',0)} ddrop={r.get('ddrop',0)}{mark}")

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
        by_t = {r["t"]: r for r in rows}
        for a, b in eps:
            reasons, marks = set(), set()
            for t in range(a, b + 1):
                r = by_t.get(t)
                if not r:
                    continue
                w, m = faults(r, r.get("fail", 0), burst)
                reasons.update(x.split("(")[0] for x in w)
                marks.update(x.split("(")[0] for x in m)
            print(f"  {hhmmss(a)} .. {hhmmss(b)}  ({b - a + 1}s)  {verdict(reasons, marks)}")
    else:
        print("nothing suspicious: composition advanced, capture held, we kept feeding")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
