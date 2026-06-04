#!/bin/bash
# Upload the target_plane mission via MAVProxy (connects, uploads, disconnects).
# Run from the repo root after both SITL instances are up.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source /home/postiau/venv-ardupilot/bin/activate

MISSION="sitl/target_plane/mission.waypoints"

if [ ! -f "$MISSION" ]; then
    echo "[upload_mission] ERROR: mission file not found: $MISSION"
    exit 1
fi

echo "[upload_mission] Uploading mission to target_plane (SYSID 52, TCP 5770)..."
mavproxy.py \
    --master=tcp:127.0.0.1:5770 \
    --target-system=52 \
    --logfile=/dev/null \
    --cmd="wp load $MISSION; wp list; exit"

echo "[upload_mission] Done."
