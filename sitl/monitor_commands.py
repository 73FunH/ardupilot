#!/usr/bin/env python3
"""Monitor commands being sent to hunter."""

import time
from pymavlink import mavutil

MAVPROXY_URL = "udpout:127.0.0.1:14577"
HUNTER_SYSID = 51

print("Monitoring commands to hunter (SYSID 51) for 10 seconds...")
print("Watching for: RC_OVERRIDE, COMMAND_INT, COMMAND_LONG, SET_POSITION_TARGET_*\n")

mav = mavutil.mavlink_connection(MAVPROXY_URL, source_system=255)

# Register with MAVProxy
for _ in range(3):
    mav.mav.heartbeat_send(
        mavutil.mavlink.MAV_TYPE_GCS,
        mavutil.mavlink.MAV_AUTOPILOT_INVALID, 0, 0, 0)
    time.sleep(0.1)

command_types = [
    'RC_CHANNELS_OVERRIDE',
    'COMMAND_INT',
    'COMMAND_LONG',
    'SET_POSITION_TARGET_GLOBAL_INT',
    'SET_POSITION_TARGET_LOCAL_NED',
    'MISSION_ITEM',
    'MISSION_ITEM_INT'
]

start = time.time()
count = {}

while time.time() - start < 10:
    msg = mav.recv_match(blocking=True, timeout=0.5)
    if msg is None:
        continue
    
    msg_type = msg.get_type()
    target_sys = getattr(msg, 'target_system', None)
    
    # Only show messages targeted at hunter
    if target_sys == HUNTER_SYSID and msg_type in command_types:
        count[msg_type] = count.get(msg_type, 0) + 1
        timestamp = time.time() - start
        print(f"[{timestamp:6.2f}s] {msg_type:35s} from SYSID {msg.get_srcSystem()}")
        
        # Show key details for different message types
        if msg_type == 'COMMAND_INT':
            cmd_name = mavutil.mavlink.enums['MAV_CMD'][msg.command].name if msg.command in mavutil.mavlink.enums['MAV_CMD'] else f"CMD_{msg.command}"
            print(f"           └─> {cmd_name}")
            if msg.command == mavutil.mavlink.MAV_CMD_DO_REPOSITION:
                print(f"               Lat: {msg.x/1e7:.6f}, Lon: {msg.y/1e7:.6f}, Alt: {msg.z:.1f}m")
        
        elif msg_type == 'COMMAND_LONG':
            cmd_name = mavutil.mavlink.enums['MAV_CMD'][msg.command].name if msg.command in mavutil.mavlink.enums['MAV_CMD'] else f"CMD_{msg.command}"
            print(f"           └─> {cmd_name}")
        
        elif msg_type == 'RC_CHANNELS_OVERRIDE':
            print(f"           └─> Channels: {msg.chan1_raw}, {msg.chan2_raw}, {msg.chan3_raw}, {msg.chan4_raw}...")

print("\n" + "=" * 70)
print("SUMMARY:")
if count:
    for msg_type, cnt in sorted(count.items()):
        print(f"  {msg_type:35s}: {cnt} messages")
else:
    print("  No commands detected to hunter")
print("=" * 70)
