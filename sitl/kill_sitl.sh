#!/bin/bash
# Kill any leftover SITL (arduplane, arducopter) and sim_vehicle.py processes.

PIDS=$(pgrep -d ' ' -f 'arduplane|arducopter|sim_vehicle.py')

if [ -z "$PIDS" ]; then
    echo "[kill_sitl] No SITL processes found."
    exit 0
fi

echo "[kill_sitl] Killing PIDs: $PIDS"
kill $PIDS 2>/dev/null
sleep 1

# Force-kill anything still alive
REMAINING=$(pgrep -d ' ' -f 'arduplane|arducopter|sim_vehicle.py')
if [ -n "$REMAINING" ]; then
    echo "[kill_sitl] Force-killing: $REMAINING"
    kill -9 $REMAINING 2>/dev/null
fi

echo "[kill_sitl] Done."
