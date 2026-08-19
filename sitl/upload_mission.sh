#!/bin/bash
# Upload a mission to a SITL vehicle via MAVProxy (port 14577).
# Requires launch_mavproxy.sh to be running.
#
# Usage:
#   ./sitl/upload_mission.sh                        # open GUI selector, then upload
#   ./sitl/upload_mission.sh <sysid>                # GUI pre-filled with sysid
#   ./sitl/upload_mission.sh <sysid> <mission_file> # direct upload, no GUI

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source "$HOME/venv-ardupilot/bin/activate"

if [[ $# -eq 2 ]]; then
    # Both sysid and file provided — skip GUI
    python3 sitl/upload_mission.py --sysid "$1" "$2"
    exit $?
fi

# Open GUI selector; on OK it prints "<sysid> <mission_path>" to stdout
SELECTION=$(python3 sitl/select_mission.py "$@")
if [[ -z "$SELECTION" ]]; then
    echo "[upload] Cancelled."
    exit 0
fi

SYSID=$(echo "$SELECTION" | awk '{print $1}')
MISSION=$(echo "$SELECTION" | awk '{print $2}')
echo "[upload] SYSID=$SYSID  mission=$(basename "$MISSION")"
python3 sitl/upload_mission.py --sysid "$SYSID" "$MISSION"
