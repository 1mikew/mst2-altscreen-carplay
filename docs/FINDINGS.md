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

The decoder emits nothing until it is given a keyframe, and Type-111 does not send them
often -- see "The keyframe merry-go-round" below, where a measured 718 access units arrived
against a single IDR. Two things were blamed on that: the cockpit staying blank for 20-30 s
after connecting, and the last frame staying on the cluster for good once the phone goes
away. The second is real. The first turned out to be something else entirely, and the
splash cannot cover it -- the same section has the measurement.

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


## The view-area switch never fired: the threshold was two turns

The symptom was "the map sits right while guiding and centred when idle", which is what a
single rectangle looks like when it is the idle one. Three things could have caused it: the
second area was never advertised, the guidance change was never noticed, or the phone
ignored `updateViewArea`. The library's log, pulled off the unit before the 3 Nov reboot,
rules out the first two:

```
GEN2 ViewArea[1] guiding safe=700x320@0,28
GEN2 ViewArea[0] full=1010x376 safe=700x320@155,28 views=2
GEN2 guidance turns=0 -> viewArea 0
GEN2 guidance turns=1 -> viewArea 0
```

Both areas were advertised, and the guidance change *was* seen -- `turns` went 0 to 1 when
the route started. It still chose area 0, because the threshold for "guiding" is two turns:

```c
static int g_turns_active = 2;
...
unsigned want = (parsed.turns >= g_turns_active) ? 1u : 0u;
```

On this unit a running route reports one turn, not two, so the comparison never held and
every state used area 0. Nothing was wrong with the declaration or the send path; the
threshold was simply above the value the phone reports.

`mibr-carplay111-turns-active` overrides it, so no rebuild is needed -- but it is read in
the library's constructor, so the unit has to be restarted for a change to take hold.

What this does *not* yet establish is the third hypothesis: whether the phone acts on
`updateViewArea` once it is actually sent. That needs a drive with the threshold at 1.


## Drive of 3 Nov: centring fixed, the dropouts are not

With one rectangle cut for guiding (`0 28 700 320`, surface `map`) and the watchdog on
wall-clock thresholds, 60 s for a stopped capture and 4 s for a stalled composition:

| | observed |
|---|---|
| centring | correct, both while guiding and while idle |
| frame rate | about 10 fps, as before |
| first picture | 20-30 s after connecting, unchanged |
| splash | never appeared |
| mid-drive | drops to the stock map for 1-5 s, sometimes longer, then comes back. More often at speed, outside town |

So raising the thresholds did not cure the dropouts, and the drive before this one, which
reported none, remains the odd one out rather than the new baseline.

**What a dropout to the *stock map* means.** A stalled stream leaves our last frame on the
cluster. For the stock map to become visible our window has to be gone from the dpy-6
composition, which only happens when something removes it: the watchdog's teardown, the
idle action, or the session going away. That narrows the causes to three, and each writes
a distinct line, so one log read separates them:

| line in `/tmp/altscreen111.log` | cause |
|---|---|
| `composition stalled ... requesting a keyframe` then `still stalled ... tearing the context down` | our stall path, 8 s in total |
| `DisplayManager stopped capturing` | the capture path, 60 s |
| `session torn down` / `no frames for 30 s` | the idle action, with `on-disconnect=release` |
| none of the above around the dropout | something outside this library removes or covers our window |

A 1-5 s outage is shorter than any of our own paths needs to fire, which makes the fourth
row the one to beat -- but the stall timer can already have been running before the
picture visibly froze, so it cannot be ruled out from the duration alone.

**The cheap experiment, no rebuild.** `stall-seconds` is read from the file on every check,
so setting it high enough that the teardown can never fire is a live change:
`tools/set-watchdog.sh stall 600`. If the dropouts continue, our watchdog is not removing
the window and the cause is outside it. If they stop and turn into frozen pictures
instead, it was us, and the answer is to stop tearing down on a stall at all -- a frozen
map is worse than a moving one but far better than the stock map coming back.

**The splash and the 20-30 s both point at the same gate.** The splash is held back until
DisplayManager is capturing, and the picture waits for a keyframe. If the capture
connection only comes up at about the time the first natural IDR arrives -- Type-111 sends
one roughly every 29 s -- then both observations are one fact, and the keyframe we request
while waiting is being asked for before the control path can carry it. The log now says
when the splash is held back, which settles it.


## The keyframe merry-go-round

