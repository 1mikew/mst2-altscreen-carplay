# The `mdevpush` protocol

Undocumented. Recovered by interposing SAL's IPC and disassembling `mdev_streamer.so`,
then verified against a working decode.

`mdev_streamer.so` is a `name_attach` server, not a resource manager. Connect with
`name_open("<basename>")` — `open()` on the full path gives an I/O connection that rejects
raw messages with `EINVAL`.

## Header

24 bytes. The consumer reads **only three fields** (`pushmode_read_pkthdr`):

| offset | type | meaning |
|---|---|---|
| `0x00` | u16 | message code |
| `0x10` | u32 | subtype |
| `0x14` | u32 | payload length |

Everything else is **stack garbage** in SAL's own messages. Fill with zeros.

| code | meaning |
|---|---|
| `< 0x100` | data |
| `0x100` | QNX connect message — rejected |
| `0x101 … 0x1FF` | QNX I/O messages — rejected |

`pushmode_read_pktdata` branches on subtype:

- **3** → 8-byte PTS at `0x18`, payload at `0x20`, length `len − 8`
- **anything else** → payload at `0x18`

## Video frames

```
[24B header][8B PTS][AVCC NAL]      three IOV parts, one NAL per message

u16 @0x00 = 0                       data
u32 @0x10 = 3                       subtype 3 = data with PTS
u32 @0x14 = 8 + 4 + len(NAL)
u64 @0x18 = PTS, microseconds, monotonic
     @0x20 = 4-byte BIG-ENDIAN length, then the NAL
```

Send with `MsgSendvs_r` or `MsgSendv`.

## Decoder initialisation

**There is no "format" message type.** Three ordinary *data* messages with subtypes other
than 3, before the first frame:

| subtype | length | payload |
|---|---|---|
| **5** | 4 B | `01 00 00 00` — start / flush |
| **2** | 32 B | `02000000` + fourcc `AVC1` (LE) + width + height + depth (16) + fps (30) + two reserved words |
| **4** | *n* + 4 | **`avcC`** followed by `02 00 00 00` |

Without these the engine takes exactly three NALs (SPS, PPS, IDR) and fails with
`error::5 = UNSUPPORTED_MEDIA_TYPE`. In-band parameter sets are not enough.

### Building the `avcC`

Do **not** reuse a stored record. The configuration the hook hands over is a different
layout (first byte is not `0x01`), and a stale `avcC` from an old capture gives a **black
picture with no error** once the phone negotiates different parameters.

Collect SPS and PPS from the incoming Annex-B units — they do **not** necessarily arrive
with the IDR — and assemble:

```
01 <profile> <compat> <level> FF E1 <2B SPS len> <SPS> 01 <2B PPS len> <PPS>
```

`tools/mk-avcc.py` does this offline; the library does it at runtime.

## Measured stream

```
H.264 High (100), level 3.1, 4:2:0
64×24 macroblocks -> encoded 1024×384
crop right=7, bottom=4 -> visible 1010×376
one IDR per ~29 s
```

The main CarPlay stream is **also** High 3.1 — the profile was never the problem.
