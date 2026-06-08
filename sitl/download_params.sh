#!/bin/bash
# Download parameters from a vehicle via mavproxy's UDP service port (14577).
# Requires mavproxy bridge to be running (launch_mavproxy.sh both).

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source /home/postiau/venv-ardupilot/bin/activate

python3 sitl/download_params.py