The log from the 3 Nov session, 3251 lines over five minutes, settles three things that
were guesswork until now. All of it is one connected session with the phone sitting still.

### D2 forces a keyframe every second, for the whole drive

```
GEN2 D2 ARM epoch=228 reason=4 sources=0x0 idr_at_arm=229 source_idrs=229 watchdog_ms=1000
GEN2 RESYNC REQUEST epoch=228 ... source_idrs=229
gen2 UI command dispatched type=4 request=232 awaiting completion
gen2 UI completion type=4 request=232 status=0 core_rc=0
GEN2 RESYNC COMPLETE epoch=228 completions=228 idr_at_arm=229 source_idrs=230
GEN2 D2 ARM epoch=229 ...                                   <- 1.1 s later, again
```

241 epochs in five minutes, one about every 1.1 s, unbroken. The watchdog's rule was

```c
now >= g2_d2_last_idr_ms + G2_D2_WATCHDOG_MS   /* 1000 ms since the last keyframe */
```

and the condition it waits for is the *normal* state of this stream. At 1793721303 the
counters read `source_aus=107 source_idrs=1`; twenty seconds later, `source_aus=718
source_idrs=1`. Six hundred frames, no second keyframe. So "no keyframe for one second" is
true from one second after the stream starts and stays true forever, and the watchdog built
to recover from a fault became a metronome: one forced IDR per second, every second, for as
long as the phone is connected.

That is expensive in exactly the way the car showed. An IDR of a moving 1010x376 map is
worth many ordinary frames, and the faster the car goes the more of the picture changes, so
the forced keyframes grow at precisely the moment there is least headroom. It matches the
report that the dropouts come at speed, outside town.

The fix is to watch the right counter. Frames arrive at the source rate, so their absence
is a genuine fault; keyframes arrive almost never, so their absence means nothing. The
watchdog now triggers on `source_aus` going stale, and the interval is tunable from
`mibr-alt111-d2-watchdog-ms` so it can be corrected without a build.

### forceKeyFrame works, and it is fast

Every one of those 241 requests was honoured: `status=0`, and `source_idrs` one higher by
the time the resync completed, about 140 ms after the request. That is the useful half of
the finding. Recovery does not have to be slow or scheduled -- one request fixes a stalled
picture in roughly a seventh of a second, on demand. The merry-go-round was never buying
safety that we cannot have cheaply.

### The 20-30 s to first picture is not a keyframe wait at all

The timeline of the same session:

| time | event |
|---|---|
| 289.5 | `startSession` |
| 298.9 | stream 111 SETUP accepted, receiver ready on 6031 |
| 299.7 | valid video config; frames start arriving |
| 303.9 | `source_aus=107 source_idrs=1` -- the stream is running at ~30 fps |
| 324.2 | `turns=1` -- the route is started on the phone |
| 324.3 | the phone sends `suggestUI` with the cluster URLs |
| 327.6 | `gen2 renderer consumer attach rc=0`, `consumer keyframe intent rc=0` |
| 327.7 | forced IDR arrives, `avcC built from the stream`, picture on the cluster |

Frames and the first keyframe were there within a second of the stream being set up, 28 s
before the picture appeared. Nothing was waiting for an IDR. What we wait for is the
phone's `suggestUI`, and the phone sent it when the route was started -- our consumer
attaches only then, and the picture follows 300 ms later.

So the startup delay is the time between connecting the phone and the navigation app having
something to offer the cluster. `showUI` of our own would not need to wait for the offer,
and there is a marker to try it by hand, no build required:

```bash
tools/unit.py "touch /tmp/mibr-alt111-show-only"
```

`g_auto_show` is 0 in this build with no way to turn it on from a file, deliberately --
upstream could not prove startup `showUI` against the reference. The marker is the way to
find out whether this unit minds.

### Which also explains the splash

The splash is driven from the frame-handling path, and that path does not run until the
consumer attaches. Until then there are no frames to be the "wrong" kind, so nothing ever
asks for a splash. It could not have covered the gap it was written for -- not because the
gate on DisplayManager was shut, but because the code that would open it never ran. The
sink log for the whole session begins at the moment the picture starts, with no splash line
of either kind, which is the proof.

Covering that gap means driving the splash from the session lifecycle instead. Worth doing
only if `showUI` turns out not to shorten the wait.


## Why 30 fps in and 10 on the cluster: two ceilings, not one

