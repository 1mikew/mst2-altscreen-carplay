#!/usr/bin/env python3
"""Build the decoder initialisation sequence for an own mdevpush context.

Recovered from SAL and confirmed by disassembling `pushmode_read_pkthdr` and
`pushmode_read_pktdata` in mdev_streamer.so: there is NO format code in the header at
all. The configuration arrives as an ordinary DATA message, just with a subtype other
than 3 (which is data+PTS).

Order, before the first frame:
  subtype 5, 4 B   : 01000000                           - start / flush
  subtype 2, 32 B  : 02000000 'AVC1' w h depth fps 0 0  - format descriptor (LE)
  subtype 4, n+4   : avcC + 02000000                    - codec configuration

Header: u16@0x00 = 0, u32@0x10 = subtype, u32@0x14 = payload length. Fields
0x04/0x08/0x0c are stack garbage in SAL's own messages and the consumer never reads
them, so they are zeroed here.

  tools/mk-init.py build/t111.avcc build/cpvc_111.prologue 1024 384
"""
import sys

def msg(subtype, payload):
    h = bytearray(24)
    h[0x00:0x02] = (0).to_bytes(2, 'little')        # code = DATA
    h[0x10:0x14] = subtype.to_bytes(4, 'little')
    h[0x14:0x18] = len(payload).to_bytes(4, 'little')
    return bytes(h) + payload

def main():
    if len(sys.argv) < 3:
        print(__doc__); return 2
    avcc = open(sys.argv[1], 'rb').read()
    out  = sys.argv[2]
    w    = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    h    = int(sys.argv[4]) if len(sys.argv) > 4 else 384
    depth, fps = 16, 30
    le = lambda v: int(v).to_bytes(4, 'little')

    desc = le(2) + b'AVC1'[::-1] + le(w) + le(h) + le(depth) + le(fps) + le(0) + le(0)
    cfg  = avcc + le(2)

    zpravy = [msg(5, le(1)), msg(2, desc), msg(4, cfg)]
    open(out, 'w').write('\n'.join(m.hex() for m in zpravy) + '\n')

    print("avcC %d B: profil 0x%02x, level %d, delka_NAL %d, SPS %d B, PPS %d B"
          % (len(avcc), avcc[1], avcc[3], (avcc[4] & 3) + 1,
             int.from_bytes(avcc[6:8], 'big'),
             int.from_bytes(avcc[6+2+int.from_bytes(avcc[6:8],'big')+1:][:2], 'big')))
    print("deskriptor: %dx%d, hloubka %d, %d fps" % (w, h, depth, fps))
    for i, m in enumerate(zpravy, 1):
        print("  zprava %d: subtype=%d, payload %d B" %
              (i, int.from_bytes(m[0x10:0x14], 'little'),
               int.from_bytes(m[0x14:0x18], 'little')))
    print("zapsano: %s" % out)
    return 0

if __name__ == '__main__':
    sys.exit(main())
