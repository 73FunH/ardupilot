#!/bin/bash
# Full SITL startup sequence — each long-running process gets its own
# named screen window so you can inspect its output at any time.
#
# Windows created:
#   sitl      — both SITL instances (vehicle types set by HUNTER_TYPE / TARGET_TYPE)
#   mavproxy  — MAVProxy bridge console
#
# Usage:
#   ./sitl/start_sim.sh                          — launch with defaults
#   ./sitl/start_sim.sh --attach                 — launch and attach to screen session
#   ./sitl/start_sim.sh -H copter -T plane       — override vehicle types
#   ./sitl/start_sim.sh --hunter=copter --target=plane
#   ./sitl/start_sim.sh -h | --help              — show this help
#
# Re-attach later : screen -r sitl_sim
# Switch window   : Ctrl+A then "  (list) or Ctrl+A N / Ctrl+A P
# Detach          : Ctrl+A D  (keeps everything running)
# Stop everything : Ctrl+C in this terminal, or: screen -S sitl_sim -X quit

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION="sitl_sim"

# ============================================================
# Simulation defaults — overridable via -H / -T arguments.
# Supported values: plane | copter
# ============================================================
HUNTER_TYPE=copter   # plane | copter
TARGET_TYPE=copter   # plane | copter
ATTACH=false
# ============================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -H, --hunter=TYPE   Hunter vehicle type: plane | copter  (default: ${HUNTER_TYPE})
  -T, --target=TYPE   Target vehicle type: plane | copter  (default: ${TARGET_TYPE})
      --attach        Attach to the screen session after launch
  -h, --help          Show this help and exit

Examples:
  $(basename "$0")                         # both copter (defaults)
  $(basename "$0") -H plane -T copter      # hunter=plane, target=copter
  $(basename "$0") --hunter=plane --target=copter --attach
EOF
}

validate_type() {
    local val=$1 opt=$2
    if [[ "$val" != "plane" && "$val" != "copter" ]]; then
        echo "ERROR: $opt must be 'plane' or 'copter', got: '$val'" >&2
        exit 1
    fi
}

# ----- argument parsing ------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage; exit 0 ;;
        -H)
            HUNTER_TYPE="$2"; validate_type "$HUNTER_TYPE" "-H"; shift 2 ;;
        --hunter)
            HUNTER_TYPE="$2"; validate_type "$HUNTER_TYPE" "--hunter"; shift 2 ;;
        --hunter=*)
            HUNTER_TYPE="${1#--hunter=}"; validate_type "$HUNTER_TYPE" "--hunter"; shift ;;
        -T)
            TARGET_TYPE="$2"; validate_type "$TARGET_TYPE" "-T"; shift 2 ;;
        --target)
            TARGET_TYPE="$2"; validate_type "$TARGET_TYPE" "--target"; shift 2 ;;
        --target=*)
            TARGET_TYPE="${1#--target=}"; validate_type "$TARGET_TYPE" "--target"; shift ;;
        --attach)
            ATTACH=true; shift ;;
        *)
            echo "ERROR: unknown option '$1'" >&2; usage >&2; exit 1 ;;
    esac
done

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

# ----- resolve launch script names (plane scripts have no _plane suffix) -----
# hunter: launch_hunter_copter.sh  OR  launch_hunter.sh (plane)
# target: launch_target_copter.sh  OR  launch_target.sh (plane)
declare -A HUNTER_LAUNCH=([copter]="launch_hunter_copter.sh" [plane]="launch_hunter.sh")
declare -A TARGET_LAUNCH=([copter]="launch_target_copter.sh" [plane]="launch_target.sh")

# ----- step 1: SITL in its own screen window ---------------------------------

echo "[start_sim] Step 1 — launching SITL in screen window 'sitl' (hunter=${HUNTER_TYPE}, target=${TARGET_TYPE})..."
screen -dmS "$SESSION" -t sitl bash -c "
    \"$SCRIPT_DIR/${HUNTER_LAUNCH[$HUNTER_TYPE]}\" &
    HUNTER_PID=\$!
    \"$SCRIPT_DIR/${TARGET_LAUNCH[$TARGET_TYPE]}\" &
    TARGET_PID=\$!
    wait \$HUNTER_PID \$TARGET_PID
    exec bash
"

wait_tcp 127.0.0.1 5760 "hunter (SYSID 51, ${HUNTER_TYPE})"
wait_tcp 127.0.0.1 5770 "target (SYSID 52, ${TARGET_TYPE})"

# Copters need longer EKF + storage initialization than planes.
if [[ "$HUNTER_TYPE" == "copter" || "$TARGET_TYPE" == "copter" ]]; then
    BOOT_WAIT=15
else
    BOOT_WAIT=5
fi
echo "[start_sim] Letting SITL finish boot (${BOOT_WAIT}s)..."
sleep $BOOT_WAIT

# ----- step 2: MAVProxy in its own screen window -----------------------------

echo "[start_sim] Step 2 — launching MAVProxy in screen window 'mavproxy'..."
screen -S "$SESSION" -X screen -t mavproxy bash -c "$SCRIPT_DIR/launch_mavproxy.sh both; exec bash"

wait_udp 14577 "MAVProxy udpin"

# ----- step 3: upload mission (runs inline, exits when done) -----------------

echo "[start_sim] Step 3 — uploading mission for target_${TARGET_TYPE}..."
"$SCRIPT_DIR/upload_mission.sh" "$TARGET_TYPE"

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

if [[ "$ATTACH" == true ]]; then
    # Attach — Ctrl+C inside screen goes to the inner process, not here.
    # To stop everything from inside: detach with Ctrl+A D, then Ctrl+C here.
    screen -r "$SESSION"
else
    # Default: stay in background. One Ctrl+C here stops everything cleanly.
    while screen -list | grep -q "$SESSION"; do
        sleep 2
    done
fi
