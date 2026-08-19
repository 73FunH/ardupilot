#!/bin/bash
# Kill any running MAVProxy instances (including stopped/suspended ones).

PIDS=$(pgrep -d ' ' -f 'mavproxy')

if [ -z "$PIDS" ]; then
    echo "[kill_mavproxy] No MAVProxy processes found."
    exit 0
fi

echo "[kill_mavproxy] Killing PIDs: $PIDS"
kill $PIDS 2>/dev/null
sleep 1

REMAINING=$(pgrep -d ' ' -f 'mavproxy')
if [ -n "$REMAINING" ]; then
    echo "[kill_mavproxy] Force-killing: $REMAINING"
    kill -9 $REMAINING 2>/dev/null
fi

echo "[kill_mavproxy] Done."
