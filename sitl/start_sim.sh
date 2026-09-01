#!/bin/bash
# Full SITL startup sequence — each long-running process gets its own
# named screen window so you can inspect its output at any time.
#
# Vehicles are selected as a glued string of 2-letter role tokens:
#   hp = hunter_plane (SYSID 51)   hc = hunter_copter (SYSID 41)
#   tp = target_plane (SYSID 52)   tc = target_copter (SYSID 42)
# e.g. "hptp" (default), "hptc", "hphc" (two hunters), "hphctptc" (all four).
# Each token may appear at most once. A screen window is created per token.
#
# Windows created:
#   <token>   — one per selected vehicle (e.g. "hp", "hc", "tp", "tc")
#   mavproxy  — MAVProxy bridge console
#   qgc       — QGroundControl
#
# Usage:
#   ./sitl/start_sim.sh                          — launch with defaults (hptp)
#   ./sitl/start_sim.sh hptc                     — hunter_plane + target_copter
#   ./sitl/start_sim.sh hphctptc                 — all four vehicles
#   ./sitl/start_sim.sh --attach                 — launch and attach to screen session
#   ./sitl/start_sim.sh -H copter -T plane       — legacy: exactly one hunter + one target
#   ./sitl/start_sim.sh -h | --help              — show this help
#
# Re-attach later : screen -r sitl_sim
# Switch window   : Ctrl+A then "  (list) or Ctrl+A N / Ctrl+A P
# Detach          : Ctrl+A D  (keeps everything running)
# Stop everything : Ctrl+C in this terminal, or: screen -S sitl_sim -X quit

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION="sitl_sim"

# ============================================================
# Role token → (vehicle type, MAV_SYSID, tuning param file)
# ============================================================
declare -A ROLE_TYPE=([hp]=plane  [hc]=copter [tp]=plane  [tc]=copter)
declare -A ROLE_SYSID=([hp]=51    [hc]=41     [tp]=52     [tc]=42)
declare -A ROLE_PARM=(
    [hp]="sitl/hunter_plane/hunter_plane.parm"
    [hc]="sitl/hunter_copter/hunter_copter.parm"
    [tp]="sitl/target_plane/target_plane.parm"
    [tc]="sitl/target_copter/target_copter.parm"
)
declare -A ROLE_KIND=([hp]=hunter [hc]=hunter [tp]=target [tc]=target)

COMBO=""            # glued token string, e.g. "hptc" — resolved below
HUNTER_TYPE=""      # legacy -H/-T mode: exactly one hunter + one target
TARGET_TYPE=""
ATTACH=false
# ============================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [COMBO] [OPTIONS]

COMBO is a glued string of 2-letter role tokens (default: hptp):
  hp = hunter_plane   hc = hunter_copter   tp = target_plane   tc = target_copter
  Each token appears at most once, in any order, e.g.: hptc, hphc, hphctptc

Options:
  -H, --hunter=TYPE   Legacy mode: hunter vehicle type: plane | copter
  -T, --target=TYPE   Legacy mode: target vehicle type: plane | copter
      --attach        Attach to the screen session after launch
  -h, --help          Show this help and exit

Examples:
  $(basename "$0")                         # hunter_plane + target_plane (defaults)
  $(basename "$0") hptc                    # hunter_plane + target_copter
  $(basename "$0") hphc                    # two hunters, no target
  $(basename "$0") hphctptc                # all four vehicles at once
  $(basename "$0") -H plane -T copter      # legacy: hunter=plane, target=copter
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
        -*)
            echo "ERROR: unknown option '$1'" >&2; usage >&2; exit 1 ;;
        *)
            if [[ -n "$COMBO" ]]; then
                echo "ERROR: multiple combo arguments given ('$COMBO' and '$1')" >&2; exit 1
            fi
            COMBO="$1"; shift ;;
    esac
done

# ----- resolve the vehicle token list -----------------------------------------
# Legacy -H/-T mode takes precedence over a positional combo, matching the
# tool's original single-hunter/single-target behaviour.
declare -a TOKENS=()
if [[ -n "$HUNTER_TYPE" || -n "$TARGET_TYPE" ]]; then
    HUNTER_TYPE="${HUNTER_TYPE:-plane}"
    TARGET_TYPE="${TARGET_TYPE:-plane}"
    TOKENS=("h${HUNTER_TYPE:0:1}" "t${TARGET_TYPE:0:1}")
