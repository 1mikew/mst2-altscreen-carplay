# Findings

## The 10 fps ceiling is a constant, not a negotiation

`DisplayManager` logs `update rate set to 10`, which reads like something the cluster asked
for. It is not. Decompiling `MIBHMI.jxe` shows the cluster sends a *mode*, and the head unit
picks the number:

```java
// de.vw.mib.asl.internal.mostkombi.streamsink.usecases.ChangeDataRateSequence
private void _stepChangeDataRate() {
   switch (this.getStreamSinkDataRate()) {
      case 0: this.getDisplayManagementService().setDataFrameRate(0);  break;
      case 1: this.getDisplayManagementService().setDataFrameRate(1);  break;
      case 2: this.getDisplayManagementService().setDataFrameRate(10);
   }
}
```

Mode 2 is "map visible"; 0 and 1 hide it. So 10 is a literal on the side we can reach, and
`omonob` shadows this same class and reports 40 fps on MHI2.

Untested here: whether the cluster and the MOST link accept more than 10 on MST2. The
constant being reachable does not prove the panel will take it.

## The right-aligned navigation layout is not fixed

With a route running, the phone pushes its content to the right of the canvas; without one
it centres. That looked inherent to CarPlay's cluster view. It is not.

`omonob` documents per-cluster behaviour: **AID 12.3 renders navigation centred, AID 10.5
renders it right**. Same phone, same CarPlay, different result — so the layout depends on
something the head unit declares about the display, not on the app alone.

How that project achieves it is not known here and was not examined. The work below is our
own, from our own measurements.

This project targets the AID 10" (`5E0920790A`), the family where the content is
right-aligned.

**The card's position is settable.** The surface URL takes query parameters, and
`maneuverLayout` accepts `leftAligned`, `rightAligned` and `topAligned`. They are off by
default — the URL is sent bare unless enabled — which is why the card has only ever been
seen where the phone chose to put it. `tools/set-nav-appearance.sh`. On a canvas this wide
and short, `topAligned` is the one worth trying. Untested.

Earlier notes here said the arrangement inside the SafeArea could not be influenced. That
was wrong: the rectangle is not the only lever.

**The intended answer is still to not show the card at all.** CarPlay offers the cluster as three
surfaces — `maps:/car/instrumentcluster`, `.../map` and `.../instructioncard` — and the
map-only one is laid out as if no route were active, so it centres. The route still draws
in the map; only the separate manoeuvre card goes away, and that is already on the radio
display. `tools/set-surface.sh` switches it. Not road-tested yet.

If the card ever has to come back, two routes to centring, both untested:

- **Move the picture.** The output URL takes `dstx`/`dstw`, changeable at runtime with
  `tools/set-output.sh` — no rebuild, no reconnect. Shifting or scaling the decoded frame
  pulls right-aligned content inward and shrinks the oversized manoeuvre icon with it. The
  cost is clipped or unused area at the edges, where the dials sit anyway.
- **Change what is declared.** If the 12.3/10.5 difference comes from the advertised canvas
  or physical size, the fix is to declare different values and let the phone lay out
  centred by itself. Those are `ALTSCREEN111_*` environment variables read once at startup,
  so this needs them made file-tunable and a rebuild., constraints and dead ends

Platform constraints, approaches that failed, and the measurements behind both.

## Constraints that shaped the design

| | |
|---|---|
| **No `/dev/mlb`** | MOST is behind the Jacinto 5. No equivalent device, hence decoding on the head unit. |
| **SAL has no clone window** | Apps on the cluster create `DispId[<NAME>]Clone1` on `dpy-6`. CarPlay does not — why the stock map reached the cluster and CarPlay never did. |
| **Overlay planes are not captured** | `SCREEN_USAGE_OVERLAY` never reaches the writeback buffer. `overlay=0` is mandatory. |
| **Composition is damage-driven** | Our video plane does not trigger composition, and capture happens during composition. Covering the stock content stops both — hence the missing pixel ([ARCHITECTURE.md](ARCHITECTURE.md)). |
| **Frame rate is set at FPK setup** | `update rate set to 10`, applied by DisplayManager. 1 and 0 seen in other states, so it is a variable. The stock map gets the same. |

