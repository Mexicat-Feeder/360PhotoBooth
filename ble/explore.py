#!/usr/bin/env python3
"""
explore.py — connect to a controller and dump its full GATT table (READ-ONLY).

This makes NO writes and sends NO motor commands. It connects, enumerates every
service / characteristic / descriptor, reads any readable characteristic, and
subscribes to every notify/indicate characteristic for a few seconds so we can
see what the device pushes on its own. Safe to run against any unit.

For a KT6368A transparent-serial module expect:
    service  0000fff0-...   (transparent UART)
      char   0000fff1-...   notify   <- data FROM the controller
      char   0000fff2-...   write    <- data TO the controller (spin commands)
plus the standard 1800 (Generic Access) / 1801 (Generic Attribute) services.

Usage:
    python3 ble/explore.py <ADDRESS>
    python3 ble/explore.py 2F:87:34:C3:85:28
    python3 ble/explore.py --name "360 Controller"   # resolve by name first
"""
from __future__ import annotations

import argparse
import asyncio
import sys

from bleak import BleakClient, BleakScanner

PROP_ORDER = ["read", "write-without-response", "write", "notify", "indicate"]


def _notify_cb(label: str):
    def cb(_char, data: bytearray) -> None:
        print(f"  [notify] {label}: {data.hex(' ')}  | ascii={_safe_ascii(data)}")
    return cb


def _safe_ascii(b: bytes) -> str:
    return "".join(chr(c) if 32 <= c < 127 else "." for c in b)


async def resolve(name_sub: str) -> str | None:
    print(f"resolving address for name containing '{name_sub}' ...")
    found = await BleakScanner.discover(timeout=10.0, return_adv=True)
    for addr, (dev, adv) in found.items():
        nm = (adv.local_name or dev.name or "")
        if name_sub.lower() in nm.lower():
            print(f"  -> {addr}  ({nm})")
            return addr
    print("  not found.")
    return None


async def main(address: str) -> None:
    print(f"connecting to {address} ...")
    async with BleakClient(address, timeout=20.0) as client:
        print(f"connected: {client.is_connected}\n")

        notify_chars = []
        for svc in client.services:
            print(f"service {svc.uuid}  ({svc.description})")
            for ch in svc.characteristics:
                props = ",".join(p for p in PROP_ORDER if p in ch.properties)
                extra = ",".join(p for p in ch.properties if p not in PROP_ORDER)
                allp = props + ((";" + extra) if extra else "")
                line = f"  char {ch.uuid}  [{allp}]  handle={ch.handle}"
                val = ""
                if "read" in ch.properties:
                    try:
                        raw = await client.read_gatt_char(ch)
                        val = f"  = {raw.hex(' ')} | {_safe_ascii(raw)!r}"
                    except Exception as e:
                        val = f"  (read failed: {e})"
                print(line + val)
                for d in ch.descriptors:
                    print(f"      descriptor {d.uuid}  handle={d.handle}")
                if "notify" in ch.properties or "indicate" in ch.properties:
                    notify_chars.append(ch)

        if notify_chars:
            print("\nsubscribing to notify/indicate chars for 6s "
                  "(watching for unsolicited data)...")
            for ch in notify_chars:
                try:
                    await client.start_notify(ch, _notify_cb(ch.uuid))
                except Exception as e:
                    print(f"  could not subscribe {ch.uuid}: {e}")
            await asyncio.sleep(6)
            for ch in notify_chars:
                try:
                    await client.stop_notify(ch)
                except Exception:
                    pass

        print("\ndone. (no writes were sent)")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("address", nargs="?", help="BLE MAC / address")
    ap.add_argument("--name", help="resolve address by advertised name substring")
    args = ap.parse_args()

    addr = args.address
    if not addr and args.name:
        addr = asyncio.run(resolve(args.name))
    if not addr:
        print("give an ADDRESS or --name. Run ble/scan.py first.", file=sys.stderr)
        sys.exit(2)
    asyncio.run(main(addr))
