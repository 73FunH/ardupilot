#!/bin/bash
# Forward all SITL vehicles to QGC.
#
# Usage: ./sitl/launch_mavproxy.sh
#   Listens on shared UDP port 14540 for incoming MAVLink from any SITL vehicle
#   launched via launch_vehicle.sh, and forwards to QGC on UDP 14550.
#   Vehicles started at any time are picked up automatically — no restart needed.

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

echo "[mavproxy] Listening on UDP 14540 → QGC at $GCS_IP:14550/14560  (mission inject: 14577)"
mavproxy.py \
    --master=udpin:0.0.0.0:14540 \
    --out=udp:"$GCS_IP":14550 \
    --out=udp:"$GCS_IP":14560 \
    --out=udpin:0.0.0.0:14577
