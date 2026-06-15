#!/bin/bash
# Launch target_plane SITL only (SYSID 52, instance 1)
#   TCP MAVLink : 5770
#   UDP direct  : 14561 (direct QGC without mavproxy, debug only)
#   UDP GCS out : 14560 via launch_mavproxy.sh (normal workflow)

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source "$HOME/venv-ardupilot/bin/activate"

./Tools/autotest/sim_vehicle.py \
    -v ArduPlane -I 1 \
    --no-rebuild \
    --no-mavproxy \
    --aircraft=sitl/target_plane \
    --add-param-file=sitl/target_plane/target_plane.parm \
    --out=udp:127.0.0.1:14561 \
    -l 50.62371126136441,5.217642001585023,100,0
