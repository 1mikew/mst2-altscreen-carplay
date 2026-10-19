# Removing the "navigation is running on the phone" overlay

During CarPlay route guidance the cluster used to cover the picture with its own
notice, which made the whole feature useless on a real drive. It is gone.

**No vendor file is distributed here.** What follows describes where the behaviour comes
from and which single instruction changes it, on a unit you own.

## Where it comes from

`/tsd/hmi/runHMI.sh` prepends an override jar to the HMI's bootclasspath:

```
-Xbootclasspath/p:$MIBJAR/NavActiveIgnore.jar
```

Classes in that jar win over the ones compiled into `MIBHMI.jxe` (42 MB). On this unit the
jar already carries `de.vw.mib.asl.internal.carplay.common.CarPlayModeHandling`, so the
whole image never has to be touched — 7.6 kB does it.

`CarPlayModeHandling.handleModeChanges` decides what kind of navigation is running:

```java
int navType = getNavigationType(appStates);   // 1 = none, 2 = CarPlay, 3 = built-in
if (navType == 2 && prevNav != 2) {
    aslPropertyManager.valueChangedBoolean(963062784, true);
    properties.setActiveNavigation(2);
}
```

## What works, and what does not

| Attempt | Change | Result |
|---|---|---|
| A | property `963062784` forced to `false` (`iconst_1` → `iconst_0`) | **No effect.** Whatever drives the cluster state does not read this property |
| B | `getNavigationType` returns 1 instead of 2 (`iconst_2` → `iconst_1`) | **Works.** The overlay is gone and route guidance is visible |

B puts the HMI into its ordinary "no navigation" path rather than inventing a new state,
and it is a one-byte edit: exactly one instruction differs from stock, confirmed by
disassembling both.

`navServices` and `ExboxGuidanceListenerImpl` are fields of that class but are never
called from it — a dead end worth skipping.

## Writing to the system partition

The jar lives on the read-only root. Two things cost real time here:

- `mount -u -o rw /dev/hd0t177 /` makes **existing files writable**. Creating new ones
  still fails, and it fails with `No such file or directory` rather than a read-only
  error, which reads like a wrong path.
- **The remount does not survive a reboot.** Redo it before every write, or the copy
  fails with that same misleading message.

Keep a copy of the stock jar before writing, on the separate writable partition
(`/tsd/var/`), not on root.
