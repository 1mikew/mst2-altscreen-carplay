# Link stubs

`libmmrndclient.so.1` (QNX mm-renderer client) and `libstrm.so.1` are taken from the head
unit and used only to satisfy the linker when building the hook. They are not
redistributable parts of this project — they belong to the platform vendor and are kept
here purely so the build is reproducible.

If you prefer not to rely on them, copy the same files off your own unit:

```
/usr/lib/libmmrndclient.so.1
/usr/lib/libstrm.so.1
```
