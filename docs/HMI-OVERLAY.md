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
called from it — a dead end.

They looked at first like a route for *external* navigation data, and therefore a way to
drive native cluster arrows. Decompiling the image says otherwise: `ExboxGuidanceListener`
carries a single `GuidanceState` (`ACTIVE` / `INACTIVE`). It arbitrates **who is
navigating**, the phone or the built-in map. No manoeuvre data passes through it.

## Writing to the system partition

The jar lives on the read-only root. Two things cost real time here:

- `mount -u -o rw /dev/hd0t177 /` makes **existing files writable**. Creating new ones
  still fails, and it fails with `No such file or directory` rather than a read-only
  error, which reads like a wrong path.
- **The remount does not survive a reboot.** Redo it before every write, or the copy
  fails with that same misleading message.

Keep a copy of the stock jar before writing, on the separate writable partition
(`/tsd/var/`), not on root.


## Raising the cluster frame rate

The same override jar carries this too. The cluster asks for a *mode*, and the head unit
picks the number:

```java
// de.vw.mib.asl.internal.mostkombi.streamsink.usecases.ChangeDataRateSequence
case 2: getDisplayManagementService().setDataFrameRate(10);   // map visible
```

It is a `bipush`, so the ceiling is one byte and anything up to 127 fits. Nothing else in
that class pushes 10, which is what makes the site safe to find.

```bash
tools/make-fps-patch.py ChangeDataRateSequence.class 30
tools/set-cluster-fps.sh ChangeDataRateSequence.patched.class
# reboot, then: tools/set-cluster-fps.sh off   to go back
```

The class comes from your own unit — `/tsd/hmi/ifs/MIBHMI.jxe` converted with jxe2jar.
Unlike `CarPlayModeHandling`, this one is not already in the jar, so it is added: the jar
is downloaded, edited here, and written back whole, and `set-cluster-fps.sh` reads it back
afterwards and compares.

**Untested.** The constant is reachable; whether the cluster and the MOST link accept more
than 10 is a separate question nobody has answered on MST2. If it does not, the picture
may stutter or stop rather than politely stay at 10 — so try it parked, not on a drive.