The numbers that get quoted -- 30, 13, 10 -- are three different places in the chain, and
only the smallest matters.

| stage | rate | set by |
|---|---|---|
| phone to us, stream 111 | 30 fps (611 access units in 20.3 s) | the phone, we advertise `maxFPS=30` |
| our decoded picture | 30 fps, on a hardware video plane, scanned out without composition | the decoder |
| `dpy-6` composition | 13.4-13.5 fps | **damage from the stock map underneath** |
| DisplayManager to the cluster | **10 fps** | `setDataFrameRate(10)` in the HMI |

Two of those are ceilings we have to beat, and beating one alone changes nothing.

**The 10.** `DisplayQNXScreen [DISPLAYID_CLUSTER] update rate set to 10` comes from the
`bipush 10` in `ChangeDataRateSequence`. Patching it is a one-byte edit of a classfile we
do not have:

- the stock override jar on the unit holds exactly two classes, `CarPlayModeHandling` and
  `RequestHandler` -- which is why the overlay patch was possible: that class was already
  there as plain bytecode;
- `MIBHMI.jxe` contains **no classfiles at all**. A scan of all 42 MB finds zero
  `CAFEBABE` magics and only the class *names* in a string table. It is a fully AOT
  compiled image.

So `make-fps-patch.py` has nothing to chew on, and "tooling ready" was too generous: the
tool is written, the input is missing. Getting it needs `jxe2jar`, or another firmware that
ships `mostkombi` as a jar, or a way to call `setDataFrameRate` at runtime -- which is the
one worth looking for first, because it would need no HMI patch at all. Reconnaissance for
it is read-only: what `/pps/services` exposes around display management, and what the
DisplayManager binary and its start script carry in the way of a rate setting.

**The 13.5.** Our picture is on a video plane that needs no composition, but DisplayManager
captures *during* composition, and composition is driven by damage from the stock content
below. The stock map redraws at about 13.4 fps and that is what we inherit -- the one
deliberately unpainted pixel is what keeps even that alive. So raising the HMI constant to
30 would land on a composition that still only runs at 13.5.

That second ceiling is in our hands, though: the damage does not have to come from the
stock map. A surface of our own, repainted at the rate we are pushing frames, would drive
composition at our rate instead of the map's. Nothing has been built for that yet -- it is
only worth building once something above 10 can actually reach the cluster.

## The startup delay was our own reboot, not the CarPlay path

Measured on 4 Nov, stationary, with the unit on the bench link. After
`tools/deploy.sh` -- which reboots the head unit and nothing else -- the cockpit
stream never starts:

| state after a software reboot | reading |
|---|---|
| `capture buffer` on `dpy-6` | `(none)`, for four and a half minutes |
| DisplayManager periodic timer | present but never armed (`0/0`) |
| frames from the phone | arriving, `source_aus` climbing, 30 fps at the sink |
| a route running | yes, `turns=1` |
| a hand-sent `showUI` | accepted, `status=0`, changed nothing |

The same unit with our library switched off (`tools/disable.sh permanent`) and
rebooted the same way shows a black cockpit and the same `(none)`: not even the
built-in map reaches the cluster. So this is not ours.

Turning the ignition fully off and on instead settles it in one step. With our
library still disabled, the cockpit came up on its own:

    timer 0  MONO --a  29029/100000
    capture buffer = win-24

`win-24` is the same buffer seen on the working drive of 3 Nov. The cluster
negotiates the cockpit stream when it and the head unit come up together; a
head-unit-only reboot leaves the cluster booted and waiting for a stream nobody
offers again, and only a source change in the car's own menu asks for it afresh.

What this retires:

* The "20-30 s before the map appears" was never a wait for anything in the
  stream. It was the time it took to reach for the map-source setting.
* The splash could not have covered it. Nothing we draw reaches the cluster
  while DisplayManager is not capturing, which is exactly what our sink logs:
  `waiting for DisplayManager to start capturing the cockpit`.
* `suggestUI` was not the gate either. Frames, a route and an accepted `showUI`
  were all in place while the cockpit stayed dark.

For developers: after `tools/deploy.sh`, either cycle the ignition or change the
map source in the car once. Driving away after a deployment hides this, because
starting the car power-cycles the unit anyway.

## `capture buffer` is not a reliable sign that the cluster is being fed

While a map source was switched away and back, the DisplayManager timer and the
capture buffer disagreed:

