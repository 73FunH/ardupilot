#!/bin/bash
# Launch hunter_plane SITL only (SYSID 51, instance 0)
#   TCP MAVLink : 5760
#   UDP GCS out : 14550 (shared with target_plane, distinguished by SYSID)
#   Use launch_mavproxy.sh to attach a MAVProxy console.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source /home/postiau/venv-ardupilot/bin/activate

./Tools/autotest/sim_vehicle.py \
    -v ArduPlane -I 0 \
    --no-rebuild \
    --no-mavproxy \
    --aircraft=sitl/hunter_plane \
    --add-param-file=sitl/hunter_plane/hunter_plane.parm \
    --out=udp:127.0.0.1:14550 \
    -l 50.62351828301441,5.217663644681113,100,0