## Dead ends

| attempt | result |
|---|---|
| Adding a second output to SAL's own context | Breaks SAL's `input_attach` (`error 5`); the iPhone then reports an incompatibility. |
| `wingrp=DisplayManagerWindowGroup` on our window | The window inherits the parent's display, lands on `dpy-1` and is `INVISIBLE`. |
| `winid` alone, to make the window a known displayable | No effect on the capture rate (0.4 fps). |
| `usage=3`, to get a composited window instead of a video plane | Window created but `INVISIBLE`. |
| `mmr_output_parameters` with `VideoWriterZOrder` | Returns `rc=0` and **does nothing**. Same trap as `VideoWriterSrcX/Y/W/H` earlier. |
| `mmr_output_detach` + re-attach, to shrink the window at runtime | `output_detach` fails on a playing context. |
| Destroying the context when the phone disconnects | DisplayManager receives `SCREEN_EVENT_CLOSE` for a window it does not manage and **its capture loop wedges** — after that not even the stock map reaches the cluster until the cockpit view is switched. |
| Mirroring the 800×480 main stream onto the cockpit | Geometrically impossible to do well: 5:3 source onto an 8:3 display always sacrifices aspect ratio, content or coverage. This is why Type-111 is required, not optional. |

## Corrections

| claim | reality |
|---|---|
| "The VPU decoder is single-instance" | Two decoders run at once. The `error::5` after three NALs was a missing init sequence — `UNSUPPORTED_MEDIA_TYPE` said so and was misread. |
| "13.4 fps is the ceiling of the unit and of MOST" | That was the redraw rate of the stock map underneath. What reaches the cluster is set at FPK setup instead. |

## Fault signatures

| symptom | likely cause |
|---|---|
| Cockpit frozen on the last frame | DisplayManager is not capturing (`capture buffer = (none)`). Switch the cockpit view. |
| Cockpit black, context `playing` | Decoder initialised with a mismatched `avcC`. |
| `error::5` after exactly 3 NALs | Missing initialisation sequence. |
| Cockpit image stutters at ~2 fps | Our window covers the stock content completely; leave a pixel. |
| iPhone reports an incompatibility | A second output was attached to SAL's own context. |


## Measuring the startup delay and the freezes

Both are timing questions, and the library already logs enough to answer them without
adding anything. In `/tmp/altscreen111.log`:

```
GEN2 D2 ARM ...        a resync was armed, with the reason
GEN2 RESYNC REQUEST ...  a keyframe was asked for
GEN2 RESYNC COMPLETE ... one arrived
```

The gap between REQUEST and COMPLETE is the real cost of waiting for an IDR. One sample
taken after a reboot was about 150 ms, which is far too quick to explain a 10–30 s startup
delay — so something else dominates there. The sink's own log also reports what it is
waiting for:

```
waiting until DisplayManager starts capturing the cockpit (capture buffer = none)
waiting for a keyframe - requesting one
```

Those two lines separate the two candidates: the cluster view not yet being on the map, and
the keyframe itself. Read them before concluding anything.


## The appearance parameters blank the cluster

Tried in the car, 26 Oct 2026. The cluster went black as soon as route guidance started,
and the bare URL brought it straight back.

What went out:

```
url=maps:/car/instrumentcluster?showSpeedLimit=user&showCompass=user&showETA=yes&maneuverLayout=topAligned
```

Nothing failed on our side — no error was logged and the session stayed up. The phone
simply stopped producing frames: the push rate fell from about 27 a second to 2.4, which is
what a black screen looks like from here.

Note that **all four parameters are always sent**. Setting two of them still emits the
other two with a default of `user`. An untested but plausible explanation is that `user` is
not a value the protocol accepts, and one bad parameter invalidates the whole URL — which
would explain losing the picture entirely rather than just losing the manoeuvre bar.

A narrower attempt is possible — explicit `yes`/`no` everywhere and no `maneuverLayout` —
but each try costs a reconnect, and the bare URL already does what matters.

One harmless side effect: Waze rearranged its own layout on the radio display and stayed
that way for the session. Route guidance and position were unaffected.
