#!/bin/bash
# Launch a SITL vehicle with auto-assigned instance.
#
# Usage: launch_vehicle.sh <type> <sysid>
#   type : plane | copter
#   sysid: MAV_SYSID value (any positive integer, e.g. 51, 52, 44)
#
# Each vehicle's serial0 is configured to push MAVLink to shared UDP port 14540.
# MAVProxy listens on that port (udpin) and forwards to QGC on UDP 14550.
# Vehicles launched at any time are picked up automatically — no MAVProxy restart needed.
#
# Start MAVProxy once: ./sitl/launch_mavproxy.sh

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
source "$HOME/venv-ardupilot/bin/activate"

# ── argument validation ──────────────────────────────────────────────────────
TYPE="${1:-}"
SYSID="${2:-}"

if [[ "$TYPE" != "plane" && "$TYPE" != "copter" ]]; then
    echo "Usage: $0 <plane|copter> <sysid>"
    echo "  type : plane | copter"
    echo "  sysid: positive integer (e.g. 51, 52, 44)"
    exit 1
fi
if [[ -z "$SYSID" || ! "$SYSID" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: sysid must be a positive integer."
    echo "Usage: $0 <plane|copter> <sysid>"
    exit 1
fi

# ── find the first free instance (0-5) via PID files ───────────────────────
# serial0 uses udpclient, so TCP ports are not bound — detect via live PIDs.
INSTANCE=-1
for I in 0 1 2 3 4 5; do
    USED=0
    for INST_FILE in "$REPO/sitl/vehicles"/*/instance; do
        [[ -f "$INST_FILE" ]] || continue
        [[ "$(cat "$INST_FILE")" == "$I" ]] || continue
        PID_F="${INST_FILE%/instance}/sitl.pid"
        if [[ -f "$PID_F" ]] && kill -0 "$(cat "$PID_F")" 2>/dev/null; then
            USED=1
            break
        fi
    done
    [[ $USED -eq 0 ]] && INSTANCE=$I && break
done

if [[ $INSTANCE -eq -1 ]]; then
    echo "[launch_vehicle] All 6 SITL slots are occupied. Stop a vehicle first."
    exit 1
fi

SHARED_UDP=14540

# ── spawn position indexed by instance ──────────────────────────────────────
# Even instances cluster slightly south, odd slightly north (~20 m apart).
# Each pair of instances is offset ~50 m to the east from the previous pair.
declare -a LAT_TABLE=(
    "50.623608000"   # 0   0 m
    "50.623647488"   # 1  10 m
    "50.623686977"   # 2  20 m
    "50.623726465"   # 3  30 m
    "50.623765953"   # 4  40 m
    "50.623805441"   # 5  50 m
)
declare -a LON_TABLE=(
    "5.217509000"    # 0   0 m
    "5.217636183"    # 1  10 m
    "5.217763366"    # 2  20 m
    "5.217890549"    # 3  30 m
    "5.218017732"    # 4  40 m
    "5.218144915"    # 5  50 m
)

LAT="${LAT_TABLE[$INSTANCE]}"
LON="${LON_TABLE[$INSTANCE]}"
ALT=$([[ "$TYPE" == "plane" ]] && echo "100" || echo "0")

# ── ArduPilot vehicle class ──────────────────────────────────────────────────
VEHICLE=$([[ "$TYPE" == "plane" ]] && echo "ArduPlane" || echo "ArduCopter")

# ── working directory and per-vehicle sysid override ────────────────────────
WORKDIR="$REPO/sitl/vehicles/$SYSID"
mkdir -p "$WORKDIR"
echo "MAV_SYSID $SYSID" > "$WORKDIR/sysid.parm"
echo "$INSTANCE"  > "$WORKDIR/instance"
echo "$TYPE"      > "$WORKDIR/type"

LOG="$WORKDIR/sitl.log"
PID_FILE="$WORKDIR/sitl.pid"

echo "[launch_vehicle] type=$TYPE  sysid=$SYSID  instance=$INSTANCE  → UDP $SHARED_UDP"
echo "[launch_vehicle] spawn: lat=$LAT lon=$LON alt=${ALT}m"
echo "[launch_vehicle] log: $LOG"

nohup ./Tools/autotest/sim_vehicle.py \
    -v "$VEHICLE" \
    -I "$INSTANCE" \
    --no-rebuild \
    --no-mavproxy \
    --aircraft="sitl/vehicles/$SYSID" \
    --add-param-file="sitl/$TYPE.parm" \
    --add-param-file="$WORKDIR/sysid.parm" \
    -A "--serial0" -A "udpclient:127.0.0.1:$SHARED_UDP" \
    -l "$LAT,$LON,$ALT,0" \
    > "$LOG" 2>&1 &

SIM_PID=$!
disown "$SIM_PID"
echo "$SIM_PID" > "$PID_FILE"

echo "[launch_vehicle] started (PID $SIM_PID) — terminal is free."
echo "[launch_vehicle] After the vehicle is up, run: ./sitl/launch_mavproxy.sh"
echo "[launch_vehicle] To stop: kill \$(cat $PID_FILE)"