| time | periodic timer | `capture buffer` |
|---|---|---|
| 20:26:29 | timer 0 armed, 100000 | `win-29` |
| 20:26:50 | timer 0 **disarmed**, `0/0` | `win-29` |
| 20:27:35 | timer 0 disarmed, new timer 1 armed | `win-29` |

The buffer stayed set across a stop. Our sink gates on the buffer, so in that
window it believes all is well and keeps pushing frames while nothing reaches
the cluster -- which looks exactly like a frozen cockpit. DisplayManager creates
a fresh timer on each restart and leaves the old one disarmed, so the count of
armed timers, not the buffer, is what says whether the cluster is being fed.

## One frame-rate ceiling, not two

The 13.5 fps figure in ARCHITECTURE.md was measured with no phone connected: it
is the rate at which the built-in map alone repaints. With our stream live,
measured over 20 s:

| stage | rate |
|---|---|
| phone to the sink | 600 NALs / 20 s = **30 fps**, `errors=0` |
| `dpy-6` composition | 700 frames / 20 s = **35 fps** |
| DisplayManager to the cluster | **10 fps** |

So composition is not a ceiling and there is nothing behind the 10 to hit next.

The 10 has a handle. DisplayManager is a native, dynamically linked ARM binary
(`/tsd/bin/displaymanager/tsd.mibstd2.system.displaymanager`), it imports no
display-rate setter at all, and it imports `timer_create`/`timer_settime`.
`pidin -p<pid> timers` shows exactly one armed periodic timer while the cluster
is being fed, at `100000` -- microseconds, so 100 ms, so 10 Hz. Milliseconds
would be a frame every 100 s and nanoseconds 10 000 fps, so the unit is not in
doubt. The timer is armed when streaming starts and disarmed when it stops.

Its `cpu.conf` block already carries the same kind of entry we use for SAL:

    service iMX6.DispMg
       envar LD_PRELOAD /lib/libmmappriofix.so.1

Untried, and not to be tried on a car that has to drive the next day: a hook on
`timer_settime` that divides the interval. Two unknowns remain -- whether the
cluster accepts more than 10 fps over MOST at all (the built-in map gets the
same 10), and that the block carries `restart global 3`, so a hook that crashes
DisplayManager repeatedly takes the whole unit down.

Static analysis of the binary got no further: Apple's `objdump` rejects the QNX
ELF ("invalid section index: 37"), and the two log strings
(`] update rate set to `, `Failed to set update rate of display `) are
referenced neither by a literal-pool word nor by an ARM or Thumb-2 `movw`/`movt`
pair, so the call site was not found without a working ARM disassembler.

## The first consumer attach was a lottery, not a long interval

After the reboot artefact, a second delay was left: the cluster sometimes kept the
built-in map for half a minute after the phone connected. The log showed it as a
silence between the first frame and the consumer attaching:

    1793825042.057  SETUP stock result=0 response=yes
                    ... 30.7 s of nothing ...
    1793825072.727  gen2 renderer consumer attach rc=0 generation=3

In `gen2_output_worker`:

    static unsigned retry;
    if ((retry++ % 6000u) == 0u) gen2_consumer_attach();
    ...
    usleep(5000);

6000 passes of 5 ms is 30 s, and the comment defending it said Type-111 sends a
keyframe only about once every 29 s so a shorter retry would discard priming.

**Two things were wrong, and only one of them was the interval.**

The stated reason does not hold: `forceKeyFrame` is answered in about 140 ms and
the attach signals keyframe intent. But the *mechanism* it protected is real and
has nothing to do with keyframes -- `gen2_consumer_attach()` discards priming in
progress, and priming itself takes longer than two seconds. Shortening the
interval to 2000 ms was tried on the unit and it collapsed: **80 attaches,
generation 82, 61 resyncs at about one a second, frames arriving, the sink
pushing nothing at all, the cockpit black.** That is exactly the failure the 30 s
was guarding against, reached by a different argument. The default is back to
30000 and a shorter value is an experiment, not a setting.

The real fault was next to it: **`retry` is static and was never reset.** It kept
its value across sessions, so where it happened to stand relative to the period
decided how long the first attach waited -- anywhere from nothing to a full 30 s.
The same build and the same interval produced a 30.7 s silence once and 61 ms
another time. That is why the delay looked intermittent and why a reconnect
sometimes "fixed" it.