else
    COMBO="${COMBO:-hptp}"
    if (( ${#COMBO} % 2 != 0 )); then
        echo "ERROR: combo '$COMBO' must be made of 2-letter tokens (hp/hc/tp/tc)" >&2; exit 1
    fi
    for (( i=0; i<${#COMBO}; i+=2 )); do
        TOK="${COMBO:i:2}"
        if [[ -z "${ROLE_TYPE[$TOK]+x}" ]]; then
            echo "ERROR: unknown token '$TOK' in combo '$COMBO' (valid: hp, hc, tp, tc)" >&2; exit 1
        fi
        for SEEN in "${TOKENS[@]:-}"; do
            [[ "$SEEN" == "$TOK" ]] && { echo "ERROR: token '$TOK' repeated in combo '$COMBO'" >&2; exit 1; }
        done
        TOKENS+=("$TOK")
    done
fi

if [[ ${#TOKENS[@]} -eq 0 ]]; then
    echo "ERROR: no vehicles selected" >&2; exit 1
fi

# ----- helpers ---------------------------------------------------------------

wait_udp() {
    local port=$1 label=$2
    echo "[start_sim] Waiting for $label on UDP :$port ..."
    until ss -lnup | grep -q ":$port "; do
        sleep 0.5
    done
    echo "[start_sim] $label is up."
}

wait_file() {
    local path=$1 label=$2 timeout=${3:-20}
    echo "[start_sim] Waiting for $label ..."
    local waited=0
    until [[ -f "$path" ]]; do
        sleep 0.2
        waited=$((waited + 1))
        if (( waited > timeout * 5 )); then
            echo "[start_sim] ERROR: timed out waiting for $label ($path)"
            exit 1
        fi
    done
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

# ----- step 1: SITL — one screen window per selected token -------------------
# Each vehicle is launched via launch_vehicle.sh, which auto-assigns a free
# instance/TCP port and bridges MAVLink through the shared UDP 14550 port —
# this is what allows any number/combination of hunters and targets at once.

echo "[start_sim] Step 1 — launching SITL for: ${TOKENS[*]} ..."
ANY_COPTER=false
for TOK in "${TOKENS[@]}"; do
    TYPE="${ROLE_TYPE[$TOK]}"
    SYSID="${ROLE_SYSID[$TOK]}"
    PARM="${ROLE_PARM[$TOK]}"
    [[ "$TYPE" == "copter" ]] && ANY_COPTER=true

    echo "[start_sim]   $TOK -> ${ROLE_KIND[$TOK]}_${TYPE} (SYSID $SYSID)"
    # Clear any stale instance file so we can detect this launch's own file below.
    rm -f "$SCRIPT_DIR/vehicles/$SYSID/instance"
    if [[ -z "$(screen -list | grep "$SESSION")" ]]; then
        screen -dmS "$SESSION" -t "$TOK" bash -c "\"$SCRIPT_DIR/launch_vehicle.sh\" \"$TYPE\" \"$SYSID\" \"$PARM\"; exec bash"
    else
        screen -S "$SESSION" -X screen -t "$TOK" bash -c "\"$SCRIPT_DIR/launch_vehicle.sh\" \"$TYPE\" \"$SYSID\" \"$PARM\"; exec bash"
    fi

    # Serialize launches: wait for this vehicle to claim its instance before
    # starting the next one, to avoid two vehicles racing for the same slot.
    # launch_vehicle.sh runs serial0 over UDP only (no TCP console port), so
    # process liveness (pid file) is the readiness signal here, not wait_tcp.
    wait_file "$SCRIPT_DIR/vehicles/$SYSID/instance" "$TOK instance assignment"
    wait_file "$SCRIPT_DIR/vehicles/$SYSID/sitl.pid" "$TOK process start"
    INSTANCE="$(cat "$SCRIPT_DIR/vehicles/$SYSID/instance")"
    echo "[start_sim]   $TOK using instance $INSTANCE (SYSID $SYSID)"
done

# Copters need longer EKF + storage initialization than planes.
if [[ "$ANY_COPTER" == true ]]; then
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

# ----- step 3: upload mission — one GUI dialog per target, sequentially -----

for TOK in "${TOKENS[@]}"; do
    [[ "${ROLE_KIND[$TOK]}" == "target" ]] || continue
    SYSID="${ROLE_SYSID[$TOK]}"
    echo "[start_sim] Step 3 — uploading mission for $TOK (SYSID $SYSID)..."
    "$SCRIPT_DIR/upload_mission.sh" "$SYSID"
done

# ----- step 4: QGroundControl ------------------------------------------------

echo "[start_sim] Step 4 — launching QGroundControl in screen window 'qgc'..."
screen -S "$SESSION" -X screen -t qgc bash -c "$SCRIPT_DIR/launch_qgc.sh; exec bash"

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
