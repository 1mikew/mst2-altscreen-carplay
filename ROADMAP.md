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
| ✅ | Keyframe policy | Upstream D2 enabled, and its watchdog was a metronome: the rule "no keyframe for 1 s" is permanently true on this stream (718 frames against 1 IDR), so it forced an IDR every second for the whole drive. Now watches frames going stale instead, tunable from `mibr-alt111-d2-watchdog-ms`. Deployed and measured on the unit: 7 IDRs per 3000 frames, against roughly one per second before. Whether this also cures the mid-drive dropouts is a separate row |
| ✅ | Persistence | Survives reboot, comes up on its own |
| ✅ | Kill switch + stock restore | Session-local and permanent |
| ✅ | Runtime reconfiguration | Geometry without rebooting the unit |
| ✅ | **"Navigation on phone" overlay removed** | One instruction in `CarPlayModeHandling`; route guidance is visible. [docs/HMI-OVERLAY.md](docs/HMI-OVERLAY.md) |
| 🟡 | Auto cleanup on disconnect | Three behaviours selectable: `keep`, `splash`, `release`. Driven from the session teardown hook — frame starvation was the wrong signal, and at 5 s it read an app switch on the radio as a disconnect. The idle timer is the fallback only, 30 s. Whether the built-in map redraws once released is still unmeasured. `tools/set-on-disconnect.sh` |
| ❌ | **Splash frame of our own** | Retired. It was written to cover a gap that turned out to be our own reboot, and nothing we draw can reach the cluster during it: DisplayManager is not capturing, which is exactly what the sink logs. There is no gap left for it to fill once the ignition is cycled. [docs/FINDINGS.md](docs/FINDINGS.md) |
| 🔬 | Mid-drive dropouts | **Not fixed.** The cluster falls back to the stock map for 1–5 s, more often at speed outside town, then recovers. The one drive that reported none was the outlier, not the new baseline. A dropout to the *stock* map means our window was removed, which only three code paths do — and all three need longer than 5 s to fire, so a fourth cause outside this library is in play. Each path logs a distinct line; `tools/set-watchdog.sh stall 600` rules our own teardown in or out without a rebuild. [docs/FINDINGS.md](docs/FINDINGS.md) |
| ✅ | Startup delay | **Was our own reboot, not the CarPlay path.** After `tools/deploy.sh`, which reboots the head unit alone, the cluster stays booted and waiting for a stream nobody offers again: `capture buffer = (none)` for four and a half minutes with frames arriving, a route running and a hand-sent `showUI` accepted. The same reboot with our library disabled gives a black cockpit too, so it is not ours. An ignition cycle fixes it in one step — `capture buffer = win-24`, timer armed, built-in map up by itself. For developers: after a deployment, cycle the ignition or change the map source once. [docs/FINDINGS.md](docs/FINDINGS.md) |
| 🟡 | First consumer attach | The half-minute of built-in map was **not** the 30 s interval but the `retry` counter beside it: `static`, never reset, so where it stood decided the first attach — the same build gave a 30.7 s silence once and 61 ms another time. Shortening the interval to 2 s instead was tried on the unit and collapsed: 80 attaches, generation 82, 61 resyncs a second, sink pushing nothing, cockpit black — priming needs longer than 2 s, which is the real reason the 30 s existed. Default back to 30000; counter now reset per session so the first attempt is immediate. **Installed 4 Nov, active from the next start of the unit** — not driven yet. [docs/FINDINGS.md](docs/FINDINGS.md) |
| ⬜ | Extended road testing | Longer drives, connect/disconnect cycles, cold starts |
| ✅ | SafeArea / ViewArea *(fork)* | Honoured by the app and tunable from a file, and the two-rectangle idea is now **retired by measurement**. The threshold really was wrong (default 2, a running route reports 1) and with `turns 1` the switch fires 16 ms after the mode change — but the guiding rectangle is inert: moved across a 310 px span, the guiding picture did not shift a pixel, while the *idle* rectangle governs both states. One rectangle has to serve both and they want different ones, so only one can be centred. Settled on `0 28 700 320`, one view area, guiding centred. [docs/FINDINGS.md](docs/FINDINGS.md) |
| 🟡 | D2 tuning *(fork)* | The 1 s watchdog is off the keyframe counter and onto the frame counter — see docs/FINDINGS.md. `forceKeyFrame` is honoured in ~140 ms every time, so recovery can stay on demand instead of scheduled |
| 🟡 | Steering-wheel zoom | **Both halves known, including the values.** In: BAP NavSD `MapScale`, decoded, step vs continuous. Out: `changeMapZoomLevel` with `uuid` and `zoomDirection` (0 in, 1 out), paced one step at a time, no acknowledgement. Needs writing. [docs/CLUSTER-ZOOM.md](docs/CLUSTER-ZOOM.md) |
| ⛔ | Native navigation arrows / RGI | The BAP NavSD sink exists (`ManeuverDescriptor`, `LaneGuidance`, `TurnToInfo`), but nothing found in the image feeds it from CarPlay — `ExboxGuidanceListener` carries a guidance *state*, not manoeuvre data. No turn-by-turn path to the head unit. Not planned |
| 🔬 | **Raise the frame rate** | **One ceiling, not two, and it has a handle.** Composition is not a limit: with our stream live `dpy-6` runs 35 fps and the sink feeds 30: the old 13.5 figure was the built-in map repainting with no phone connected. What caps the cluster is DisplayManager, a native dynamically linked binary that imports no display-rate setter and holds exactly one armed periodic timer at `100000` µs = 10 Hz while the cluster is fed. Its `cpu.conf` block already carries an `LD_PRELOAD`, so a hook on `timer_settime` that divides the interval is the lever. Untried: the cluster may refuse more than 10 fps over MOST, and the block carries `restart global 3`. The jar patch is dead — no classfile on this unit. [docs/FINDINGS.md](docs/FINDINGS.md) |
| ⬜ | Other firmware | Wanted, but only `P0480T` can be tested here — no other unit available |
| ⛔ | `/dev/mlb` transport | No such device on this platform |

