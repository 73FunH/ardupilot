#!/bin/bash
# Launch two ArduPlane SITL instances in a single console (background processes).
#   hunter_plane  - SYSID 51 - instance 0 - TCP 5760
#   target_plane  - SYSID 52 - instance 1 - TCP 5770
# SITL instances use private debug ports (14551/14561) — use launch_mavproxy.sh
# which forwards both vehicles cleanly to QGC via UDP 14550 (hunter+target mixed,
# distinguished by SYSID) and UDP 14560 as an alternative output.
#
# Press Ctrl+C to stop both instances.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cleanup() {
    echo
    echo "[launch] Stopping all SITL instances..."
    kill "$PID_HUNTER" "$PID_TARGET" 2>/dev/null
    wait "$PID_HUNTER" "$PID_TARGET" 2>/dev/null
    echo "[launch] Done."
}
trap cleanup INT TERM

echo "[launch] Starting hunter_plane (SYSID 51, instance 0)..."
"$SCRIPT_DIR/launch_hunter.sh" &
PID_HUNTER=$!

echo "[launch] Starting target_plane (SYSID 52, instance 1)..."
"$SCRIPT_DIR/launch_target.sh" &
PID_TARGET=$!

echo "[launch] Both instances running. Start mavproxy (launch_mavproxy.sh both), then run upload_mission.sh."

echo "[launch] Press Ctrl+C to stop."
wait "$PID_HUNTER" "$PID_TARGET"
