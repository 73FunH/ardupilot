#!/bin/bash
# Launch QGroundControl for SITL testing
#
# Usage:
#   ./sitl/launch_qgc.sh

QGC_DIR="/home/postiau/Downloads/Autopilot_etc"
QGC_EXEC="$QGC_DIR/QGroundControl-x86_64.AppImage"

# Check if QGroundControl exists
if [ ! -f "$QGC_EXEC" ]; then
    echo "ERROR: QGroundControl not found at $QGC_EXEC"
    exit 1
fi

echo "[qgc] Launching QGroundControl from $QGC_EXEC"

chmod +x "$QGC_EXEC"

nohup "$QGC_EXEC" > /tmp/qgc.log 2>&1 &
disown $!
echo "[qgc] Started (PID $!) — terminal is free. Log: /tmp/qgc.log"
