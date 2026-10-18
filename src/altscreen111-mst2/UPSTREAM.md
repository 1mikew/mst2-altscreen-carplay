# Upstream

The files in this directory are a fork of the GEN2 ScreenAlt work from

**<https://github.com/harman-f/mhi2_altscreen_carplay>** — GPL-3.0-or-later

adapted to MIB2 Standard (built with `-DMST2`).

| file | origin |
|---|---|
| `libaltscreen111_gen2.c` | upstream, with MST2 patches (persistent marker directory, the cockpit sink branch in the output worker) |
| `include/alt111.h` | upstream |
| `src/alt111_profile.c`, `alt111_control.c`, `alt111_video.c`, `alt111_resync.c` | upstream |
| `src/alt111_trace.c` | **this project** — IPC tap used to recover the push protocol |
| `src/alt111_vc111.c` | **this project** — the cockpit sink: own mm-renderer context, decoder init, watchdog |

Upstream files keep their original comments and style. Changes made here are marked in
place and explained in `docs/`.
