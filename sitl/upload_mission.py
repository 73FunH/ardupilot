#!/usr/bin/env python3
"""
Upload a mission to target_plane via mavproxy's UDP service port (14577).
Uses MAVLink protocol directly — receives MISSION_REQUEST per waypoint and
waits for MISSION_ACK to confirm the vehicle accepted the full mission.

Usage:
  python3 upload_mission.py                    # file selection dialog
  python3 upload_mission.py --headless         # use default mission file
  python3 upload_mission.py path/to/file.waypoints  # explicit file, no dialog
"""
import argparse
import os
import sys
import time


def load_waypoints(path):
    wps = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('QGC') or line.startswith('#'):
                continue
            parts = line.split('\t')
            if len(parts) < 12:
                continue
            wps.append({
                'seq':          int(parts[0]),
                'current':      int(parts[1]),
                'frame':        int(parts[2]),
                'command':      int(parts[3]),
                'param1':       float(parts[4]),
                'param2':       float(parts[5]),
                'param3':       float(parts[6]),
                'param4':       float(parts[7]),
                'lat':          float(parts[8]),
                'lon':          float(parts[9]),
                'alt':          float(parts[10]),
                'autocontinue': int(parts[11]),
            })
    return wps


def upload(url, target_sysid, wps, timeout=30):
    from pymavlink import mavutil

    mav = mavutil.mavlink_connection(url, source_system=255)

    # Send a heartbeat so mavproxy learns our source port and forwards data to us
    mav.mav.heartbeat_send(
        mavutil.mavlink.MAV_TYPE_GCS,
        mavutil.mavlink.MAV_AUTOPILOT_INVALID,
        0, 0, 0)
    time.sleep(0.1)

    print(f"  Waiting for heartbeat from SYSID {target_sysid}...", flush=True)
    deadline = time.time() + timeout
    while time.time() < deadline:
        # Send a heartbeat so mavproxy's udpin registers our source address
        # and starts forwarding traffic back to us.
        mav.mav.heartbeat_send(
            mavutil.mavlink.MAV_TYPE_GCS,
            mavutil.mavlink.MAV_AUTOPILOT_INVALID,
            0, 0, 0)
        msg = mav.recv_match(type='HEARTBEAT', blocking=True, timeout=1)
        if msg and msg.get_srcSystem() == target_sysid:
            print("  Connected.", flush=True)
            break
    else:
        print("  ERROR: no heartbeat — is SITL running and mavproxy bridge up?")
        mav.close()
        return False

    mav.target_system    = target_sysid
    mav.target_component = 1

    count = len(wps)
    mav.mav.mission_count_send(target_sysid, 1, count)
    print(f"  Sending {count} waypoints...", flush=True)

    acked = False
    deadline = time.time() + timeout
    while time.time() < deadline:
        msg = mav.recv_match(
            type=['MISSION_REQUEST', 'MISSION_REQUEST_INT', 'MISSION_ACK'],
            blocking=True, timeout=2)
        if msg is None:
            continue
        t = msg.get_type()
        if t == 'MISSION_ACK':
            if msg.type == 0:  # MAV_MISSION_ACCEPTED
                acked = True
            else:
                print(f"  ERROR: vehicle rejected mission (MISSION_ACK type={msg.type})")
            break
        if t in ('MISSION_REQUEST', 'MISSION_REQUEST_INT'):
            seq = msg.seq
            if seq >= count:
                break
            wp = wps[seq]
            mav.mav.mission_item_send(
                target_sysid, 1, seq,
                wp['frame'], wp['command'],
                wp['current'], wp['autocontinue'],
                wp['param1'], wp['param2'], wp['param3'], wp['param4'],
                wp['lat'], wp['lon'], wp['alt'])
            print(f"  WP {seq + 1}/{count}", flush=True)

    mav.close()
    return acked


def pick_mission_file(default_path):
    """Open a file selection dialog. Returns chosen path or None if cancelled."""
    try:
        import tkinter as tk
        from tkinter import filedialog
        root = tk.Tk()
        root.withdraw()
        root.attributes('-topmost', True)
        initial_dir  = os.path.dirname(default_path)
        initial_file = os.path.basename(default_path)
        chosen = filedialog.askopenfilename(
            title="Select mission file",
            initialdir=initial_dir,
            initialfile=initial_file,
            filetypes=[("Waypoint files", "*.waypoints *.txt"), ("All files", "*")],
        )
        root.destroy()
        return chosen if chosen else None
    except Exception as e:
        print(f"[upload_mission] WARNING: file dialog unavailable ({e}), falling back to default.")
        return default_path


def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    default_mission = os.path.join(repo, 'sitl', 'target_plane', 'mission.waypoints')

    parser = argparse.ArgumentParser(description="Upload a MAVLink mission to target_plane.")
    parser.add_argument('mission', nargs='?', default=None,
                        help="Path to .waypoints file (skips dialog if provided).")
    parser.add_argument('--headless', action='store_true',
                        help="Skip file dialog and use the default mission file.")
    args = parser.parse_args()

    if args.mission:
        mission = args.mission
    elif args.headless:
        mission = default_mission
    else:
        print(f"[upload_mission] Opening file dialog (default: {default_mission})")
        mission = pick_mission_file(default_mission)
        if not mission:
            print("[upload_mission] Cancelled.")
            sys.exit(0)

    if not os.path.exists(mission):
        print(f"[upload_mission] ERROR: {mission} not found")
        sys.exit(1)

    wps = load_waypoints(mission)
    print(f"[upload_mission] {len(wps)} waypoints from {mission}")
    print("[upload_mission] Uploading to SYSID 52 via udp:14577...")

    ok = upload('udpout:127.0.0.1:14577', 52, wps)
    if ok:
        print("[upload_mission] SUCCESS — mission accepted by vehicle.")
        sys.exit(0)
    else:
        print("[upload_mission] FAILED — mission was not accepted by vehicle.")
        sys.exit(1)


if __name__ == '__main__':
    main()
