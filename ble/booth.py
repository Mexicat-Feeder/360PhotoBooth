#!/usr/bin/env python3
"""
booth.py — drive the 360 booth controller over BLE.

Protocol decoded from btsnoop captures + confirmed by a controlled single-
variable experiment (see ble/protocol.md). Commands are 12-byte frames written
(write-without-response) to fff1.

  !! SAFETY !! `start` spins the physical rig. Clear the platform and keep the
  power switch / e-stop in reach before running.

Examples:
    python3 ble/booth.py --selftest
    python3 ble/booth.py --name "360 Controller" start --dir ccw --speed 5 --secs 8
    python3 ble/booth.py --name "360 Controller" start --dir cw  --speed 2 --secs 6
    python3 ble/booth.py --name "360 Controller" stop
"""
from __future__ import annotations

import argparse
import asyncio
import sys

FFF1 = "0000fff1-0000-1000-8000-00805f9b34fb"   # write + notify on this unit

# byte[2] = action / direction
CMD_CCW = 0x22    # run counter-clockwise
CMD_CW = 0x11     # run clockwise
CMD_STOP = 0x33   # stop


def enc_speed(n: int) -> int:
    """Speed setting N -> byte[3], encoded by the app as N*0x11 == (N<<4)|N.
    Valid app range is 1..9 (0x11..0x99); the controller clamps anything above 9
    to max, so 0xaa..0xff spin no faster than speed 9. Matches controllerv2_UI.py."""
    n = max(1, min(9, n))
    return (n << 4) | n


def build(cmd: int, speed_n: int, secs: int) -> bytes:
    """12-byte frame: AA CC | cmd speed 22 00 secs 11 00 | CHK | CC AA.
    byte[3]=speed (encoded), byte[6]=duration in seconds (controller auto-stops)."""
    secs = max(0, min(255, secs))
    payload = [cmd & 0xFF, enc_speed(speed_n), 0x22, 0x00,
               secs & 0xFF, 0x11, 0x00]
    chk = sum(payload) & 0xFF
    return bytes([0xAA, 0xCC] + payload + [chk, 0xCC, 0xAA])


def run_frame(clockwise: bool, speed_n: int, secs: int) -> bytes:
    return build(CMD_CW if clockwise else CMD_CCW, speed_n, secs)


def stop_frame(speed_n: int = 2) -> bytes:
    # stop echoes the speed byte in captures; value doesn't matter, secs=0
    return build(CMD_STOP, speed_n, 0)


# ---- verification against the real captures (ble/protocol.md) ----
# (cmd, speed_n, secs) -> expected frame, straight from the btsnoop logs
_VECTORS = [
    ((CMD_CCW, 1, 5),  "aa cc 22 11 22 00 05 11 00 6b cc aa"),
    ((CMD_CCW, 2, 5),  "aa cc 22 22 22 00 05 11 00 7c cc aa"),
    ((CMD_CCW, 2, 10), "aa cc 22 22 22 00 0a 11 00 81 cc aa"),
    ((CMD_CW, 2, 5),   "aa cc 11 22 22 00 05 11 00 6b cc aa"),
    ((CMD_CW, 2, 3),   "aa cc 11 22 22 00 03 11 00 69 cc aa"),
    ((CMD_CW, 1, 5),   "aa cc 11 11 22 00 05 11 00 5a cc aa"),
    ((CMD_CW, 5, 5),   "aa cc 11 55 22 00 05 11 00 9e cc aa"),
    ((CMD_CW, 5, 10),  "aa cc 11 55 22 00 0a 11 00 a3 cc aa"),
    ((CMD_STOP, 1, 0), "aa cc 33 11 22 00 00 11 00 77 cc aa"),
    ((CMD_STOP, 5, 0), "aa cc 33 55 22 00 00 11 00 bb cc aa"),
    ((CMD_STOP, 2, 0), "aa cc 33 22 22 00 00 11 00 88 cc aa"),
]


def selftest() -> int:
    ok = True
    for (cmd, spd, secs), expect in _VECTORS:
        got = build(cmd, spd, secs).hex(" ")
        if got != expect:
            ok = False
        print(f"  [{'OK ' if got == expect else 'FAIL'}] "
              f"cmd={cmd:#04x} speed={spd} secs={secs} -> {got}")
    print("self-test:", "PASS" if ok else "FAILED")
    return 0 if ok else 1


async def resolve(name_sub: str):
    from bleak import BleakScanner
    found = await BleakScanner.discover(timeout=12.0, return_adv=True)
    for addr, (dev, adv) in found.items():
        nm = adv.local_name or dev.name or ""
        if name_sub.lower() in nm.lower():
            print(f"resolved '{nm}' -> {addr} (rssi {adv.rssi})")
            return dev
    return None


async def _connect(target, tries=8):
    from bleak import BleakClient
    for i in range(1, tries + 1):
        try:
            c = BleakClient(target, timeout=25.0)
            await c.connect()
            if c.is_connected:
                print(f"connected (try {i})")
                return c
        except Exception:
            print(f"  connect try {i} failed; retrying...")
            await asyncio.sleep(2)
    return None


async def run(target, frames: list[bytes], secs: float) -> None:
    def on_notify(_c, data: bytearray):
        print(f"  <- ack {data.hex(' ')}")

    print("connecting ...")
    c = await _connect(target)
    if c is None:
        print("ERROR: could not connect (booth powered + disconnected from the "
              "Chacktok app + in range?)")
        return
    try:
        try:
            await c.start_notify(FFF1, on_notify)
        except Exception as e:
            print("notify subscribe failed:", e)
        for fr in frames:
            print(f"  -> {fr.hex(' ')}")
            await c.write_gatt_char(FFF1, fr, response=False)
            await asyncio.sleep(0.3)
        if secs > 0 and frames:
            print(f"waiting {secs:.0f}s (controller also auto-stops) ...")
            await asyncio.sleep(secs)
    finally:
        for _ in range(2):
            try:
                await c.write_gatt_char(FFF1, stop_frame(), response=False)
            except Exception:
                pass
            await asyncio.sleep(0.3)
        print("  -> STOP sent")
        try:
            await c.disconnect()
        except Exception:
            pass
    print("disconnected (stopped).")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("action", nargs="?", choices=["start", "stop", "listen"],
                    default="listen")
    ap.add_argument("--addr")
    ap.add_argument("--name", help="resolve by advertised name substring")
    ap.add_argument("--dir", choices=["cw", "ccw"], default="ccw")
    ap.add_argument("--speed", type=int, default=5, help="1..9 (app range; >9 clamps to max)")
    ap.add_argument("--secs", type=int, default=8,
                    help="spin duration in seconds (goes in the frame; "
                         "the controller auto-stops)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if not args.addr and not args.name:
        print("need --addr or --name (run ble/scan.py first)", file=sys.stderr)
        return 2

    if args.action == "start":
        frames = [run_frame(args.dir == "cw", args.speed, args.secs)]
    elif args.action == "stop":
        frames = [stop_frame()]
    else:
        frames = []

    async def _go():
        target = args.addr or await resolve(args.name)
        if target is None:
            print("controller not found in scan", file=sys.stderr)
            return
        await run(target, frames, args.secs if args.action == "start" else 0)

    asyncio.run(_go())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
