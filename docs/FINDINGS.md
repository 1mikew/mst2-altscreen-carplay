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


## Centring: the SafeArea is an offset, not a frame

Solved 26 Oct 2026, and not the way it was being attempted.

With a route running, the phone holds its content against the **right** of the SafeArea,
whatever the rectangle is. Widening the rectangle does not centre anything and does not
push the manoeuvre card out of sight either — going from 700 to 800 wide moved the card by
about a tenth of its own width.

The lever is the rectangle's **position**. Offsetting the zone to the left cancels the
right bias:

```bash
tools/set-surface.sh map             # no manoeuvre card
tools/set-safearea.sh 0 28 700 320   # zone 0-700, centred at 350 against a canvas centre of 505
```

The zone sits 155 px left of centre, the content sits right inside it, and the result lands
centred on the cluster. **Road-tested on 26 Oct 2026 and confirmed** — this is the working
configuration.

This also explains the "perfect centre" seen on 19 Oct at `155 28 700 320` and never
reproduced afterwards: it was a coincidence of offset and width, not a setting anyone had
reasoned out.

### What does not work

| attempt | result |
|---|---|
| Widening the SafeArea to hide the manoeuvre card | Card barely moves; it is not anchored to the zone edge |
| `map` surface alone | Removes the card, but the content stays right |
| Negative `dstx` to shift our own window | QNX will not place the window off-display — black cluster |
| Appearance parameters (`maneuverLayout`, `showETA`) | Cluster blanks as soon as a route starts |

Removing the manoeuvre card needs the `map` surface. Nothing else does it.


## The splash, and why it is a keyframe

The decoder emits nothing until it is given a keyframe, and Type-111 sends one only about
every 29 s. Two things follow from that single fact: the cockpit stays blank for 10–30 s
after connecting, and when the phone goes away the last frame it sent stays on the cluster
for good.

Both are the same problem, so both get the same answer — a keyframe of our own:

```bash
tools/make-splash.py        # one Annex-B IDR with its own SPS/PPS, ~1.3 kB
tools/set-splash.sh         # onto the unit; remove it to disable the feature entirely
```

It runs in its own context, primed from its own parameter sets, because the stream's are
different. The first genuine keyframe tears it down and the real picture takes over.

Shrinking the window to hide it was tried first and does not work — `mmr_output_detach`
is refused on a playing context — and destroying the window wedges DisplayManager. The
splash sidesteps both: the window never changes, only its contents.


## The stall watchdog was checking far too rarely

There is a watchdog for the case the cluster freezes while frames are still being pushed:
it reads the dpy-6 composition counter and, if that stands still, rebuilds the context and
asks for a keyframe.

It was gated on a frame count — once every 256 frames. At the rate the cluster takes, that
is roughly **20 s between checks**, and it wants two checks in a row before acting. So a
freeze had to last the better part of a minute before anything noticed, which means the
mid-drive freezes that recover in a few seconds were never the watchdog's doing. Something
else was fixing those.

Now on a clock: twice a second, so a stall is caught in about one. The rate limit that
stopped it rebuilding repeatedly came down from 30 s to 10, and the separate
"DisplayManager is not capturing" count was re-sized, since checks are now forty times more
frequent.

Untested in the car. The risk to watch for is the opposite failure — reacting to a
composition pause that was not a fault, and rebuilding the context for nothing.


## One rectangle cannot serve both states

The road test showed the offset works while guiding and overshoots when it is not: idle,
the map sits 155 px left. That is the model confirming itself rather than failing. The
phone **centres its content in the SafeArea when idle and pushes it right while guiding**,
so a rectangle that cancels the right-hand bias necessarily over-corrects when there is no
bias to cancel.

CarPlay allows more than one view area, and the hook can switch between them at runtime —
`updateViewArea`, which the control state machine already implements and which had never
been used because only one area was ever declared. So the answer is two rectangles:

```bash
tools/set-safearea.sh     155 28 700 320    # idle: centred, because the phone centres in it
tools/set-safearea.sh nav   0 28 700 320    # guiding: 155 px left, to cancel the bias
```

The switch follows the `turns` field of the CarPlay mode state, which is already logged on
every change. Which value means "guiding" is assumed to be 2, matching the convention the
HMI uses elsewhere; if the log says otherwise, `mibr-carplay111-turns-active` corrects it
without a rebuild.

Untested. With no guiding rectangle configured, one view area is declared and none of this
runs.


## Baseline: how often the picture freezes

A full drive on 27 Oct 2026, on the **old library** — the one whose stall watchdog checks
once every 256 frames — gave **three to five freezes**, each recovering on its own.
Everything else worked.