Fixed by resetting the counter when a session starts wanting data, so the first
attempt of every session is immediate and the backoff applies only to retries,
where it was meant to. The interval itself stays tunable from
`mibr-alt111-attach-retry-ms` (`tools/set-watchdog.sh attach`), re-read once a
second while unattached.

A shorter interval would need attach to leave priming alone while priming is
running. That is not implemented, and it is the only thing that would make a fast
retry safe.

## The second view area is inert: the two states cannot both be centred

Two things were wrong with the idle state, and fixing the first exposed that the
second is not fixable the way we assumed.

**The switch really was broken.** `g_turns_active` defaults to 2 and a running
route on the AID 10" reports `turns=1`, so `(parsed.turns >= g_turns_active)` was
false in every state and both fell back to the idle rectangle. With
`tools/set-safearea.sh turns 1` and a guiding rectangle configured, it fires:

    GEN2 ViewArea[1] guiding safe=700x320@0,28
    GEN2 ViewArea[0] full=1010x376 safe=700x320@155,28 views=2
    GEN2 guidance turns=0 -> viewArea 0
    GEN2 guidance turns=1 -> viewArea 1

The switch is sent 16 ms after the mode change, and it is sent only on a *change*
of turns (`delta & (1u<<5)`), so at session start with no route nothing is sent
and the phone takes index 0.

**And it changes nothing.** With the idle rectangle at 155, the guiding one was
set to 0, then 155, then 310 -- a 310 px span, the full width the canvas allows --
and the picture while guiding did not move by a pixel each time. Setting the
*idle* rectangle to 0 then centred the guiding picture, with the guiding
rectangle still sitting at 310. So the phone uses the first view area's rectangle
in both states, and accepts `updateViewArea` without acting on it.

| idle rect | guiding rect | no route | with a route |
|---|---|---|---|
| 0 | none | left of centre | **centred** |
| 155 | 0 | **centred** | right |
| 155 | 155 | **centred** | right |
| 155 | 310 | **centred** | right |
| 0 | 310 | left of centre | **centred** |

One rectangle therefore has to serve both, and the two states want different ones,
so only one can be centred:

    0 28 700 320     guiding centred, idle sits left
    155 28 700 320   idle centred, guiding sits right

Chosen: `0 28 700 320`, one view area, guiding centred. Guiding is the state the
cluster map exists for, and a compromise between the two would centre neither.

What this retires: the whole two-rectangle design in `set-safearea.sh`. The
switch, the threshold and the `nav` rectangle all work as written and buy nothing
on this head unit. The note in that tool has been corrected so the next attempt
starts from the measurement rather than from the intention.

## Releasing on disconnect does bring the built-in map back

Open until now. Observed on the cluster: unplugging the phone drops straight to
the built-in map, with no frozen last frame left behind.

## A resync storm can be a symptom of attach churn, not of the D2 policy

During the 2 s attach experiment the log filled with `GEN2 RESYNC REQUEST`, about
one a second, reaching epoch 101 -- which looks exactly like the keyframe
metronome coming back. It was not. With the interval back at 30 s the same
session ran **0 resyncs in 20 s** while the sink pushed 300 NALs per 10 s. The
resyncs were driven by the attach loop discarding priming and asking for a
keyframe each time it started over.

So when counting resyncs to judge the keyframe policy, check the attach
generation first: `grep -c 'consumer attach'` and the `generation=` on the last
one. A generation in the dozens means the resync rate is not telling you anything
about D2.

## Superseded commits

Two commit messages in the history state things that later measurement on the
unit contradicted. The code and the documents at HEAD are correct; only those
messages are not, and they are left in place as the record of how it was measured.

| commit | what it claims | what holds |
|---|---|---|
| `0a371b3` "Two frame-rate ceilings" | composition caps us at 13.5 fps as well as DisplayManager's 10 | one ceiling. With our stream live, composition runs 35–37 fps; the 13.5 was the built-in map repainting with no phone connected. Corrected by `1052f56` |
| `2113eb4` "The rest of the startup delay was a 30 s retry of our own" | the 30 s attach interval caused the delay, and 2000 ms fixes it | the interval was not the cause — an unreset counter was — and 2000 ms blacked out the cockpit. Corrected by `ffe8090` and `da8ffa4` |

## The dropouts are not speed-dependent, and the log did not survive the drive

Reported from the drive of 5 Nov: two dropouts to the built-in map, one while
accelerating out of a village and one in a queue in town. Opposite ends of the
speed range, so the dropouts are **not** speed-dependent.

