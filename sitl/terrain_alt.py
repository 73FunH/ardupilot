#!/usr/bin/env python3
"""Print the SRTM terrain altitude (AMSL, meters, rounded) for a lat/lon.
Exits non-zero with no stdout output if the lookup fails (e.g. no network
and no cached tile), so callers can fall back to a default altitude.

Usage: terrain_alt.py <lat> <lon>
"""
import os
import sys
import time


def main():
    if len(sys.argv) != 3:
        print("Usage: terrain_alt.py <lat> <lon>", file=sys.stderr)
        sys.exit(1)
    lat, lon = float(sys.argv[1]), float(sys.argv[2])

    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    cachedir = os.path.join(repo, "Tools", "autotest", "tilecache", "srtm")

    from MAVProxy.modules.mavproxy_map import srtm

    downloader = srtm.SRTMDownloader(cachedir=cachedir)
    downloader.loadFileList()

    # getTile() downloads the tile asynchronously and returns 0 until ready.
    deadline = time.time() + 30
    tile = None
    while time.time() < deadline:
        tile = downloader.getTile(lat, lon)
        if tile:
            break
        time.sleep(0.2)
    if not tile:
        print("terrain_alt: timed out waiting for SRTM tile", file=sys.stderr)
        sys.exit(1)

    alt = tile.getAltitudeFromLatLon(lat, lon)
    print(round(alt))


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f"terrain_alt: lookup failed: {e}", file=sys.stderr)
        sys.exit(1)
