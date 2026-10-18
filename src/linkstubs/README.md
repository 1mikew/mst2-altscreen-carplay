# Link stubs

The build links against two libraries from the head unit:

```
/usr/lib/libmmrndclient.so.1    QNX mm-renderer client
/usr/lib/libstrm.so.1
```

They are **vendor firmware components and are not redistributed here.** They are used only
to resolve symbols at link time; nothing from them ends up in the build output.

Fetch them from your own unit:

```bash
tools/pull-linkstubs.sh
```
