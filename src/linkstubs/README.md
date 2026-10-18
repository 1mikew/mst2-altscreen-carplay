# Link stubs

The hook calls into two head-unit libraries:

```
libmmrndclient.so.1    QNX mm-renderer client
libstrm.so.1
```

**Neither is redistributed here.** `build.sh` generates stub libraries from
`mmrndclient_stub.c` and `strm_stub.c`, which define only the twelve symbols the hook
references. That is enough to link.

The stubs never reach the vehicle. On the unit the dynamic linker binds to the real
libraries, because the SONAMEs match.

If you would rather link against the real ones, fetch them from your own unit with
`tools/pull-linkstubs.sh` — the build prefers them when present.
