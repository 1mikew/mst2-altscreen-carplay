#!/usr/bin/env python3
"""Run a command on the head unit over telnet and return its output.

Usage:
    tools/unit.py "ls -l /tmp"            # a single command
    tools/unit.py -f script.sh            # send a file line by line
    tools/unit.py --probe                 # just check reachability and login

Host and credentials come from the environment:
    UNIT_HOST (default 192.168.2.1), UNIT_PORT (23), UNIT_USER, UNIT_PASS

This is a minimal telnet client of its own: macOS no longer ships telnet, and `nc`
trips over IAC negotiation.
"""
import os, socket, sys, time, argparse

IAC, DONT, DO, WONT, WILL, SB, SE = 255, 254, 253, 252, 251, 250, 240

class Telnet:
    def __init__(self, host, port, timeout=10.0):
        self.s = socket.create_connection((host, port), timeout=timeout)
        self.s.settimeout(timeout)
        self.buf = b""

    def _filter(self, data):
        """Odstran IAC sekvence; na DO/WILL odpovez odmitnutim (WONT/DONT)."""
        out, reply, i = b"", b"", 0
        while i < len(data):
            b0 = data[i]
            if b0 != IAC:
                out += data[i:i+1]; i += 1; continue
            if i + 1 >= len(data): break
            cmd = data[i+1]
            if cmd in (DO, DONT, WILL, WONT):
                if i + 2 >= len(data): break
                opt = data[i+2]
                # odmitni vsechny volby
                reply += bytes([IAC, WONT if cmd == DO else DONT, opt]) if cmd in (DO, DONT) \
                         else bytes([IAC, DONT, opt])
                i += 3
            elif cmd == SB:
                j = data.find(bytes([IAC, SE]), i)
                i = (j + 2) if j >= 0 else len(data)
            elif cmd == IAC:
                out += b"\xff"; i += 2
            else:
                i += 2
        if reply:
            try: self.s.sendall(reply)
            except OSError: pass
        return out

    def read_until(self, patterns, timeout=15.0):
        if isinstance(patterns, (bytes, str)): patterns = [patterns]
        pats = [p.encode() if isinstance(p, str) else p for p in patterns]
        end = time.time() + timeout
        while time.time() < end:
            for p in pats:
                k = self.buf.find(p)
                if k >= 0:
                    got, self.buf = self.buf[:k+len(p)], self.buf[k+len(p):]
                    return got, p
            try:
                self.s.settimeout(max(0.3, end - time.time()))
                d = self.s.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            if not d: break
            self.buf += self._filter(d)
        return self.buf, None

    def send(self, line):
        self.s.sendall(line.encode() + b"\r\n")

    def close(self):
        # DULEZITE: korektne se odhlasit, jinak telnetd neuvolni pty a dalsi spojeni
        # skonci na "login_tty: Operation not permitted" (QNX ma omezeny pocet pty).
        try:
            self.s.sendall(b"exit\r\n")
            time.sleep(0.25)
        except OSError:
            pass
        try: self.s.close()
        except OSError: pass


def login(host, port, user, passwd, timeout=15.0):
    t = Telnet(host, port, timeout)
    out, hit = t.read_until(["login:", "Login:", "username:", "$ ", "# "], timeout)
    if hit and hit.lower().endswith(b"login:") or (hit and b"username" in hit.lower()):
        t.send(user)
        out2, hit2 = t.read_until(["Password:", "password:", "$ ", "# "], timeout)
        if hit2 and b"assword" in hit2:
            t.send(passwd)
            t.read_until(["$ ", "# ", "login:"], timeout)
    return t


def run(t, cmd, timeout=60.0):
    """Send a command and return (output, rc).

    NOTE: telnetd echoes back whatever we type. The end marker is therefore SPLIT in the
    command itself ("R" "C_END") so the echo never contains it whole -- only the real
    output does. The unit's prompt is 'imx6:/# '.
    """
    t.send('%s; echo "R""C_END=$?"' % cmd)
    out, hit = t.read_until(["RC_END="], timeout)
    text = out.decode("utf-8", "replace").replace("\r", "")
    rcline, _ = t.read_until(["\n"], 5.0)
    rc = rcline.decode("utf-8", "replace").strip()
    t.read_until(["# "], 3.0)          # drain the prompt so the next command starts clean
    lines = text.split("\n")
    if lines and ('C_END=$?' in lines[0] or lines[0].strip().startswith(cmd[:25])):
        lines = lines[1:]              # drop the echo of our own command
    lines = [l for l in lines if 'RC_END' not in l]
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines).strip(), rc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", nargs="?", default=None)
    ap.add_argument("-f", "--file", help="send commands from a file")
    ap.add_argument("--probe", action="store_true")
    ap.add_argument("--raw", action="store_true", help="vypis hrubou session (diagnostika)")
    ap.add_argument("--timeout", type=float, default=60.0)
    a = ap.parse_args()

    host = os.environ.get("UNIT_HOST", "192.168.2.1")
    port = int(os.environ.get("UNIT_PORT", "23"))
    user = os.environ.get("UNIT_USER", "root")
    pw   = os.environ.get("UNIT_PASS", "root")

    try:
        t = login(host, port, user, pw, timeout=min(15.0, a.timeout))
    except OSError as e:
        print("UNREACHABLE unit %s:%d (%s)" % (host, port, e), file=sys.stderr)
        return 3

    try:
        if a.raw:
            t.send("uname -a")
            time.sleep(1.5)
            d, _ = t.read_until(["\x00NEVER\x00"], 2.5)
            sys.stdout.write(repr(d.decode("utf-8", "replace")) + "\n")
            return 0
        if a.probe:
            out, rc = run(t, "uname -a; echo PWD=$PWD; id", a.timeout)
            print(out); print("[rc=%s]" % rc)
        elif a.file:
            for line in open(a.file):
                line = line.strip()
                if not line or line.startswith("#"): continue
                out, rc = run(t, line, a.timeout)
                print("$ %s\n%s\n[rc=%s]" % (line, out, rc))
        elif a.cmd:
            out, rc = run(t, a.cmd, a.timeout)
            print(out)
            if rc not in ("0", ""): print("[rc=%s]" % rc, file=sys.stderr)
        else:
            print("nic k provedeni (viz --help)", file=sys.stderr); return 2
    finally:
        t.close()
    return 0

if __name__ == "__main__":
    sys.exit(main())
