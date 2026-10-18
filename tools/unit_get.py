#!/usr/bin/env python3
"""Download a file from the head unit over FTP.  tools/unit_get.py /remote/path [local]"""
import os, sys, ftplib, posixpath
def main():
    if len(sys.argv) < 2:
        print("usage: unit_get.py /remote/path [local]", file=sys.stderr); return 2
    rem = sys.argv[1]
    loc = sys.argv[2] if len(sys.argv) > 2 else posixpath.basename(rem)
    f = ftplib.FTP(); f.connect(os.environ.get("UNIT_HOST","192.168.1.4"), 21, timeout=30)
    f.login(os.environ.get("UNIT_USER","root"), os.environ.get("UNIT_PASS","root"))
    with open(loc, "wb") as fh:
        f.retrbinary("RETR " + rem, fh.write, blocksize=32768)
    f.quit()
    print("got %s -> %s (%d B)" % (rem, loc, os.path.getsize(loc)))
    return 0
if __name__ == "__main__": sys.exit(main())
