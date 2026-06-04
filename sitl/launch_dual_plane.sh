#!/bin/bash
# Launch two ArduPlane SITL instances in a single console (background processes).
#   hunter_plane  - SYSID 51 - instance 0 - TCP 5760
#   target_plane  - SYSID 52 - instance 1 - TCP 5770
# Both output to the same UDP port 14550 — GCS differentiates by SYSID.
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

echo "[launch] Both instances running. Waiting 20s for SITL to initialise before uploading mission..."
(sleep 20 && "$SCRIPT_DIR/upload_mission.sh") &

echo "[launch] Press Ctrl+C to stop."
wait "$PID_HUNTER" "$PID_TARGET"
