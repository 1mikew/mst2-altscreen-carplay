# Developer install

**Read the READ FIRST block in [../README.md](../README.md).** Work in progress, no
packaged install, your own car, your own risk — including **voiding your warranty**.

## Prerequisites

- Škoda Amundsen 8", part `5Q0035874C` — MIB2 Standard "MST2", firmware
  `MST2_EU_SK_ZR_P0480T`. Other units and builds are intended but untested — there is no
  second unit to try them on.
- Virtual Cockpit **AID 10", part `5E0920790A`** — the only cluster this is tested against.
- Shell access (telnet) and FTP on the unit.
- Docker, for the QNX 6.5 ARMv7 toolchain.
- iPhone with CarPlay and a navigation app.

```bash
sudo ifconfig <iface> inet 192.168.1.10 netmask 255.255.255.0 up
```

The tools default to `192.168.1.4` for the unit; override with `UNIT_HOST=x.x.x.x`.

## Build

```bash
./build.sh
```

→ `build/mst2/libaltscreen111.so`, `build/mst2/alt111-dump`

## Install

```bash
tools/deploy.sh
```

Copies the library to `/tsd/lib/mibr/` and reboots. It does **not** touch `cpu.conf` —
add this once by hand in the `service iMX6.SAL` block (`/tsd/etc/system/cpu.conf`, ~line 607):

```
envar LD_PRELOAD /lib/libmmappriofix.so.1:/tsd/lib/mibr/libaltscreen111.so
```

Needs the system partition remounted read-write (`util_mount.sh` / `util_mount_ro.sh`).
**Back the file up first.** Verify after the reboot:

```bash
tools/unit.py "pidin -p tsd.mibstd2.sal.main mem | grep altscreen"
```

## Configure

```bash
tools/persist.sh        # survives reboot, enables the keyframe policy
tools/set-output.sh …   # experiments: writes to /tmp, wins, cleared on reboot
tools/set-safearea.sh … # which part of the cluster canvas the phone may draw in
tools/set-surface.sh …  # map only, or map plus the manoeuvre card
tools/make-splash.py    # build a keyframe of our own
tools/set-splash.sh     # ... and put it on the unit (leave it off to keep stock behaviour)
tools/set-on-disconnect.sh …  # keep the last frame, show the splash, or release the cockpit
tools/make-fps-patch.py …     # raise the cluster frame rate (HMI class, needs a reboot)
tools/set-cluster-fps.sh …    # ... and put it in the override jar, or take it out
```

Nothing has to be exported from the unit for this. The decoder initialisation is built
from the live stream at runtime; the fallback prologue needs a capture of your own and is
skipped if you do not have one.

## Run

Connect the iPhone, start a navigation app, make sure the **map is active on the cockpit** —
DisplayManager only captures while streaming to the cluster.

```bash
tools/status.sh
```

Expected: `cpvc111` and `SalTechnology::CarPlay` both present, `capture buffer = win-N`
(not `(none)`), composition above ~10 fps.

## Kill switch and uninstall

```bash
tools/disable.sh [permanent|off]
tools/restore-stock.sh
```

Full uninstall: also delete `/tsd/lib/mibr/libaltscreen111.so`, remove the
`:/tsd/lib/mibr/libaltscreen111.so` suffix from `cpu.conf`, reboot.

## Rules learned the hard way

| | |
|---|---|
| **Never `slay` SAL** | `restart global 3` — the watchdog takes the whole unit down. Use `util_reboot.sh`. |
| **Never log to a file on a hot IPC path** | An early tracer wrote one line per message and delayed SAL until the watchdog fired. Filter by coid, buffer in memory, flush once. |
| Cockpit misbehaving? | **Switch the cockpit view, do not reboot.** |
| `/tmp` is RAM | `dev/shmem`, cleared on reboot — session-local changes are one reboot from stock. |
| No `dd` on the unit | Use `cat`. |
