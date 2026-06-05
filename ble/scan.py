#!/usr/bin/env python3
"""
scan.py — find 360 photo-booth controllers (and any BLE device) in range.

The Chacktok / generic 360 booths use a KT6368A "BLE + SPP transparent serial"
module. It advertises a name like "360 Controller_XXXX" (BLE side) and
"KT6368A-SPP-X.X" (Classic side). This script lists everything, highlights the
likely controllers, and prints the advertised service UUIDs + manufacturer data
so we know what we're connecting to before we connect.

Usage:
    python3 ble/scan.py            # 10 s scan
    python3 ble/scan.py 20         # 20 s scan
"""
from __future__ import annotations

import asyncio
import sys

from bleak import BleakScanner

# Substrings that flag a probable 360-booth controller.
HINTS = ("360 controller", "kt6368", "spinner", "booth")


async def main(timeout: float) -> None:
    print(f"scanning for {timeout:.0f}s ...\n")
    found = await BleakScanner.discover(timeout=timeout, return_adv=True)

    rows = []
    for addr, (dev, adv) in found.items():
        name = adv.local_name or dev.name or "(no name)"
        rows.append((adv.rssi or -999, addr, name, adv))

    rows.sort(reverse=True)  # strongest signal first

    print(f"{'RSSI':>5}  {'ADDRESS':<18}  NAME")
    print("-" * 70)
    for rssi, addr, name, adv in rows:
        flag = "  <-- LIKELY CONTROLLER" if any(
            h in name.lower() for h in HINTS) else ""
        print(f"{rssi:>5}  {addr:<18}  {name}{flag}")
        if flag:
            if adv.service_uuids:
                print(f"        service UUIDs: {adv.service_uuids}")
            if adv.manufacturer_data:
                for k, v in adv.manufacturer_data.items():
                    print(f"        mfr 0x{k:04x}: {v.hex()}")
    print(f"\n{len(rows)} devices seen. "
          "Note the ADDRESS of your controller for explore.py / probe.py.")


if __name__ == "__main__":
    t = float(sys.argv[1]) if len(sys.argv) > 1 else 10.0
    asyncio.run(main(t))
