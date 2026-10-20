# Steering-wheel zoom for the CarPlay map

The wheel still zooms the stock map. Making it zoom a third-party CarPlay map needs two
halves: notice the request, and act on it. The first half is solved; the second is not.

## Where the zoom request arrives

Not at the key panel. On MQB the cluster decides what the wheel means while it shows the
map, and sends the result to the head unit over **BAP NavSD `MapScale`** (function id 45),
which hands it to the built-in navigation:

```java
// de.vw.mib.bap.mqbab2.navsd.functions.MapScale
VALUE_ZOOM_IN = 1;               VALUE_ZOOM_OUT = -1;
VALUE_CONTINUOUS_ZOOM_IN = 127;  VALUE_CONTINUOUS_ZOOM_OUT = -128;
ZOOM_TYPE_STEP = 1;  ZOOM_TYPE_CONTINUOUS = 2;  ZOOM_TYPE_CONTINUOUS_STOP = 5;

navigationService.setMapScaleSteps(steps, autoZoom);   // steps in {-128,-1,0,1,127}
```

That is better than a key event: the intent is already decoded, and a short press is
already distinguished from a held button. Nothing has to be reconstructed from timing.

So the hook is a shadow of `MapScale` that keeps the stock call and additionally reports
the request when CarPlay owns the cluster.

## Getting it to the phone — unsolved

The alt screen is currently declared with **no input device at all**. `libaltscreen111_gen2.c`
clones the stock display and then:

```c
remove_key(alt,"primaryInputDevice");
```

which is why `/info` reports `input=none`. Until that changes, the phone has no reason to
accept anything. What to send after that is open, and is the real work: the stock value is
logged at startup (`stock display capability baseline`) and is the obvious starting point.

## Shape of the implementation

Split, so the Java side stays trivial and reversible:

| half | where | job |
|---|---|---|
| detect | HMI shadow class | see the request, send a short command over loopback UDP |
| act | our library, inside the SAL process | receive it, drive CarPlay |

The split is **[omonob](https://github.com/omonob/MHI2-Carplay-Maps)'s design** (GPL-3.0),
which this follows: their Java side emits plain ASCII strings — `zoom-in`, `zoom-out` — to
`127.0.0.1` and knows nothing about CarPlay. On MHI2 their detection half hooks the key
panel and reconstructs press length, which MST2 does not need.
