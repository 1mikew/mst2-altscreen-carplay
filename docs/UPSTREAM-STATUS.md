# Upstream comparison

Against **[harman-f/mhi2_altscreen_carplay](https://github.com/harman-f/mhi2_altscreen_carplay)**,
which this is forked from.

*Snapshot 19 Oct 2026. Upstream moves daily — treat as point-in-time.*

Upstream's recent commits are platform research (MU1440 clocks, memory layout, QNX startup,
V850 CAN). Its alt-screen feature line sits at **SafeArea calibration**, its current P0.

## Side by side

| | upstream (MHI2) | this (MIB2 Standard) |
|---|---|---|
| Stream 111 to cluster | ✅ | ✅ different transport |
| Main screen keeps working | ✅ | ✅ |
| Decoder on the head unit | none needed | own mm-renderer context |
| Keyframe recovery | ✅ D2 | ✅ upstream D2 |
| Frame rate | 20 fps native, ~28 measured | 10 fps — a constant in the HMI, not a negotiated limit |
| **Head unit** | Harman MHI2 "High" | Škoda Amundsen 8", part `5Q0035874C` |
| **Cluster** | MQB Virtual Cockpit | AID 10", part `5E0920790A` |
| Canvas | 1010×376 baseline | 1010×376 — identical |
| Reversible install | ✅ | ✅ |
| Provider switching | ✅ vehicle proof of concept (Apple/Google/Waze) | ✅ road-tested |
| SafeArea / ViewArea | 🟡 P0 | 🟡 advertised, honoured, calibrated to `245 28 520 320` |
| Steering wheel, media | ⬜ | ⬜ fork |
| Native navigation arrows | ⬜ | ⛔ no turn data reaches the head unit |
| Firmware matrix | 6 baselines | 1 |
| "Navigation on phone" overlay | n/a on their HMI | ✅ removed — [HMI-OVERLAY.md](HMI-OVERLAY.md) |

**The cluster is shared; only the head units differ.** Both sides independently measured a
1010×376 canvas — unrelated panels would not land on the same number.

That establishes the *video contract*. Whether the *usable area* is identical depends on
the physical panel, so SafeArea presets should be matched by part number. This side is
**AID 10", `5E0920790A`** (Octavia); if upstream's differs, the presets may need their own
calibration even though the canvas matches.

## What ports across

| upstream item | portable | why |
|---|---|---|
| SafeArea / ViewArea | ✅ directly | Same canvas, session level only |
| D2 keyframe tuning | ✅ | Already running the upstream policy |
| Multi-ViewArea, media metadata | ✅ | Protocol level |
| Steering wheel control | ✅ largely | Same cluster, same BAP block |
| Nav arrows / RGI | ⛔ | The NavSD sink exists on both sides; the data does not. `ExboxGuidanceListener` carries only a guidance state, and no other CarPlay route to manoeuvre data appears in the image |
| Exact-stock Java isolation | method only | Different HMI, but the method carried: shadow classes via `-Xbootclasspath/p:` is what removed the overlay here |
| Continental FPK RE | 🔬 | Less critical than it looked: the 10 is a literal in the HMI, above FPK. Still the answer to what the cluster will actually accept |
| Direct-TS remux, `/dev/mlb` | ⛔ | No such device here — the one real divide |
| Most20 20 fps, AID matrix, MU1438 | ⛔ | Head-unit side |

## What this side can give back

- Proof the architecture works **without `/dev/mlb`** — decode on the unit, let the stock
  capture path carry it.
- The **`mdevpush` protocol incl. decoder init** ([PROTOCOL-MDEVPUSH.md](PROTOCOL-MDEVPUSH.md)).
  QNX `mm-renderer` is used well beyond this head unit.
- **Where the frame rate really comes from.** `update rate set to 10` reads like the
  cluster's demand; it is not. The cluster sends a *mode* (0/1/2) and
  `ChangeDataRateSequence` maps mode 2 to a hard-coded `setDataFrameRate(10)`. The same
  class exists on MST2 and MHI2, so the ceiling sits on the head unit on both. Untested
  whether the cluster accepts more.
- **QNX Screen capture constraints** ([ARCHITECTURE.md](ARCHITECTURE.md)): overlay planes
  never reach the writeback buffer; a video-plane window generates no composition event.

## Sequencing

Forked items are not picked up as they appear. The overlay is gone, so the order is now:
road testing → SafeArea refinement → frame rate → view control and wheel input.

Downstream fork, not a competitor. Credits in [../CREDITS.md](../CREDITS.md).
