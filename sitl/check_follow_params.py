#!/usr/bin/env python3
"""Check if FOLLOW mode is enabled on hunter."""

import time
from pymavlink import mavutil

MAVPROXY_URL = "udpout:127.0.0.1:14577"
HUNTER_SYSID = 51

print("Connecting...")
mav = mavutil.mavlink_connection(MAVPROXY_URL, source_system=255)

# Register with MAVProxy
for _ in range(3):
    mav.mav.heartbeat_send(
        mavutil.mavlink.MAV_TYPE_GCS,
        mavutil.mavlink.MAV_AUTOPILOT_INVALID, 0, 0, 0)
    time.sleep(0.1)

print("Requesting FOLL_* parameters from hunter...\n")

# Request all parameters
mav.mav.param_request_list_send(HUNTER_SYSID, 1)

params = {}
timeout = time.time() + 5

while time.time() < timeout:
    msg = mav.recv_match(type='PARAM_VALUE', blocking=True, timeout=1)
    if msg and msg.get_srcSystem() == HUNTER_SYSID:
        param_id = msg.param_id
        if 'FOLL' in param_id:
            params[param_id] = msg.param_value

print("=" * 60)
print("FOLLOW Parameters on Hunter (SYSID 51):")
print("=" * 60)
if params:
    for k, v in sorted(params.items()):
        print(f"  {k:20s} = {v}")
else:
    print("  No FOLL_* parameters received")
    print("  (FOLLOW mode may not be compiled in)")
print("=" * 60)
