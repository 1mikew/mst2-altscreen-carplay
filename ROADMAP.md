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
| 🔬 | Mid-drive dropouts | **Not fixed, and not speed-dependent.** The drive of 5 Nov had one accelerating out of a village and one in a stationary queue, which retires the theory the D2 fix rested on. The drive could not be read afterwards either: both logs were in `/tmp`, wiped by the reboot every ignition cycle performs. Now mirrored to `/tsd/var/cpvc/events.log` with a minute heartbeat, fetched by `tools/get-events.sh`. Each of the three paths that remove our window names itself there, so the next drive settles whether it is ours. [docs/FINDINGS.md](docs/FINDINGS.md) |
| 🟡 | Detailed logging to USB | A thread of its own writes `telemetry.log`, one line a second (composition delta, capture state, access units pushed, context state), plus both verbose logs every ten seconds, onto a stick in the free USB port — which survives the ignition and reads on a laptop instead of over a 3 kB/s link. Where a stick mounts here is undocumented, so it scans `/media/*` and `/fs/*` for somewhere writable; `tools/set-logship.sh` pins or disables it. `tools/read-telemetry.py` groups the suspicious seconds into episodes. **Built, not yet installed.** [docs/FINDINGS.md](docs/FINDINGS.md) |
| ✅ | Startup delay | **Was our own reboot, not the CarPlay path.** After `tools/deploy.sh`, which reboots the head unit alone, the cluster stays booted and waiting for a stream nobody offers again: `capture buffer = (none)` for four and a half minutes with frames arriving, a route running and a hand-sent `showUI` accepted. The same reboot with our library disabled gives a black cockpit too, so it is not ours. An ignition cycle fixes it in one step — `capture buffer = win-24`, timer armed, built-in map up by itself. For developers: after a deployment, cycle the ignition or change the map source once. [docs/FINDINGS.md](docs/FINDINGS.md) |
| 🟡 | First consumer attach | The delay was never the 30 s interval but the `retry` counter beside it, static and unreset. Resetting it on the session edge was still too early — the sink wants data long before a stream exists and every pointless attempt advanced the counter, so the drive of 5 Nov again waited on the built-in map. Now also zeroed where the first frame is accepted, the only moment worth attaching at. Default interval stays 30000; 2 s blacked out the cockpit. **Built, not yet installed.** [docs/FINDINGS.md](docs/FINDINGS.md) |
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

1. ✅ Cluster layout — settled 4 Nov. One rectangle `0 28 700 320`, one view area,
   guiding centred. Two rectangles are a dead end by measurement: the threshold really
   was wrong (default 2, a running route reports 1) and with `turns 1` the switch fires
   16 ms after the mode change, but the guiding rectangle is inert — moved across a
   310 px span the guiding picture did not shift a pixel, while the *idle* rectangle
   governs both states. So only one of the two states can be centred, and guiding is the
   one that matters. Manoeuvre card deliberately left on the radio display
2. 🔴 **Install the build and put a stick in the free USB port — everything below waits
   on it.** Until then no drive can be read: both logs live in `/tmp`, which the reboot
   behind every ignition cycle wipes, and the link off the unit runs at about 3 kB/s. The
   shipper writes one telemetry line a second plus both verbose logs onto the stick, which
   reads on a laptop in seconds. `tools/deploy.sh`, then `tools/set-logship.sh probe` to
   see where the stick landed, and `tools/read-telemetry.py` on it afterwards
   persistent event log, and until it is on the car no drive can be read: both logs live
   in `/tmp`, which the reboot behind every ignition cycle wipes, so switching the car off
   destroys the evidence for a fault that only happens while driving. It also fixes the
   first consumer attach. `tools/deploy.sh`, then `tools/get-events.sh clear` before a
   drive and `tools/get-events.sh` after
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
