# Shared helpers for tools/*.sh. These run on your workstation and drive the head
# unit over telnet (control) and FTP (file transfer).
UNIT_HOST="${UNIT_HOST:-192.168.1.4}"
export UNIT_HOST
R="$(cd "$(dirname "$0")/.." && pwd)"
need_link() {
    if ! nc -z -w 3 "$UNIT_HOST" 23 2>/dev/null; then
        echo "Head unit unreachable at $UNIT_HOST:23."
        echo "1) Connect the USB-Ethernet adapter and the cable to the unit."
        echo "2) Find the interface:  ifconfig -l"
        echo "3) Set a static address (needs your password):"
        echo "     sudo ifconfig <en?> inet 192.168.1.10 netmask 255.255.255.0 up"
        echo "4) Telnet must be enabled on the unit."
        exit 1
    fi
}
u()  { "$R/tools/unit.py" "$@"; }
up() { "$R/tools/unit_put.py" "$@"; }
