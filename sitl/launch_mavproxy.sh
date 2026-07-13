#!/bin/bash
# Connect MAVProxy to both SITL instances.
# Run AFTER both SITL instances are up.
#
# Usage:
#   ./sitl/launch_mavproxy.sh            → connect to both planes/copters
#   ./sitl/launch_mavproxy.sh hunter     → hunter vehicle only (TCP 5760)
#   ./sitl/launch_mavproxy.sh target     → target vehicle only (TCP 5770)

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source "$HOME/venv-ardupilot/bin/activate"

# Detect WSL2: if so, forward to the Windows host; otherwise use localhost.
if grep -qi microsoft /proc/version 2>/dev/null; then
    GCS_IP=$(ip route show default | awk '{print $3}')
    echo "[mavproxy] WSL2 detected — forwarding to Windows host at $GCS_IP"
else
    GCS_IP=127.0.0.1
    echo "[mavproxy] Native Linux — forwarding to $GCS_IP"
fi

case "${1:-both}" in
    hunter)
        mavproxy.py \
            --master=tcp:127.0.0.1:5760 \
            --out=udp:"$GCS_IP":14550
        ;;
    target)
        mavproxy.py \
            --master=tcp:127.0.0.1:5770 \
            --out=udp:"$GCS_IP":14550
        ;;
    both|*)
        mavproxy.py \
            --master=tcp:127.0.0.1:5760 \
            --master=tcp:127.0.0.1:5770 \
            --out=udp:"$GCS_IP":14550 \
            --out=udp:"$GCS_IP":14560 \
            --out=udpin:0.0.0.0:14577
        ;;
esac
