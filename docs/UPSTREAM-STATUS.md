# Upstream comparison

Against **[harman-f/mhi2_altscreen_carplay](https://github.com/harman-f/mhi2_altscreen_carplay)**,
which this is forked from.

*Snapshot 14 Oct 2026. Upstream moves daily — treat as point-in-time.*

Upstream's recent commits are platform research (MU1440 clocks, memory layout, QNX startup,
V850 CAN). Its alt-screen feature line sits at **SafeArea calibration**, its current P0.

## Side by side

| | upstream (MHI2) | this (MIB2 Standard) |
|---|---|---|
| Stream 111 to cluster | ✅ | ✅ different transport |
| Main screen keeps working | ✅ | ✅ |
| Decoder on the head unit | none needed | own mm-renderer context |
| Keyframe recovery | ✅ D2 | ✅ upstream D2 |
| Frame rate | 20 fps native, ~28 measured | 10 fps observed, set at FPK setup |
| **Head unit** | Harman MHI2 "High" | Škoda Amundsen 8", part `5Q0035874C` |
| **Cluster** | MQB Virtual Cockpit | AID 10", part `5E0920790A` |
| Canvas | 1010×376 baseline | 1010×376 — identical |
| Reversible install | ✅ | ✅ |
| Provider switching | ✅ vehicle proof of concept (Apple/Google/Waze) | ✅ road-tested |
| SafeArea / ViewArea | 🟡 P0 | ⬜ fork |
| Steering wheel, arrows, media | ⬜ | ⬜ fork |
| Firmware matrix | 6 baselines | 1 |
| "Navigation on phone" overlay | n/a on their HMI | 🟥 blocking |

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
| Steering wheel, nav arrows / RGI | ✅ largely | Same cluster, same BAP NavSD block |
| Exact-stock Java isolation | method only | Different HMI; the approach is what the overlay needs |
| Continental FPK RE | 🔬 **high value** | Our frame rate is set at FPK setup; this is the line most likely to raise it |
| Direct-TS remux, `/dev/mlb` | ⛔ | No such device here — the one real divide |
| Most20 20 fps, AID matrix, MU1438 | ⛔ | Head-unit side |

## What this side can give back

- Proof the architecture works **without `/dev/mlb`** — decode on the unit, let the stock
  capture path carry it.
- The **`mdevpush` protocol incl. decoder init** ([PROTOCOL-MDEVPUSH.md](PROTOCOL-MDEVPUSH.md)).
  QNX `mm-renderer` is used well beyond this head unit.
- **The update rate is set at FPK setup** (`update rate set to 10`; 1 and 0 seen in other
  states), applied by DisplayManager on the head-unit side. Same cluster upstream
  researches, observed from a different head unit.
- **QNX Screen capture constraints** ([ARCHITECTURE.md](ARCHITECTURE.md)): overlay planes
  never reach the writeback buffer; a video-plane window generates no composition event.

## Sequencing

Forked items are not picked up as they appear. Current feature stable → overlay gone →
then view control, wheel input, navigation widgets.

Downstream fork, not a competitor. Credits in [../CREDITS.md](../CREDITS.md).
