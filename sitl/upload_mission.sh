#!/bin/bash
# Upload the target_plane mission via MAVLink (pymavlink direct).
# Requires mavproxy bridge to be running (launch_mavproxy.sh both).
# Can be run at any time alongside QGC or other GCS apps.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source "$HOME/venv-ardupilot/bin/activate"

python3 sitl/upload_mission.py
