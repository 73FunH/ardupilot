#!/bin/bash
# Upload a mission to the target vehicle via MAVLink (pymavlink direct).
# Requires mavproxy bridge to be running (launch_mavproxy.sh).
# Mission file is resolved by convention: sitl/target_<type>/mission.waypoints
#
# Usage:
#   ./sitl/upload_mission.sh              # defaults to plane
#   ./sitl/upload_mission.sh plane        # explicit type
#   ./sitl/upload_mission.sh copter       # copter mission
#   ./sitl/upload_mission.sh path/to/file.waypoints  # explicit file path

TARGET="${1:-plane}"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source "$HOME/venv-ardupilot/bin/activate"

# If the argument is an existing file, use it directly; otherwise treat as type.
if [[ -f "$TARGET" ]]; then
    MISSION="$TARGET"
else
    MISSION="sitl/target_${TARGET}/mission_double_rect.waypoints"
fi

python3 sitl/upload_mission.py "$MISSION"
