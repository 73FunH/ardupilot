#!/bin/bash
# Launch target_copter SITL only (SYSID 42, instance 1)
#   TCP MAVLink : 5770
#   UDP direct  : 14561 (direct QGC without mavproxy, debug only)
#   UDP GCS out : 14560 via launch_mavproxy.sh both_copter (normal workflow)

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source "$HOME/venv-ardupilot/bin/activate"

./Tools/autotest/sim_vehicle.py \
    -v ArduCopter -I 1 \
    --no-rebuild \
    --no-mavproxy \
    --aircraft=sitl/target_copter \
    --add-param-file=sitl/target_copter/target_copter.parm \
    --out=udp:127.0.0.1:14561 \
    -l 50.62371126136441,5.217642001585023,0,0
