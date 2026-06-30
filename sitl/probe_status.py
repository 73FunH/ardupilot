#!/usr/bin/env python3
"""Quick probe to check if hunter is still tracking target."""

import time
from pymavlink import mavutil

MAVPROXY_URL = "udpout:127.0.0.1:14577"
HUNTER_SYSID = 51
TARGET_SYSID = 52

print("Connecting to vehicles...")
mav = mavutil.mavlink_connection(MAVPROXY_URL, source_system=255)

# Send heartbeats to register with MAVProxy
for _ in range(3):
    mav.mav.heartbeat_send(
        mavutil.mavlink.MAV_TYPE_GCS,
        mavutil.mavlink.MAV_AUTOPILOT_INVALID, 0, 0, 0)
    time.sleep(0.1)

print("Collecting data for 5 seconds...\n")

positions = {HUNTER_SYSID: [], TARGET_SYSID: []}
modes = {}

start_time = time.time()
while time.time() - start_time < 5:
    msg = mav.recv_match(blocking=True, timeout=0.5)
    if msg is None:
        continue
    
    sysid = msg.get_srcSystem()
    
    if msg.get_type() == 'HEARTBEAT' and sysid in [HUNTER_SYSID, TARGET_SYSID]:
        modes[sysid] = msg.custom_mode
        
    if msg.get_type() == 'GLOBAL_POSITION_INT' and sysid in [HUNTER_SYSID, TARGET_SYSID]:
        pos = {
            'time': time.time(),
            'lat': msg.lat / 1e7,
            'lon': msg.lon / 1e7,
            'alt': msg.alt / 1000.0
        }
        positions[sysid].append(pos)

print("=" * 70)
print("MODES:")
print(f"  Hunter (51): mode {modes.get(HUNTER_SYSID, 'unknown')} (15=GUIDED, 10=AUTO)")
print(f"  Target (52): mode {modes.get(TARGET_SYSID, 'unknown')}")

print("\nPOSITIONS:")
for sysid in [TARGET_SYSID, HUNTER_SYSID]:
    name = "Target" if sysid == TARGET_SYSID else "Hunter"
    if positions[sysid]:
        first = positions[sysid][0]
        last = positions[sysid][-1]
        dt = last['time'] - first['time']
        dlat = (last['lat'] - first['lat']) * 111139  # approx meters
        dlon = (last['lon'] - first['lon']) * 111139
        dist = (dlat**2 + dlon**2)**0.5
        speed = dist / dt if dt > 0 else 0
        
        print(f"  {name} (SYSID {sysid}):")
        print(f"    Latest: ({last['lat']:.6f}, {last['lon']:.6f}, {last['alt']:.1f}m)")
        print(f"    Moved:  {dist:.1f}m in {dt:.1f}s ({speed:.1f} m/s)")
    else:
        print(f"  {name} (SYSID {sysid}): No position data received")

if positions[HUNTER_SYSID] and positions[TARGET_SYSID]:
    hunter_latest = positions[HUNTER_SYSID][-1]
    target_latest = positions[TARGET_SYSID][-1]
    
    dlat = (target_latest['lat'] - hunter_latest['lat']) * 111139
    dlon = (target_latest['lon'] - hunter_latest['lon']) * 111139
    separation = (dlat**2 + dlon**2)**0.5
    
    print(f"\nSEPARATION: {separation:.1f}m")
    print(f"  Target is {dlat:.1f}m north, {dlon:.1f}m east of hunter")

print("=" * 70)
