# Captures

`t111_1024x384.h264` is a raw Annex-B capture of the CarPlay Type-111 instrument-cluster
stream, taken with `alt111-dump` on the vehicle. It is **not** in git — it is personal
driving data — but the measurements taken from it are:

```
H.264 High profile (100), level 3.1, 4:2:0
64x24 macroblocks  ->  encoded 1024x384
crop right=7, bottom=4  ->  visible 1010x376
one IDR per ~29 s
```

To make your own:

```bash
tools/unit_put.py build/mst2/alt111-dump --to /tmp
tools/unit.py "chmod 755 /tmp/alt111-dump; /tmp/alt111-dump /tmp/t111.h264 2 60 19820"
tools/unit_get.py /tmp/t111.h264 captures/t111.h264
```

The hook only produces the stream while a consumer is connected to `127.0.0.1:19820`.
