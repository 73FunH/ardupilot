#!/bin/bash
# Full SITL startup sequence — each long-running process gets its own
# named screen window so you can inspect its output at any time.
#
# Windows created:
#   sitl      — both ArduPlane instances (hunter + target)
#   mavproxy  — MAVProxy bridge console
#
# To change the mission, edit the MISSION variable in upload_mission.sh.
#
# Usage:
#   ./sitl/start_sim.sh           — launch everything, Ctrl+C to stop all
#   ./sitl/start_sim.sh --attach  — launch and attach to screen session
#
# Re-attach later : screen -r sitl_sim
# Switch window   : Ctrl+A then "  (list) or Ctrl+A N / Ctrl+A P
# Detach          : Ctrl+A D  (keeps everything running)
# Stop everything : Ctrl+C in this terminal, or: screen -S sitl_sim -X quit

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION="sitl_sim"

# ----- helpers ---------------------------------------------------------------

tcp_ready() {
    local host=$1 port=$2
    (echo >/dev/tcp/"$host"/"$port") 2>/dev/null
}

wait_tcp() {
    local host=$1 port=$2 label=$3
    echo "[start_sim] Waiting for $label on $host:$port ..."
    until tcp_ready "$host" "$port"; do
        sleep 0.5
    done
    echo "[start_sim] $label is up."
}

wait_udp() {
    local port=$1 label=$2
    echo "[start_sim] Waiting for $label on UDP :$port ..."
    until ss -lnup | grep -q ":$port "; do
        sleep 0.5
    done
    echo "[start_sim] $label is up."
}

# ----- cleanup ---------------------------------------------------------------

cleanup() {
    trap - INT TERM EXIT
    echo
    echo "[start_sim] Shutting down..."
    screen -S "$SESSION" -X quit 2>/dev/null
    pkill -f "QGroundControl" 2>/dev/null
    "$SCRIPT_DIR/kill_sitl.sh"
    echo "[start_sim] Done."
}
trap cleanup INT TERM EXIT

# ----- guard: screen must be available ---------------------------------------

if ! command -v screen &>/dev/null; then
    echo "[start_sim] ERROR: 'screen' is not installed. Install it with: sudo apt install screen"
    exit 1
fi

# Kill any leftover session from a previous run.
screen -S "$SESSION" -X quit 2>/dev/null
sleep 0.5

# ----- step 1: SITL in its own screen window ---------------------------------

echo "[start_sim] Step 1 — launching SITL in screen window 'sitl'..."
screen -dmS "$SESSION" -t sitl bash -c "$SCRIPT_DIR/launch_dual_plane.sh; exec bash"

wait_tcp 127.0.0.1 5760 "hunter_plane (SYSID 51)"
wait_tcp 127.0.0.1 5770 "target_plane (SYSID 52)"

echo "[start_sim] Letting SITL finish boot (5 s)..."
sleep 5

# ----- step 2: MAVProxy in its own screen window -----------------------------

echo "[start_sim] Step 2 — launching MAVProxy in screen window 'mavproxy'..."
screen -S "$SESSION" -X screen -t mavproxy bash -c "$SCRIPT_DIR/launch_mavproxy.sh both; exec bash"

wait_udp 14577 "MAVProxy udpin"

# ----- step 3: upload mission (runs inline, exits when done) -----------------

echo "[start_sim] Step 3 — uploading mission..."
"$SCRIPT_DIR/upload_mission.sh"

# ----- step 4: QGroundControl ------------------------------------------------

echo "[start_sim] Step 4 — launching QGroundControl..."
"$SCRIPT_DIR/launch_qgc.sh"

# ----- step 5: attach or wait ------------------------------------------------

echo ""
echo "[start_sim] All up."
echo "  Re-attach : screen -r $SESSION"
echo "  Windows   : Ctrl+A then \" to list | Ctrl+A N/P to switch"
echo "  Detach    : Ctrl+A D  (keeps sim running)"
echo "  Stop all  : Ctrl+C here"
echo ""

if [[ "${1:-}" == "--attach" ]]; then
    # Attach — Ctrl+C inside screen goes to the inner process, not here.
    # To stop everything from inside: detach with Ctrl+A D, then Ctrl+C here.
    screen -r "$SESSION"
else
    # Default: stay in background. One Ctrl+C here stops everything cleanly.
    while screen -list | grep -q "$SESSION"; do
        sleep 2
    done
fi
