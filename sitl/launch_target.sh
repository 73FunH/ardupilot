#!/bin/bash
# Launch target_plane SITL only (SYSID 52, instance 1)
#   TCP MAVLink : 5770
#   UDP GCS out : 14550 (shared with hunter_plane, distinguished by SYSID)
#   Use launch_mavproxy.sh to attach a MAVProxy console.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source /home/postiau/venv-ardupilot/bin/activate

./Tools/autotest/sim_vehicle.py \
    -v ArduPlane -I 1 \
    --no-rebuild \
    --no-mavproxy \
    --aircraft=sitl/target_plane \
    --add-param-file=sitl/target_plane/target_plane.parm \
    --out=udp:127.0.0.1:14550 \
    -l 50.62371126136441,5.217642001585023,100,0
