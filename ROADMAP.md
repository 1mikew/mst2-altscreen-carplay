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
| ⬜ | Auto cleanup on disconnect | Last frame stays; both attempted fixes failed |
| 🔬 | Startup delay and mid-drive freezes | 10–30 s to first picture, and brief freezes that recover by themselves. Both plausibly wait on the same thing — an IDR, which Type-111 sends about every 29 s — but the logs already show a resync completing in ~150 ms, so that is a hypothesis, not a diagnosis. Measure before changing anything |
| ⬜ | Extended road testing | Longer drives, connect/disconnect cycles, cold starts |
| 🟡 | SafeArea / ViewArea *(fork)* | Honoured by the app and tunable from a file. Calibrated to `245 28 520 320`; centring still to be refined |
| ⬜ | D2 tuning *(fork)* | Event-scoped recovery instead of the 1 s watchdog |
| 🟡 | Steering-wheel zoom | Request located: BAP NavSD `MapScale`, already decoded, step vs continuous distinguished. Open: the alt screen declares no input device, so there is nothing to send it to yet. [docs/CLUSTER-ZOOM.md](docs/CLUSTER-ZOOM.md) |
| ⛔ | Native navigation arrows / RGI | The BAP NavSD sink exists (`ManeuverDescriptor`, `LaneGuidance`, `TurnToInfo`), but nothing found in the image feeds it from CarPlay — `ExboxGuidanceListener` carries a guidance *state*, not manoeuvre data. No turn-by-turn path to the head unit. Not planned |
| 🔬 | **Raise the frame rate** | **Found.** The cluster sends a *mode* (0/1/2), not a rate; `ChangeDataRateSequence._stepChangeDataRate` maps mode 2 to a hard-coded `setDataFrameRate(10)`. That constant is the ceiling, and it is on the head unit where we have access. omonob shadows the same class and runs 40 fps on MHI2 |
| ⬜ | Other firmware | Wanted, but only `P0480T` can be tested here — no other unit available |
| ⛔ | `/dev/mlb` transport | No such device on this platform |

## Known limits

| | |
|---|---|
| Frame rate | 10 fps, from a constant in the HMI rather than a negotiated limit. Whether the cluster accepts more is untested |
| After disconnect | Last frame remains; switching the cockpit view clears it |
| Mid-drive freeze | The cluster picture stops for a few seconds while the phone keeps navigating normally, then catches up on its own. Not always fatal, so the earlier "only a view switch recovers it" was too absolute |
| Startup delay | 10–30 s from connecting the phone to a picture on the cluster |
| Firmware | One build, one car |
| Layout inside the SafeArea | Partly ours: `maneuverLayout` places the card left, right or top. Everything else is the app's |
| Manoeuvre card | Not shown on the cluster by choice — the map-only surface is the target. The card stays on the radio display |

## Order of work

The overlay is gone, so the picture can finally be judged on its own.

1. 🟡 Road-test the map-only surface (`tools/set-surface.sh map`). If the route still
   draws and the layout centres, that is the intended configuration and the
   right-alignment problem disappears with the card
2. 🔬 Measure the startup delay and the freezes before touching D2
3. 🔬 Raise the cluster frame rate past the hard-coded 10
3. ⬜ Auto cleanup when the phone disconnects
4. ⬜ Extended road testing *(gate for everything below)*
5. ⬜ D2 tuning *(fork)*
6. ⬜ Steering-wheel control *(fork)*
7. ⬜ Native navigation arrows *(fork)*
8. 🔬 **Test a higher frame rate.** Angles: where DisplayManager takes the value from at
   FPK setup, whether the advertised `maxFPS` matters (the hook already has a runtime
   override), and upstream's Continental FPK research
9. ⬜ **Broader firmware coverage.** Blocked on access, not on design: most of the work is
   firmware-independent. Needs people with other units

## Help wanted

- **Other MIB2 Standard firmware** with shell access. This is the single biggest gap: we
  want to support more than one build and cannot, because there is only one unit to test
  on. Do the window parameters and the push protocol hold on yours?
- Experience with **QNX Screen**, **BAP/FPK** on MQB, or the **J9/JXE HMI**
- Navigation-transition traces from other units
