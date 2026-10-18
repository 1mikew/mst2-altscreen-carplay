#!/usr/bin/env python3
"""Build an avcC (AVCDecoderConfigurationRecord) from an Annex-B H.264 file.

The avcC is what the decoder initialisation sequence carries: it tells the engine the
profile and level and supplies SPS+PPS out of band. It can be assembled deterministically
from a capture, so it never has to be sniffed.

Used to produce the fallback prologue; at runtime the library builds the record from the
live stream instead. See docs/PROTOCOL-MDEVPUSH.md.

  tools/mk-avcc.py captures/t111_1024x384.h264 build/t111.avcc
"""
import sys

def nals(buf):
    """Vrati (typ, bajty) pro kazdy NAL v Annex-B toku."""
    i, n = 0, len(buf)
    starts = []
    while i + 3 <= n:
        if buf[i] == 0 and buf[i+1] == 0 and buf[i+2] == 1:
            starts.append(i + 3); i += 3
        else:
            i += 1
    for k, s in enumerate(starts):
        e = starts[k+1] - 3 if k + 1 < len(starts) else n
        while e > s and buf[e-1] == 0:          # zero_byte pred dalsim start kodem
            e -= 1
        if e > s:
            yield buf[s] & 0x1f, buf[s:e]

def main():
    if len(sys.argv) < 2:
        print(__doc__); return 2
    buf = open(sys.argv[1], 'rb').read()
    sps = pps = None
    for t, d in nals(buf):
        if t == 7 and sps is None: sps = d
        if t == 8 and pps is None: pps = d
        if sps and pps: break
    if not sps or not pps:
        print("nenalezeno SPS/PPS", file=sys.stderr); return 1

    a = bytearray()
    a += bytes([1, sps[1], sps[2], sps[3]])     # verze, profil, kompatibilita, level
    a += bytes([0xff])                          # 6b reserved + lengthSizeMinusOne=3 (4B delky)
    a += bytes([0xe1])                          # 3b reserved + numOfSPS=1
    a += len(sps).to_bytes(2, 'big') + sps
    a += bytes([1])                             # numOfPPS=1
    a += len(pps).to_bytes(2, 'big') + pps

    print("SPS (%d B): %s" % (len(sps), sps.hex()))
    print("PPS (%d B): %s" % (len(pps), pps.hex()))
    print("profil=0x%02x kompatibilita=0x%02x level=%d (%.1f)"
          % (sps[1], sps[2], sps[3], sps[3] / 10.0))
    print("avcC (%d B): %s" % (len(a), a.hex()))
    if len(sys.argv) > 2:
        open(sys.argv[2], 'wb').write(bytes(a))
        print("zapsano: %s" % sys.argv[2])
    return 0

if __name__ == '__main__':
    sys.exit(main())
