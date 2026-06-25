#!/bin/bash
# Upload a mission via MAVLink (pymavlink direct).
# Requires mavproxy bridge to be running (launch_mavproxy.sh both).
# Can be run at any time alongside QGC or other GCS apps.
#
# Usage:
#   ./sitl/upload_mission.sh                          # uses MISSION below
#   ./sitl/upload_mission.sh path/to/file.waypoints   # explicit file override

MISSION="sitl/target_plane/mission_double_rect.waypoints"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source "$HOME/venv-ardupilot/bin/activate"

python3 sitl/upload_mission.py "${1:-$MISSION}"