## Known limits

| | |
|---|---|
| Frame rate | 10 fps to the cluster, from a constant in the HMI; `dpy-6` composition is a second ceiling at 13.5 fps, inherited from the stock map's redraw rate. The phone sends 30 |
| After disconnect | Last frame remains; switching the cockpit view clears it |
| Mid-drive dropout | The cluster falls back to the stock map for 1–5 s, sometimes longer, then our picture returns on its own. More frequent at speed outside town. Unexplained — see docs/FINDINGS.md |
| Startup delay | Gone after an ignition cycle. A head-unit-only reboot (`tools/deploy.sh`) leaves the cockpit dark until the ignition is cycled or the map source is changed once |
| Firmware | One build, one car |
| Layout inside the SafeArea | The rectangle's *position* is the only working lever, and it works as an offset. `maneuverLayout` blanks the cluster |
| Idle map off-centre | Only one of the two states can be centred. The guiding one is, because the second view area turns out to have no effect on the layout — see docs/FINDINGS.md |
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
2. 🟡 Drive the D2 fix: the forced keyframe every second is gone, which is the best
   candidate for dropouts that worsen with speed. If they survive it, `set-watchdog.sh
   stall 600` rules our own teardown in or out
3. 🔬 Gate the sink on something better than `capture buffer`. Measured: the buffer
   stayed set while DisplayManager had disarmed its timer, so the sink believed it was
   being consumed and kept pushing frames into a cluster that was no longer fed. The
   count of armed periodic timers is what actually says. This is a candidate cause for
   the mid-drive dropouts
4. 🔬 Raise the cluster frame rate — a hook on `timer_settime` in DisplayManager, whose
   `cpu.conf` block already carries an `LD_PRELOAD`. Composition is not in the way (35
   fps measured). Open: whether the cluster accepts more than 10 fps over MOST
5. ⬜ Auto cleanup when the phone disconnects
6. ⬜ Extended road testing *(gate for everything below)*
7. ⬜ Steering-wheel control *(fork)*
8. ⬜ Native navigation arrows *(fork)*
9. ⬜ **If the cluster refuses a higher rate**, the remaining angles are the advertised
   `maxFPS` (the hook already has a runtime override) and upstream's Continental FPK
   research
10. ⬜ **Broader firmware coverage.** Blocked on access, not on design: most of the work is
   firmware-independent. Needs people with other units

## Help wanted

- **Other MIB2 Standard firmware** with shell access. This is the single biggest gap: we
  want to support more than one build and cannot, because there is only one unit to test
  on. Do the window parameters and the push protocol hold on yours?
- Experience with **QNX Screen**, **BAP/FPK** on MQB, or the **J9/JXE HMI**
- Navigation-transition traces from other units
