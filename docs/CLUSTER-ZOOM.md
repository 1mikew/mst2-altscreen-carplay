# Steering-wheel zoom for the CarPlay map

The wheel still zooms the stock map. Making it zoom a third-party CarPlay map needs two
halves: notice the request, and act on it. The first half is solved; the second is not.

This matters more with the map-only surface as the target: a map with no manoeuvre card is
a map you want to scale yourself.

## Where the zoom request arrives

Not at the key panel. On MQB the cluster decides what the wheel means while it shows the
map, and sends the result to the head unit over **BAP NavSD `MapScale`** (function id 45),
which hands it to the built-in navigation:

```java
// de.vw.mib.bap.mqbab2.navsd.functions.MapScale
VALUE_ZOOM_IN = 1;               VALUE_ZOOM_OUT = -1;
VALUE_CONTINUOUS_ZOOM_IN = 127;  VALUE_CONTINUOUS_ZOOM_OUT = -128;
ZOOM_TYPE_STEP = 1;  ZOOM_TYPE_CONTINUOUS = 2;  ZOOM_TYPE_CONTINUOUS_STOP = 5;

navigationService.setMapScaleSteps(steps, autoZoom);   // steps in {-128,-1,0,1,127}
```

That is better than a key event: the intent is already decoded, and a short press is
already distinguished from a held button. Nothing has to be reconstructed from timing.

So the hook is a shadow of `MapScale` that keeps the stock call and additionally reports
the request when CarPlay owns the cluster.

## Getting it to the phone — the command exists

Zoom is **not** an input device. It is a command on the session we already talk to:

```
AirPlayReceiverSessionSendCommand
  type   = changeMapZoomLevel
  params = { uuid: <cluster display UUID>, zoomDirection: 0 | 1 }
```

**`zoomDirection` is 0 for in and 1 for out** — not a signed step, which was the first
guess here. Upstream documents the exact shape, traced to the open source of
`yuedizhibo/MHI2Q-CarPlay-AltScreen`; see
[docs/research/keypanel](https://github.com/harman-f/mhi2_altscreen_carplay/tree/main/docs/research/keypanel).

It sits in the same vocabulary as `forceKeyFrame`, `requestUI` and `showUI`, two of which
this project already sends. So the declaration side is likely irrelevant — nothing has to
advertise an input device for a command to be accepted.

One detent is one command. Upstream's sender paces single steps rather than sending a
magnitude, caps how many may be outstanding, and retargets on a reversal — and notes that
a successful submit is **not** an acknowledgement that the phone zoomed. There is no ACK to
wait for.

That maps onto what BAP gives us: `steps` of ±1 is one command, and the continuous
±127/−128 means repeat until the stop arrives.

Established by studying GPL-3.0 binaries, as the licence allows — see
[../CREDITS.md](../CREDITS.md). What that gives is Apple's protocol vocabulary; the
implementation here is its own.

## The old assumption, kept for the record

The alt screen is declared with **no input device at all**. `libaltscreen111_gen2.c`
clones the stock display and then:

```c
remove_key(alt,"primaryInputDevice");
```

which is why `/info` reports `input=none`. Until that changes, the phone has no reason to
accept anything. What to send after that is open, and is the real work: the stock value is
logged at startup (`stock display capability baseline`) and is the obvious starting point.

## Shape of the implementation

Split, so the Java side stays trivial and reversible:

| half | where | job |
|---|---|---|
| detect | HMI shadow class | see the request, send a short command over loopback UDP |
| act | our library, inside the SAL process | receive it, drive CarPlay |

The split is **[omonob](https://github.com/omonob/MHI2-Carplay-Maps)'s design** (GPL-3.0),
which this follows: their Java side emits plain ASCII strings — `zoom-in`, `zoom-out` — to
`127.0.0.1` and knows nothing about CarPlay. On MHI2 their detection half hooks the key
panel and reconstructs press length, which MST2 does not need.


## Context guard

Upstream's warning is worth repeating because it is easy to get wrong: a negotiated
source-111 is **not** the same as the cluster actually showing the map. Sending zoom while
the driver is looking at something else is at best wasted and at worst confusing, so the
command should be gated on the cluster really being on our picture — which is the same
`capture buffer` check the sink already makes.
