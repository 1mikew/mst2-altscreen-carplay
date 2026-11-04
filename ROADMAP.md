# Roadmap

**Work in progress.** Nothing below is a release promise. Items marked ✅ are vehicle-tested
on one car; everything else is not done.

`✅ done` · `🟡 in progress` · `⬜ planned` · `🔬 research` · `⛔ not possible here`
· *(fork)* = follows upstream, see [docs/UPSTREAM-STATUS.md](docs/UPSTREAM-STATUS.md)

## Status

| | Item | Notes |
|---|---|---|
| ✅ | Type-111 to the cockpit | Own mm-renderer context, native 1024×384 |
| ✅ | Two independent displays | Both contexts `playing` at once; radio untouched |
| ✅ | Decoder init from the live stream | SPS/PPS collected at runtime, `avcC` built on the fly |
| ✅ | Provider switching | Apple Maps, Waze, Google Maps |
| ✅ | Keyframe policy | Upstream D2 enabled |
| ✅ | Persistence | Survives reboot, comes up on its own |
| ✅ | Kill switch + stock restore | Session-local and permanent |
| ✅ | Runtime reconfiguration | Geometry without rebooting the unit |
| ✅ | **"Navigation on phone" overlay removed** | One instruction in `CarPlayModeHandling`; route guidance is visible. [docs/HMI-OVERLAY.md](docs/HMI-OVERLAY.md) |
| 🟡 | Auto cleanup on disconnect | Three behaviours selectable: `keep`, `splash`, `release`. Driven from the session teardown hook — frame starvation was the wrong signal, and at 5 s it read an app switch on the radio as a disconnect. The idle timer is the fallback only, 30 s. Whether the built-in map redraws once released is still unmeasured. `tools/set-on-disconnect.sh` |
| 🟡 | **Splash frame of our own** | Driven twice at the right size, showed nothing either time. It is gated on DisplayManager capturing, and the 20–30 s wait for the first picture suggests that gate opens about when the first natural IDR arrives — so the gap it was written for may not exist. The skip is logged; read the log before changing anything. Off unless the file is present |
| 🔬 | Mid-drive dropouts | **Not fixed.** The cluster falls back to the stock map for 1–5 s, more often at speed outside town, then recovers. The one drive that reported none was the outlier, not the new baseline. A dropout to the *stock* map means our window was removed, which only three code paths do — and all three need longer than 5 s to fire, so a fourth cause outside this library is in play. Each path logs a distinct line; `tools/set-watchdog.sh stall 600` rules our own teardown in or out without a rebuild. [docs/FINDINGS.md](docs/FINDINGS.md) |
| 🔬 | Startup delay | 20–30 s to first picture, unchanged across builds. We do ask for a keyframe while waiting, every 10 s, so either the request is not reaching the phone before the natural IDR or the phone ignores it for stream 111. The same gate holds the splash back, which makes the two one measurement |
| ⬜ | Extended road testing | Longer drives, connect/disconnect cycles, cold starts |
| 🟡 | SafeArea / ViewArea *(fork)* | Honoured by the app and tunable from a file. The guiding rectangle `0 28 700 320` centres the map. The second view area for the idle state is declared and the guidance change is noticed, but the switch never fired: the threshold is two turns and a running route reports one. `mibr-carplay111-turns-active` overrides it, and whether the phone then acts on `updateViewArea` is the untested half |
| ⬜ | D2 tuning *(fork)* | Event-scoped recovery instead of the 1 s watchdog |
| 🟡 | Steering-wheel zoom | **Both halves known, including the values.** In: BAP NavSD `MapScale`, decoded, step vs continuous. Out: `changeMapZoomLevel` with `uuid` and `zoomDirection` (0 in, 1 out), paced one step at a time, no acknowledgement. Needs writing. [docs/CLUSTER-ZOOM.md](docs/CLUSTER-ZOOM.md) |
| ⛔ | Native navigation arrows / RGI | The BAP NavSD sink exists (`ManeuverDescriptor`, `LaneGuidance`, `TurnToInfo`), but nothing found in the image feeds it from CarPlay — `ExboxGuidanceListener` carries a guidance *state*, not manoeuvre data. No turn-by-turn path to the head unit. Not planned |
| 🟡 | **Raise the frame rate** | The cluster sends a *mode*, not a rate: `ChangeDataRateSequence` maps mode 2 to a hard-coded `setDataFrameRate(10)`. Tooling ready — `make-fps-patch.py` flips the byte, `set-cluster-fps.sh` puts it in the override jar and verifies it. Whether the cluster accepts more is still unanswered; try it parked |
| ⬜ | Other firmware | Wanted, but only `P0480T` can be tested here — no other unit available |
| ⛔ | `/dev/mlb` transport | No such device on this platform |

## Known limits

| | |
|---|---|
| Frame rate | 10 fps, from a constant in the HMI rather than a negotiated limit. Whether the cluster accepts more is untested |
| After disconnect | Last frame remains; switching the cockpit view clears it |
| Mid-drive dropout | The cluster falls back to the stock map for 1–5 s, sometimes longer, then our picture returns on its own. More frequent at speed outside town. Unexplained — see docs/FINDINGS.md |
| Startup delay | 10–30 s from connecting the phone to a picture on the cluster |
| Firmware | One build, one car |
| Layout inside the SafeArea | The rectangle's *position* is the only working lever, and it works as an offset. `maneuverLayout` blanks the cluster |
| Manoeuvre card | Not shown on the cluster by choice — the map-only surface is the target. The card stays on the radio display |

## Order of work

The overlay is gone, so the picture can finally be judged on its own.

1. 🟡 Cluster layout — one rectangle centres one state, not both. `0 28 700 320`
   centres the map while guiding, driven 26 Oct; `155 28 700 320` centres it when idle.
   The rectangle is an offset against the phone's right bias, not a frame to centre
   content inside. Two view areas are declared for the two states; the log says why the
   switch never fired — the threshold is two turns and a running route reports one, so
   every state used the idle area. `turns-active` at 1 is the next drive. A single
   rectangle may still serve both; see docs/FINDINGS.md. Manoeuvre card deliberately
   left on the radio display
2. 🔬 The dropouts and the startup delay — read the log from the drive before changing
   anything, then the `stall 600` experiment to rule our own teardown in or out
3. 🟡 Raise the cluster frame rate past the hard-coded 10 — tooling ready, needs a car
3. ⬜ Auto cleanup when the phone disconnects
4. ⬜ Extended road testing *(gate for everything below)*
5. ⬜ D2 tuning *(fork)*
6. ⬜ Steering-wheel control *(fork)*
7. ⬜ Native navigation arrows *(fork)*
8. ⬜ **If the cluster refuses a higher rate**, the remaining angles are the advertised
   `maxFPS` (the hook already has a runtime override) and upstream's Continental FPK
   research
9. ⬜ **Broader firmware coverage.** Blocked on access, not on design: most of the work is
   firmware-independent. Needs people with other units

## Help wanted

- **Other MIB2 Standard firmware** with shell access. This is the single biggest gap: we
  want to support more than one build and cannot, because there is only one unit to test
  on. Do the window parameters and the push protocol hold on yours?
- Experience with **QNX Screen**, **BAP/FPK** on MQB, or the **J9/JXE HMI**
- Navigation-transition traces from other units
