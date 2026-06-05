#!/usr/bin/env python3
"""
probe.py — send raw frames to the controller and watch its replies.

This is the ACTIVE step: it writes bytes to the write characteristic (FFF2 on a
KT6368A) and prints anything that comes back on the notify characteristic
(FFF1). Use it to (a) replay frames captured from the Chacktok app, or (b)
experiment to find the spin command.

  !! SAFETY !!
  This can make the booth motor move. Before running:
    - confirm the unit is YOURS,
    - clear the platform (nobody/nothing on the spinner),
    - keep the physical power switch / e-stop within reach,
    - start with short/low-speed frames.

Examples:
    # interactive: type hex frames, press enter to send; 'q' to quit
    python3 ble/probe.py <ADDRESS>

    # one-shot: send a single frame then listen 5s
    python3 ble/probe.py <ADDRESS> --send "aa 01 64 01 0a 55"

    # replay a file of frames (one hex frame per line, # = comment)
    python3 ble/probe.py <ADDRESS> --file frames.txt

Write/notify UUIDs default to the KT6368A layout; override if explore.py
shows different ones.
"""
from __future__ import annotations

import argparse
import asyncio
import sys

from bleak import BleakClient

# This lab's unit uses fff1 for BOTH write and notify (confirmed via btsnoop;
# see ble/protocol.md). The generic KT6368A default is fff2-write/fff1-notify —
# override with --write-uuid if explore.py shows otherwise on a different unit.
WRITE_UUID = "0000fff1-0000-1000-8000-00805f9b34fb"   # data TO controller
NOTIFY_UUID = "0000fff1-0000-1000-8000-00805f9b34fb"  # data FROM controller


def _ascii(b: bytes) -> str:
    return "".join(chr(c) if 32 <= c < 127 else "." for c in b)


def _parse_frame(s: str) -> bytes:
    s = s.strip()
    if not s:
        return b""
    # accept "aa 01 64", "aa0164", or "0xAA,0x01"
    s = s.replace("0x", "").replace(",", " ")
    if " " in s:
        return bytes(int(x, 16) for x in s.split())
    return bytes.fromhex(s)


def _notify_cb(_char, data: bytearray) -> None:
    print(f"  <- {data.hex(' ')}  | {_ascii(data)!r}")


async def run(address: str, write_uuid: str, notify_uuid: str,
              frames: list[bytes], interactive: bool) -> None:
    print(f"connecting to {address} ...")
    async with BleakClient(address, timeout=20.0) as client:
        print(f"connected: {client.is_connected}")
        try:
            await client.start_notify(notify_uuid, _notify_cb)
            print(f"listening on {notify_uuid}")
        except Exception as e:
            print(f"!! could not subscribe to {notify_uuid}: {e}")

        async def send(frame: bytes) -> None:
            if not frame:
                return
            print(f"  -> {frame.hex(' ')}")
            # write-with-response first; fall back to without-response
            try:
                await client.write_gatt_char(write_uuid, frame, response=True)
            except Exception:
                await client.write_gatt_char(write_uuid, frame, response=False)

        for fr in frames:
            await send(fr)
            await asyncio.sleep(1.0)

        if interactive:
            print("\ninteractive mode. type a hex frame and Enter to send.")
            print("  's' = re-show UUIDs, 'q' = quit\n")
            loop = asyncio.get_event_loop()
            while True:
                line = await loop.run_in_executor(None, sys.stdin.readline)
                if not line:
                    break
                line = line.strip()
                if line in ("q", "quit", "exit"):
                    break
                if line == "s":
                    print(f"  write={write_uuid} notify={notify_uuid}")
                    continue
                try:
                    await send(_parse_frame(line))
                except ValueError as e:
                    print(f"  bad frame: {e}")
        else:
            await asyncio.sleep(5)

        try:
            await client.stop_notify(notify_uuid)
        except Exception:
            pass
    print("disconnected.")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("address", help="BLE MAC / address (from scan.py)")
    ap.add_argument("--send", help="single hex frame to send")
    ap.add_argument("--file", help="file of hex frames, one per line (# comment)")
    ap.add_argument("--write-uuid", default=WRITE_UUID)
    ap.add_argument("--notify-uuid", default=NOTIFY_UUID)
    args = ap.parse_args()

    frames: list[bytes] = []
    if args.send:
        frames.append(_parse_frame(args.send))
    if args.file:
        for ln in open(args.file):
            ln = ln.split("#", 1)[0].strip()
            if ln:
                frames.append(_parse_frame(ln))

    interactive = not (args.send or args.file)
    asyncio.run(run(args.address, args.write_uuid, args.notify_uuid,
                    frames, interactive))
