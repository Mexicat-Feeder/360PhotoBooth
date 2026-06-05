#!/usr/bin/env python3
"""
parse_btsnoop.py — decode an Android btsnoop_hci.log into the BLE commands an app
sent to a peripheral. Built to extract the 360-booth spin protocol from a
capture of the Chacktok app driving the controller.

Handles multiple simultaneous BLE connections (the phone is usually talking to
more than just the booth), so everything is keyed by connection handle and you
can filter to one peer.

Pulls out:
  - LE connections (conn handle -> peer MAC)
  - characteristic declarations per connection (value handle -> UUID)
  - a timeline of every ATT Write Request/Command (app -> device)
    and Handle Value Notification/Indication (device -> app)

Usage:
    python3 ble/parse_btsnoop.py btsnoop_hci.log
    python3 ble/parse_btsnoop.py btsnoop_hci.log --peer 2F:87:34:C3:85:28
    python3 ble/parse_btsnoop.py btsnoop_hci.log --writes-only
"""
from __future__ import annotations

import struct
import sys

U16 = lambda b, i: b[i] | (b[i + 1] << 8)          # little-endian


def ascii_of(b: bytes) -> str:
    return "".join(chr(c) if 32 <= c < 127 else "." for c in b)


def read_records(path: str):
    with open(path, "rb") as f:
        hdr = f.read(16)
        if hdr[:8] != b"btsnoop\x00":
            raise SystemExit("not a btsnoop file")
        while True:
            rec = f.read(24)
            if len(rec) < 24:
                break
            orig_len, incl_len, flags, drops, ts = struct.unpack(">IIIIq", rec)
            data = f.read(incl_len)
            if len(data) < incl_len:
                break
            yield flags, ts, data


class Parser:
    def __init__(self):
        self.conns = {}      # conn handle -> peer mac
        self.chars = {}      # (conn, value_handle) -> uuid
        self.events = []     # (ts, conn, kind, dir, handle, value)
        self.t0 = None
        self.reasm = {}
        self.need = {}

    def feed(self, flags, ts, data):
        if not data:
            return
        if self.t0 is None:
            self.t0 = ts
        rel = (ts - self.t0) / 1e6
        direction = "rx" if (flags & 0x01) else "tx"   # rx = device->app
        h4, body = data[0], data[1:]

        if h4 == 0x04:        # HCI event: capture LE Connection Complete
            if len(body) >= 3 and body[0] == 0x3e and body[2] in (0x01, 0x0a):
                p = body[3:]
                if len(p) >= 11 and p[0] == 0:
                    chandle = U16(p, 1)
                    mac = ":".join(f"{x:02X}" for x in reversed(p[5:11]))
                    self.conns[chandle] = mac
            return
        if h4 != 0x02:        # only ACL carries ATT
            return
        if len(body) < 4:
            return
        hf = U16(body, 0)
        chandle = hf & 0x0FFF
        pb = (hf >> 12) & 0x3
        acl = body[4:4 + U16(body, 2)]

        if pb in (0x0, 0x2):
            buf = bytearray(acl)
            need = (U16(buf, 0) + 4) if len(buf) >= 2 else 0
            if len(buf) >= need:
                self._att(buf, chandle, direction, rel)
            else:
                self.reasm[chandle], self.need[chandle] = buf, need
        elif pb == 0x1 and chandle in self.reasm:
            self.reasm[chandle] += acl
            if len(self.reasm[chandle]) >= self.need[chandle]:
                self._att(self.reasm[chandle], chandle, direction, rel)
                del self.reasm[chandle]

    def _att(self, buf, conn, direction, rel):
        if len(buf) < 4:
            return
        l2_len, cid = U16(buf, 0), U16(buf, 2)
        att = buf[4:4 + l2_len]
        if cid != 0x0004 or not att:
            return
        op = att[0]
        names = {0x12: "WriteReq", 0x52: "WriteCmd", 0x1b: "Notify",
                 0x1d: "Indicate"}
        if op in names and len(att) >= 3:
            self.events.append((rel, conn, names[op], direction,
                                U16(att, 1), bytes(att[3:])))
        elif op == 0x09 and len(att) >= 2:   # Read By Type Resp (char decls)
            ilen, i = att[1], 2
            while i + ilen <= len(att):
                item = att[i:i + ilen]
                if ilen in (7, 21):
                    vh = U16(item, 3)
                    if ilen == 7:
                        uuid = f"0000{U16(item,5):04x}-0000-1000-8000-00805f9b34fb"
                    else:
                        r = item[5:21]
                        uuid = "-".join([bytes(reversed(r[12:16])).hex(),
                                         bytes(reversed(r[10:12])).hex(),
                                         bytes(reversed(r[8:10])).hex(),
                                         bytes(reversed(r[6:8])).hex(),
                                         bytes(reversed(r[0:6])).hex()])
                    self.chars[(conn, vh)] = uuid
                i += ilen


def main(path, peer, writes_only):
    p = Parser()
    for flags, ts, data in read_records(path):
        p.feed(flags, ts, data)

    print("=== LE connections (conn handle -> peer MAC) ===")
    for h, mac in p.conns.items():
        print(f"  handle 0x{h:04x} -> {mac}")

    want = {h for h, m in p.conns.items()
            if peer is None or m.upper() == peer.upper()}

    print("\n=== characteristic declarations (value handle -> UUID) ===")
    for (conn, vh), u in sorted(p.chars.items()):
        if conn in want:
            print(f"  conn 0x{conn:04x} handle 0x{vh:04x} -> {u}")

    print("\n=== ATT timeline (tx = app->device, rx = device->app) ===")
    print(f"{'t(s)':>8} conn  dir {'op':<9} {'hdl':>6}  value")
    print("-" * 76)
    for ts, conn, kind, direction, hdl, val in p.events:
        if conn not in want:
            continue
        if writes_only and not kind.startswith("Write"):
            continue
        uuid = p.chars.get((conn, hdl), "")
        tag = f"  <{uuid[4:8]}>" if uuid else ""
        print(f"{ts:8.3f} {conn:04x}  {direction}  {kind:<9} 0x{hdl:04x}  "
              f"{val.hex(' ')}  | {ascii_of(val)!r}{tag}")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        print("usage: parse_btsnoop.py <log> [--peer MAC] [--writes-only]")
        sys.exit(2)
    peer = None
    if "--peer" in a:
        peer = a[a.index("--peer") + 1]
    main(a[0], peer, "--writes-only" in a)
