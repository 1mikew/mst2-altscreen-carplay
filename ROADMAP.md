# Roadmap

**Work in progress.** Nothing below is a release promise. Items marked ✅ are vehicle-tested
on one car; everything else is not done.

`✅ done` · `🟡 in progress` · `⬜ planned` · `🔬 research` · `🟥 blocking` · `⛔ n/a here`
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
| 🟥 | **"Navigation on phone" overlay** | Cluster covers the picture during route guidance — the one blocker for real use |
| 🟡 | Removing that overlay | Bytecode analysis of `CarPlayModeHandling` |
| ⬜ | Auto cleanup on disconnect | Last frame stays; both attempted fixes failed |
| ⬜ | Extended road testing | Longer drives, connect/disconnect cycles, cold starts |
| ⬜ | SafeArea / ViewArea *(fork)* | Upstream P0; same canvas, session level. Needs a live route to calibrate against |
| ⬜ | D2 tuning *(fork)* | Event-scoped recovery instead of the 1 s watchdog |
| ⬜ | Steering-wheel view/zoom *(fork)* | Wheel currently zooms the stock map |
| ⬜ | Native navigation arrows / RGI *(fork)* | Drive cluster widgets from CarPlay metadata over BAP NavSD |
| 🔬 | **Test a higher frame rate** | 10 fps observed. Set by DisplayManager at FPK setup — head-unit side, where we have access, and 1/0 seen in other states. Worth testing; nothing says it cannot go higher |
| ⬜ | Other firmware | Only `P0480T` tested. Needs testers |
| ⛔ | `/dev/mlb` transport | No such device on this platform |

## Known limits

| | |
|---|---|
| Frame rate | 10 fps observed, same as the stock map. Raising it is untested, not ruled out |
| After disconnect | Last frame remains; switching the cockpit view clears it |
| Capture stall | Recoverable only by switching the cockpit view; the HMI owns the FPK connection |
| Firmware | One build, one car |

## Order of work

Nothing is added until the current feature is stable and the overlay is gone — view
controls on a covered picture cannot be evaluated.

1. 🟥 Remove the "navigation on phone" overlay
2. ⬜ Auto cleanup when the phone disconnects
3. ⬜ Extended road testing *(gate for everything below)*
4. ⬜ SafeArea / ViewArea *(fork)*
5. ⬜ D2 tuning *(fork)*
6. ⬜ Steering-wheel control *(fork)*
7. ⬜ Native navigation arrows *(fork)*
8. 🔬 **Test a higher frame rate.** Angles: where DisplayManager takes the value from at
   FPK setup, whether the advertised `maxFPS` matters (the hook already has a runtime
   override), and upstream's Continental FPK research
9. ⬜ Broader firmware coverage

## Help wanted

- Other **MIB2 Standard** firmware with shell access — does the window and protocol work hold?
- Experience with **QNX Screen**, **BAP/FPK** on MQB, or the **J9/JXE HMI**
- Navigation-transition traces from other units
