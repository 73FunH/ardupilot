#!/usr/bin/env python3
"""
follow.py — hunter_plane (SYSID 51) follows target_plane (SYSID 52) in GUIDED mode.

The hunter keeps a configurable NED offset behind/beside the target.
Run AFTER both SITL instances and mavproxy are up:
    python3 sitl/follow.py

Controls:
    Ctrl+C  → stop following, hunter keeps last GUIDED position
"""

import math
import sys
import time

from pymavlink import mavutil

# ── configuration ────────────────────────────────────────────────────────────
MAVPROXY_URL  = "udpout:127.0.0.1:14577"
HUNTER_SYSID  = 51
TARGET_SYSID  = 52
UPDATE_HZ     = 4           # how often per second to send GUIDED commands

# Formation offset relative to target, in North-East-Down (meters)
# Positive X = behind (north), positive Y = right (east), negative Z = above
OFFSET_X_M    = -20.0       # 50 m behind (south of target)
OFFSET_Y_M    =   0.0       # inline
OFFSET_Z_M    =   0.0       # same altitude

PLANE_MODE_GUIDED = 15   # ArduPlane GUIDED mode number


def ned_offset_to_latlon(lat_deg, lon_deg, north_m, east_m):
    """Return (lat, lon) shifted by (north_m, east_m) meters."""
    lat_rad = math.radians(lat_deg)
    dlat = north_m / 6378137.0
    dlon = east_m  / (6378137.0 * math.cos(lat_rad))
    return lat_deg + math.degrees(dlat), lon_deg + math.degrees(dlon)


def wait_heartbeat(mav, sysid, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        mav.mav.heartbeat_send(
            mavutil.mavlink.MAV_TYPE_GCS,
            mavutil.mavlink.MAV_AUTOPILOT_INVALID, 0, 0, 0)
        msg = mav.recv_match(type='HEARTBEAT', blocking=True, timeout=1)
        if msg and msg.get_srcSystem() == sysid:
            return True
    return False


def set_guided_mode(mav, sysid):
    """Command a specific sysid to switch to GUIDED mode."""
    mav.mav.command_long_send(
        sysid, 1,
        mavutil.mavlink.MAV_CMD_DO_SET_MODE,
        0,
        mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
        PLANE_MODE_GUIDED,
        0, 0, 0, 0, 0
    )


def send_guided_position(mav, sysid, lat_deg, lon_deg, alt_m_amsl):
    """Send MAV_CMD_DO_REPOSITION via command_int — the only way ArduPlane
    honours lat/lon updates in GUIDED mode. SET_POSITION_TARGET_GLOBAL_INT
    only handles altitude in ArduPlane."""
    mav.mav.command_int_send(
        sysid, 1,                                       # target system / component
        mavutil.mavlink.MAV_FRAME_GLOBAL,               # altitude frame: AMSL
        mavutil.mavlink.MAV_CMD_DO_REPOSITION,
        0, 0,                                           # current, autocontinue
        -1,                                             # param1: ground speed (-1 = no change)
        mavutil.mavlink.MAV_DO_REPOSITION_FLAGS_CHANGE_MODE,  # param2: switch to GUIDED if needed
        0,                                              # param3: loiter radius (0 = default)
        float('nan'),                                   # param4: yaw (NaN = no change)
        int(lat_deg * 1e7),                             # x: lat (degE7)
        int(lon_deg * 1e7),                             # y: lon (degE7)
        alt_m_amsl,                                     # z: altitude AMSL (m)
    )


def main():
    print(f"[follow] Connecting to MAVProxy at {MAVPROXY_URL} ...")
    mav = mavutil.mavlink_connection(MAVPROXY_URL, source_system=255)

    # Announce ourselves so mavproxy's udpin registers our return address
    for _ in range(3):
        mav.mav.heartbeat_send(
            mavutil.mavlink.MAV_TYPE_GCS,
            mavutil.mavlink.MAV_AUTOPILOT_INVALID, 0, 0, 0)
        time.sleep(0.1)

    print(f"[follow] Waiting for hunter  (SYSID {HUNTER_SYSID}) ...")
    if not wait_heartbeat(mav, HUNTER_SYSID):
        print("[follow] ERROR: hunter heartbeat timeout — is SITL running?")
        sys.exit(1)
    print(f"[follow] Waiting for target  (SYSID {TARGET_SYSID}) ...")
    if not wait_heartbeat(mav, TARGET_SYSID):
        print("[follow] ERROR: target heartbeat timeout — is SITL running?")
        sys.exit(1)

    print("[follow] Both vehicles found.  Switching hunter to GUIDED ...")
    set_guided_mode(mav, HUNTER_SYSID)
    time.sleep(1)

    # Request GLOBAL_POSITION_INT stream from target at 4 Hz
    mav.mav.request_data_stream_send(
        TARGET_SYSID, 1,
        mavutil.mavlink.MAV_DATA_STREAM_POSITION,
        UPDATE_HZ, 1)

    interval_s = 1.0 / UPDATE_HZ
    last_target_pos = None
    last_heartbeat_s = 0.0
    print(f"[follow] Following started. Offset: X={OFFSET_X_M}m  Y={OFFSET_Y_M}m  Z={OFFSET_Z_M}m")
    print("[follow] Ctrl+C to stop.\n")

    try:
        while True:
            loop_start = time.time()

            # Keep udpin registration alive: send a GCS heartbeat every second
            if loop_start - last_heartbeat_s >= 1.0:
                mav.mav.heartbeat_send(
                    mavutil.mavlink.MAV_TYPE_GCS,
                    mavutil.mavlink.MAV_AUTOPILOT_INVALID, 0, 0, 0)
                last_heartbeat_s = loop_start

            # Drain incoming messages; capture latest target position
            while True:
                msg = mav.recv_match(blocking=False)
                if msg is None:
                    break
                if (msg.get_type() == 'GLOBAL_POSITION_INT'
                        and msg.get_srcSystem() == TARGET_SYSID):
                    last_target_pos = msg

            if last_target_pos is not None:
                t_lat = last_target_pos.lat  / 1e7
                t_lon = last_target_pos.lon  / 1e7
                t_alt = last_target_pos.alt  / 1000.0  # mm → m (AMSL)

                h_lat, h_lon = ned_offset_to_latlon(t_lat, t_lon, OFFSET_X_M, OFFSET_Y_M)
                h_alt = t_alt - OFFSET_Z_M  # positive Z = down, so subtract for above

                send_guided_position(mav, HUNTER_SYSID, h_lat, h_lon, h_alt)
                print(f"\r[follow] target ({t_lat:.5f},{t_lon:.5f},{t_alt:.0f}m) "
                      f"→ hunter cmd ({h_lat:.5f},{h_lon:.5f},{h_alt:.0f}m)   ",
                      end="", flush=True)
            else:
                print("\r[follow] waiting for target position ...                 ",
                      end="", flush=True)

            elapsed = time.time() - loop_start
            sleep_for = interval_s - elapsed
            if sleep_for > 0:
                time.sleep(sleep_for)

    except KeyboardInterrupt:
        print("\n[follow] Stopped.")


if __name__ == "__main__":
    main()
