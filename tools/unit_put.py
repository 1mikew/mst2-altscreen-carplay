#!/usr/bin/env python3
"""Upload file(s) to the head unit over FTP.

    tools/unit_put.py <local_file> [...] --to /tmp
Env: UNIT_HOST (192.168.1.4), UNIT_USER, UNIT_PASS
"""
import os, sys, ftplib, argparse, posixpath

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--to", default="/tmp")
    a = ap.parse_args()
    host = os.environ.get("UNIT_HOST", "192.168.1.4")
    user = os.environ.get("UNIT_USER", "root")
    pw   = os.environ.get("UNIT_PASS", "root")
    f = ftplib.FTP()
    f.connect(host, 21, timeout=20)
    f.login(user, pw)
    # vytvor cilovy adresar (po castech, chyby ignoruj)
    parts = [p for p in a.to.strip("/").split("/") if p]
    f.cwd("/")
    for p in parts:
        try: f.mkd(p)
        except ftplib.error_perm: pass
        f.cwd(p)
    for path in a.files:
        name = posixpath.basename(path)
        with open(path, "rb") as fh:
            f.storbinary("STOR " + name, fh, blocksize=32768)
        print("nahrano %s -> %s/%s (%d B)" % (path, a.to, name, os.path.getsize(path)))
    f.quit()
    return 0

if __name__ == "__main__":
    sys.exit(main())
