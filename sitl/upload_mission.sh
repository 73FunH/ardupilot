#!/bin/bash
# Upload a mission to the target vehicle via MAVLink (pymavlink direct).
# Requires mavproxy bridge to be running (launch_mavproxy.sh).
#
# Usage:
#   ./sitl/upload_mission.sh              # defaults to plane
#   ./sitl/upload_mission.sh plane        # explicit type
#   ./sitl/upload_mission.sh copter       # copter mission
#   ./sitl/upload_mission.sh path/to/file.waypoints  # explicit file path

# --- Mission file selection ---
MISSION_PLANE="sitl/target_plane/mission_double_rect.waypoints"
MISSION_COPTER="sitl/target_copter/mission_double_rect_bow.waypoints"
# -----------------------------

TARGET="${1:-plane}"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source "$HOME/venv-ardupilot/bin/activate"

# If the argument is an existing file, use it directly; otherwise select by type.
if [[ -f "$TARGET" ]]; then
    MISSION="$TARGET"
elif [[ "$TARGET" == "copter" ]]; then
    MISSION="$MISSION_COPTER"
elif [[ "$TARGET" == "plane" ]]; then
    MISSION="$MISSION_PLANE"
else
    echo "Unknown vehicle type '$TARGET'. Use 'plane', 'copter', or a file path." >&2
    exit 1
fi

python3 sitl/upload_mission.py "$MISSION"