That retires the theory the D2 fix was built on. The forced keyframe every
second was real and is gone, but the reason it looked like the cause -- an IDR of
a moving map being expensive, and more expensive the faster the map moves -- does
not survive a dropout in a stationary queue.

Worse, the drive could not be read afterwards. Both logs live in `/tmp`, and
`/tmp` is wiped by the reboot that every ignition cycle performs, so switching
the car off destroys the evidence. The dropouts only happen while driving, and
nobody is sitting at the car with a laptop while driving.

Fixed by writing the significant lines to `/tsd/var/cpvc/events.log` as well,
rotated once at 256 KB. It carries every teardown, every watchdog decision, the
session coming and going, and a heartbeat once a minute with composition
progress, whether DisplayManager is capturing, and how much we have pushed --
enough to place a dropout reported from the road against something.
`tools/get-events.sh` fetches it and prints the teardowns and the heartbeats.

Each of the three paths that can remove our window names itself in that log, so
the next drive settles whether the dropouts are ours:

| line | path |
|---|---|
| `DisplayManager has not captured for Ns` | the cluster dropped its video connection, 60 s threshold |
| `still stalled Ns after the keyframe request` | composition froze while we kept pushing, 2 x 4 s |
| `no frames for N s -> releasing the cockpit` | the phone stopped sending, 30 s |

All three need longer than the 1-5 s the driver sees, so if a dropout has none of
those lines against it, the cause is outside this library and the heartbeat says
whether composition or capture faltered at that moment.

## The attach counter reset was still in the wrong place

Yesterday's fix reset the retry counter when the sink starts wanting data. That
is too early: the sink wants data from the moment it starts, long before the
phone's stream exists, and every pointless attempt in that gap advances the
counter -- five of them were visible in the log of 4 Nov before any stream. So
when the stream finally arrived we were again at a random point in the 30 s
period, which is exactly what the drive of 5 Nov reported: a long wait on the
built-in map.

The counter is now also zeroed where the first frame of a session is accepted,
which is the only moment worth attaching at. The session-start reset is kept for
the case where frames are already flowing when the sink comes up.

## Detailed logging onto a USB stick, and a second-by-second telemetry line

Two problems made the mid-drive dropouts undiagnosable, and the event log on
`/tsd` only solved half of one. `/tmp` is wiped by the reboot behind every
ignition cycle, and the link off the unit runs at about 3 kB/s -- six minutes for
one session's verbose log, assuming the car is still switched on. The free USB
port solves both: a stick survives the ignition and reads on a laptop in seconds.

Written by a thread of its own, because the frame path must never wait on USB:

* **`telemetry.log`, one line a second.** This is the point of the exercise. A
  dropout the driver reports as one to five seconds is invisible in a log that
  only speaks when something decides to act, and all three of our teardown paths
  need longer than that to fire. Four numbers a second tell the modes apart:

      <epoch> comp=<counter> dcomp=<delta> cap=<0|1|-1> sent=<AUs> dsent=<delta> fail=<n> state=<n>

  | symptom in the telemetry | what it means |
  |---|---|
  | `dcomp` goes to 0 while `state=1` | `dpy-6` is not being recomposed |
  | `cap` goes to 0 | DisplayManager stopped capturing: nothing reaches the cluster |
  | `dsent` goes to 0 while `state=1` | we stopped feeding |
  | `state` dips to 0 and back | our context was torn down and rebuilt — what a fallback to the built-in map looks like from inside |
  | none of the above at the reported time | **not ours**, which moves the search to the cluster and the MOST link |

* **Both verbose logs, appended every ten seconds** from where they were last
  shipped, so nothing is copied twice and `/tmp` stays the fast buffer.

Where a USB stick mounts on this unit is not documented anywhere we have, so the
shipper scans `/media/*` and `/fs/*` for a volume it can write to, skipping
`mp000` by name because that is the read-only map card. `logship-dir` pins one
instead, `logship-off` switches the whole thing off, and `tools/set-logship.sh
probe` lists what the unit can see. A stick pulled mid-drive is noticed on the
next write and picked up again when it returns.

`tools/read-telemetry.py` reads the result: it groups neighbouring suspicious
seconds into the episodes a driver would actually notice, prints gaps where the
unit was off or the stick was out, and takes `--at HH:MM:SS` to show a window
around a time reported from the road.

## The dropouts track a change of speed, not a speed