That is the number to measure the faster watchdog against. What should change is the
length of each freeze, not necessarily how often they happen: the watchdog only shortens
recovery, it does not stop the stall occurring.


## The faster watchdog: no freezes at all

The drive on the evening of 27 Oct 2026, on the library whose watchdog checks twice a
second, had **none**. Not shorter freezes — none observed over the same route that gave
three to five the same morning.

That is one drive, so it is an encouraging number rather than a settled one, and the
mechanism only explains part of it: a check every 256 frames at 10 fps is a check every
25 s, so a stall that cleared in a few seconds used to clear on its own, unnoticed and
unrecorded. Some of what was counted as a freeze may simply now be too short to see.


## Starvation is not a disconnect

With `on-disconnect=release`, leaving the CarPlay window on the radio — into the car
menu, or any other screen — took the map off the cluster and put the built-in navigation
there instead. Going back to the phone's map brought it back after a few seconds.

Nothing disconnected. The frames stop while the radio is showing something else, and the
idle timer was five seconds, so a perfectly normal app switch read as a phone going away.
The few seconds coming back are the keyframe wait: the context has to be rebuilt, and an
IDR is only requested once every ten seconds.

Frame starvation was the wrong signal in the first place. The session teardown hook
already distinguishes the cases we care about — an explicit stream-111 teardown, or the
whole AirPlay session ending — from stock tearing down screen 110 alone, which must not
touch the cluster. The action now runs from there, and the idle timer survives only as
the fallback for a disconnect that never reports itself, at 30 s.


## Why the splash showed nothing

It is gated on DisplayManager actually capturing the cockpit, the same condition that
stops us covering the built-in map before the cluster has a video connection to rebuild
from. While that gate is shut there is no splash, and by the time it opens the real
keyframe has usually arrived too — so the window the splash was written for barely
exists.

The gate is not wrong; taking the cockpit early is what produced a frozen frame from the
previous session. What was wrong is that the skip was silent. It now says so in the log,
which is the measurement needed before changing anything else.

There was a second fault underneath it, and this one is settled: **the splash was the
wrong size.** Type-111 carries 1010x376 — measured from a capture, not assumed — and the
splash was being encoded at 1024x384, the panel's dimensions. The generator's own comment
claimed the two were kept identical, which is how it went unnoticed. The stream is also
full range (`yuvj420p`) where the splash was limited range. Both now match, so if the
splash is pushed and still shows nothing, the cause is somewhere else.


## Can one rectangle centre both states?

Two measurements, both taken at width 700:

- idle, `155 28 700 320` — centred. The phone centres its content in the rectangle.
- guiding, `0 28 700 320` — centred. The phone pushes its content right.

Those two fit two different rules, and at width 700 the two rules predict the same pixel,
which is why one measurement each was never enough to tell them apart:

| rule | guiding content centre | one rectangle for both? |
|---|---|---|
| fixed inset from the right edge, 195 px | `x + w - 195` | yes, at `w = 390`, `x = 310` |
| fixed bias from the rectangle's centre, 155 px | `x + w/2 + 155` | no, never |

At `w = 700` both give 505, the centre of the 1010 canvas. They separate at any other
width, so `310 28 390 320` decides it: idle is centred under either rule, and guiding is
either centred as well (inset rule, and one rectangle is enough) or 155 px right of centre
(bias rule, and the view-area switch has to be made to work).

Untested. Narrowing the rectangle from 700 to 390 is a large change and the phone may
rescale its content rather than only move it, which would show up as a smaller map rather
than a shifted one.


## The freezes did not go away; they changed shape

Moving the watchdog onto a clock, twice a second, left two thresholds expressed as counts
of checks. Both silently changed meaning by the same factor the interval did:

| path | before | after | what it does |
|---|---|---|---|
| `capture buffer = none` | 3 checks ≈ **75 s** | 10 checks = **5 s** | releases the cockpit |
| composition stalled | 2 checks ≈ **50 s** | 2 checks = **1 s** | tears the context down |

So the drive that reported no freezes was not a drive without stalls. The stalls were
being caught within a second or two and answered by removing our window, which shows the
stock map for as long as the rebuild takes. The frozen picture became a flip to the
built-in map — a different symptom of the same fault, and a worse one in the case that
has nothing to do with a fault at all: a parking camera or any other radio view stops the
capture for as long as the driver leaves it up, and five seconds of that was read as a
cluster that had lost its video connection.

Both thresholds are wall-clock now, 60 s for no capture and 4 s for a stall, and
settable from files. The stall recovery also has two stages: ask for a keyframe and leave
the window in place, and only tear the context down if that did not help. The first stage
is invisible to the driver, which is the point.
