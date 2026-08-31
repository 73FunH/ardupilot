#!/bin/bash
# Launch two ArduCopter SITL instances in a single console (background processes).
#   hunter_copter  - SYSID 41 - instance 0 - TCP 5760
#   target_copter  - SYSID 42 - instance 1 - TCP 5770
# SITL instances use private debug ports (14551/14561) — use launch_mavproxy.sh
# which forwards both vehicles cleanly to QGC via UDP 14550 (hunter+target mixed,
# distinguished by SYSID) and UDP 14560 as an alternative output.
#
# Ports are shared with the plane simulation — run only one session at a time.
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

echo "[launch] Starting hunter_copter (SYSID 41, instance 0)..."
"$SCRIPT_DIR/launch_hunter_copter.sh" &
PID_HUNTER=$!

echo "[launch] Starting target_copter (SYSID 42, instance 1)..."
"$SCRIPT_DIR/launch_target_copter.sh" &
PID_TARGET=$!

echo "[launch] Both instances running. Start mavproxy: launch_mavproxy.sh both_copter"
echo "[launch] Press Ctrl+C to stop."
wait "$PID_HUNTER" "$PID_TARGET"