Reported from the drive of 10 Nov: the stream drops when slowing down, for
example from 100 to 45 km/h. That reconciles the two reports of 5 Nov which
looked contradictory -- one accelerating out of a village and one in a queue in
town. A queue is nothing but accelerating and slowing down, so the common factor
is not how fast the car is going but that the speed is **changing**. The earlier
conclusion, "not speed-dependent", was right to reject absolute speed and wrong
to stop there.

Two mechanisms fit, and they live on opposite sides of the link:

**The phone redraws the scene.** Apple Maps and Waze both rezoom the map as speed
changes, which is a full redraw: a keyframe and a burst of access units for a
moving 1010x376 map. Nothing we can stop at source.

**The head unit changes the cluster data rate.** `ChangeDataRateSequence` exists
in the HMI and `update rate` is a variable there, not a constant -- 1 and 0 have
both been seen in other states. If a vehicle-state change runs that sequence,
DisplayManager reconfigures its capture timer, and that is exactly the behaviour
measured on 4 Nov when the map source was switched: the old timer disarmed, a new
one created. Nothing reaches the cluster while that happens.

**We ask for the keyframe ourselves.** On every turns edge the library runs
`gen2_d2_schedule(G2_D2_SOURCE_TURNS, "turns-edge")`, so a change in the number
of reported turns forces an IDR. Slowing from 100 to 45 is typically the approach
to a manoeuvre or a village, which is exactly when `turns` changes -- so the
expensive keyframe may be ours, arriving at the worst possible moment. This is the
one of the three that is wholly in our hands, and `drsy` in the telemetry shows it.

The telemetry separates them, which is why `aus`, `idrs` and `rsy` were added to
it. A dropout carrying a keyframe or a burst of frames came from the phone; one
with the counters ticking along evenly did not, and the fault is on this side.
`tools/read-telemetry.py` prints that as the verdict for each episode, so the
reading does not depend on remembering which column means what. Our own request is
checked before the keyframe marker: a keyframe we asked for is not the phone
redrawing the scene, and since we ask on every turns edge, the other order would
blame the phone for every manoeuvre.

Still to check at the car, and not codeable blind: DisplayManager logs
`update rate set to N` to the `dispmg` stdout log named in its `cpu.conf` block.
If that log can be found and followed, a rate change at the moment of a dropout
is direct evidence for the second mechanism.

## The fourth teardown path, and the counter that made it fire for nothing

Refined from the drive of 10 Nov: the dropouts do not come at every turn, but
they have come several times entering a village -- where the map rezooms. That
demotes the turns-edge keyframe, which would fire at every manoeuvre, and points
at the phone redrawing the scene.

Which led to the path none of our tables had, because the three we knew all need
seconds to fire and the driver sees one to five:

    if (++v_fail > 30) {
        v_log("errors=%ld (ok=%ld) -> tearing down, retrying on the next IDR", ...);
        v_teardown();

Thirty-one refused pushes is about a second at 30 fps -- the only path fast
enough to match. And **`v_fail` was never reset on a successful push.** It was
cleared at setup and nowhere else, so it was not a burst counter at all but a
lifetime count: refusals picked up one at a time across a drive accumulated until
the thirty-first tore the context down, whenever that happened to fall. That
matches the report exactly -- not at every turn, but several times over a drive,
each village contributing a few.

A second fault sat beside it. `v_retries` was not cleared on a successful setup
either, so four rebuilds spread across a long drive would reach
`SINK DISABLED (4 failures)` and the cockpit would stay gone for good.

Both fixed, and the response made two-stage, which is what the composition
watchdog in the same file already argues for -- the first stage is invisible to
the driver and the second is not:

* thirty-one refusals **in a row** now request a keyframe and keep the window;
* a second burst within five seconds is treated as a real fault and tears down;
* a successful push clears the run, a successful setup clears the retry count;
* the lifetime figure is kept separately for the log and the telemetry, so
  nothing is lost by the counter meaning what it says.

The telemetry also carries `drop`/`ddrop` now, because the rezoom hypothesis
predicts exactly that signature: a burst arrives, the queue cannot take it, and
access units are thrown away. `tools/read-telemetry.py` reports dropped frames
ahead of the keyframe and burst markers -- that we could not take the burst says
more than that it arrived, and it is the half that is ours to fix.

Four scenarios were run against the reader to check it names each one correctly:
our own keyframe, an unprompted one from the phone, a rezoom overrunning the
queue, and DisplayManager simply stopping its capture.
