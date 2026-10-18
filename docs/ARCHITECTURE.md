# Architecture

## Platform

| | |
|---|---|
| Head unit | Škoda Amundsen 8", part `5Q0035874C` — MIB2 Standard "MST2", TechniSat/Preh |
| SoC | i.MX6 quad Cortex-A9, QNX Neutrino 6.5 |
| Second chip | TI Jacinto 5 — owns MOST, reached over an internal IP link |
| CarPlay process | `/tsd/bin/sal/tsd.mibstd2.sal.main` (service `iMX6.SAL`) |
| Video | `mm-renderer`, `mdev_streamer.so` input, `imx6_video_decoder.so` |
| Cluster video | `tsd.mibstd2.system.displaymanager` |
| Cluster | Virtual Cockpit AID 10", part `5E0920790A` |

**No `/dev/mlb` anywhere.** MOST is behind the Jacinto 5 — the MHI2 approach of writing
MPEG-TS to `/dev/mlb/isoTX2` cannot be ported.

## Displays

| display | size | pipeline | role |
|---|---|---|---|
| `dpy-1` | 800×480 | 2 | radio screen |
| **`dpy-6`** | **1024×384** | **8** | **cockpit source** |
| `dpy-7` | 800×480 | 9 | unused |

Apps shown on the cluster create a clone window `DispId[<NAME>]Clone1` on `dpy-6`.
**SAL has no clone** — the original reason CarPlay never reached the cluster.

## Data path

```
iPhone ──CarPlay──> SAL ──┬─> main 800×480 ──> mm-renderer ──> dpy-1 (radio)
                          │
                          └─> Type-111 1024×384
                                └─> hook ──> own mm-renderer context ──> window on dpy-6
                                              │
          DisplayManager: capture dpy-6 ──> VPU H.264 ──> Jacinto 5 ──> MOST ──> cluster
```

The hook (`libaltscreen111.so`, LD_PRELOADed into SAL) advertises the alt screen, receives
Type-111 and feeds its **own** context. SAL's session is untouched — that is what makes two
independent displays possible.

## Output URL

```
screen:/?index=1&overlay=0&dstx=0&dsty=0&dstw=1023&dsth=384&zorder=500
```

| parameter | why |
|---|---|
| `index=1` | 0-based display selector. Without it the window lands on the radio screen — the cause of every early failure. |
| `overlay=0` | A hardware overlay plane never reaches the writeback buffer. |
| `zorder=500` | Above the map clone at `order=3`. |
| `dstw=1023` | Deliberately one pixel short — see below. |
| `wingrp` / `winid` | **Do not use.** The window inherits the parent's display and ends up `INVISIBLE` on `dpy-1`. |

### The missing pixel

The decoded picture sits on a **hardware video plane** (`usage = SCREEN_USAGE_VIDEO`,
`pipeline id = 8`), scanned out directly, needing no composition. But DisplayManager
captures *during* composition, and composition is driven by damage from the stock content
underneath.

Cover the map completely → it stops redrawing → composition nearly stops → the cluster
freezes. One visible pixel keeps it running:

| configuration | capture rate |
|---|---|
| stock map alone | 13.4 fps |
| our window over the whole cockpit | 0.4 – 4 fps |
| our window, 1 px of map beside it | **13.5 fps** |

## Preconditions

1. **DisplayManager must be streaming.** It sets a capture buffer on `dpy-6` and opens
   `/dev/mxc_vpu` only while the cluster shows the map. Check
   `grep 'capture buffer' /dev/screen/0/dpy-6` — `(none)` means nothing gets through.
2. **A keyframe is needed to start.** The context builds only on an IDR, sent about every
   29 s. The library requests one itself.

## Frame rate

Set at FPK connection setup —
`DisplayQNXScreen [DISPLAYID_CLUSTER] update rate set to 10`. Measured: 24–36 fps into the
decoder, 30–40 fps composition, **10 fps out**. The stock map gets the same.

Values of 1 and 0 were seen in other states, so the rate is a variable, not a constant,
and it is **DisplayManager** that applies it — head-unit side, where we have access.
Raising it is untested and on the roadmap; nothing so far says it cannot go higher.
