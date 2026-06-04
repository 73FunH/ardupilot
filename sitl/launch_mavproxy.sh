#!/bin/bash
# Connect MAVProxy to both SITL instances.
# Run AFTER both SITL instances are up.
#
# Usage:
#   ./sitl/launch_mavproxy.sh            → connect to both planes
#   ./sitl/launch_mavproxy.sh hunter     → hunter_plane only (TCP 5760)
#   ./sitl/launch_mavproxy.sh target     → target_plane only (TCP 5770)

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source /home/postiau/venv-ardupilot/bin/activate

case "${1:-both}" in
    hunter)
        mavproxy.py \
            --master=tcp:127.0.0.1:5760 \
            --out=udp:127.0.0.1:14550
        ;;
    target)
        mavproxy.py \
            --master=tcp:127.0.0.1:5770 \
            --out=udp:127.0.0.1:14550
        ;;
    both|*)
        mavproxy.py \
            --master=tcp:127.0.0.1:5760 \
            --master=tcp:127.0.0.1:5770 \
            --out=udp:127.0.0.1:14550 \
            --out=udp:127.0.0.1:14560
        ;;
esac
