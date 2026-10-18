# Credits

## harman-f/mhi2_altscreen_carplay

<https://github.com/harman-f/mhi2_altscreen_carplay> — GPL-3.0-or-later

**The project this is forked from.** It established that the CarPlay cluster view can be
driven on VW Group head units at all, and did the protocol work: Type-111 alt screen,
`suggestUI` / `showUI`, AirPlay key derivation for the screen stream, keyframe policy.

Reused here:

- `libaltscreen111_gen2.c` and the `alt111_*` modules — a **fork of its GEN2 ScreenAlt
  work**, adapted with `-DMST2`. See `src/altscreen111-mst2/UPSTREAM.md`.
- Alt-screen advertising and session handling.
- The D2 keyframe policy and the `alt111-dump` capture helper.

New here: everything below the stream. On MHI2 the H.264 goes straight to `/dev/mlb` and
the cluster decodes it — impossible on MIB2 Standard. The decoding path, the `mdevpush`
protocol including decoder initialisation, and the QNX Screen output handling are this
project's own.

## omonob/MHI2-Carplay-Maps

<https://github.com/omonob/MHI2-Carplay-Maps> — GPL-3.0-or-later

Mature MHI2 solution (`altscreen-most-bridge`, `carplay-cluster-supervisor`). Ships
binaries, so nothing was copied — but its component layout confirmed that the cluster
decodes H.264 itself, which is what made the platform difference clear.

## yuedizhibo/MHI2Q-CarPlay-AltScreen

<https://github.com/yuedizhibo/MHI2Q-CarPlay-AltScreen>

Cross-check on the protocol side. Platform-specific parts do not transfer.

## Toolchain

- **QNX 6.5 ARMv7 cross toolchain** — public `qnx65-armv7-toolchain` image (luka-dev).
- **jxe2jar** (luka-dev) and **Vineflower** for HMI research.

## Platform documentation

QNX Neutrino 6.5 and QNX Screen, for `mm-renderer`, `screen:` output URLs and window
properties. The relevant `screen.h` constants are not shipped on the target and were
recovered from `screen_writer.so`.

## Method

Where a conclusion was later disproved by measurement, the correction is stated rather
than dropped — see [docs/FINDINGS.md](docs/FINDINGS.md). Trust the measurements.
