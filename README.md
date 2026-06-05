# 360 Photobooth — BLE bring-up (Phase 0)

Goal of this phase: **prove we can connect to the booth's motor controller from
software and discover the spin command**, before building the Flutter app. If we
can't drive the motor, nothing downstream matters — so we do this first.

This is the fresh start. Old prototype lives one directory up; ignore it.

---

## What we already know (from probing this machine + the controller's radio)

- **This Linux box can do BLE.** It has a **Bluetooth 5.4** adapter (`hci0`,
  MediaTek), **BlueZ 5.72**, and Python 3.12. `bleak` 3.0 is installed. We ran a
  live scan successfully — so connecting/exploring works natively here, no phone
  required for that part.
- **The controller is a KT6368A module.** A live scan saw
  `360 Controller_X290` (BLE) right next to `KT6368A-SPP-2.1` (Classic) with
  near-identical MACs — i.e. the two faces of one **KT6368A "BLE + SPP
  transparent serial" chip**. Your unit is the same family (it advertises
  `360 Controller-8132`).
- **What that means:** the controller is a **UART bridge**. Spin/speed/direction
  commands are just **bytes written to one BLE characteristic**, forwarded to the
  motor MCU over serial. For a KT6368A the transparent-UART layout is:
  - service `0000fff0-…`
  - `0000fff1-…`  **notify**  ← data *from* the controller
  - `0000fff2-…`  **write**   ← data *to* the controller (this is where spin commands go)
- **315 MHz is NOT this.** That's the separate handheld RF keyfob. The app uses
  **BLE only.** Ignore 315 MHz unless we ever go the "emulate the remote" route.

---

## What you physically need for this phase

1. **The booth powered on** (controller is DC24V — the BLE module only
   advertises when powered) and **within ~10 m of this machine**. NOTE: this box
   is a desktop workstation, so either bring the booth to it or run these same
   scripts from a laptop near the booth.
2. That's it for **connect + GATT discovery** (steps 1–2 below).
3. For **discovering the exact command bytes** the clean way (step 3, option A):
   an **Android phone** with the **Chacktok app** installed + a **USB cable**,
   plus `adb` and `tshark` on this box (`sudo apt install android-tools-adb
   tshark`). The phone captures; this box analyzes.

---

## The procedure

### Step 1 — Find the controller
Power the booth, then:
```bash
python3 ble/scan.py 15
```
Look for `360 Controller-8132` (flagged `<-- LIKELY CONTROLLER`). Note its
ADDRESS.

### Step 2 — Dump its GATT (read-only, safe)
```bash
python3 ble/explore.py <ADDRESS>
# or: python3 ble/explore.py --name "360 Controller"
```
This sends **no** commands. It lists every service/characteristic, reads the
readable ones, and watches notifications for 6 s. **Confirm** you see the
`fff0/fff1/fff2` trio (or note the real UUIDs if they differ). Success here =
"we can connect." That's the gate this phase exists to clear.

### Step 3 — Discover the spin command
Two ways; **A is recommended** (exact, low-risk).

**A. Sniff the Chacktok app (needs the Android phone):**
1. Phone → Settings → Developer options → **Enable Bluetooth HCI snoop log**.
   Toggle Bluetooth off/on.
2. Drive the booth with the **Chacktok app**, doing each action distinctly and
   noting the order: connect → set speed → set direction → set duration →
   **Start** → **Stop**.
3. Pull + analyze on this box:
   ```bash
   adb bugreport bugreport.zip          # contains the btsnoop log
   # unzip, find FS/data/.../btsnoop_hci.log, then:
   tshark -r btsnoop_hci.log -Y 'btatt.opcode.method == 0x12 || btatt.opcode.method == 0x52' \
          -T fields -e frame.number -e btatt.handle -e btatt.value
   ```
   (opcodes 0x12 = Write Request, 0x52 = Write Command.) The `btatt.value`
   column is the **exact bytes per action** — that's the protocol.
4. Write the decoded frames into `frames.txt` (one hex frame per line) and the
   findings into `ble/protocol.md`.

**B. Active probing from Linux (no phone, but blind):**
Only with the platform clear and power switch in reach:
```bash
python3 ble/probe.py <ADDRESS>            # interactive: type hex frames
python3 ble/probe.py <ADDRESS> --file frames.txt
```
Watch `fff1` notifications and the motor. Slower and riskier than A; use A if you
can. (You can also just **ask Chacktok** for the command set — it may be a one-
line answer.)

### Step 4 — Replay to confirm
Replay the captured Start frame from this machine:
```bash
python3 ble/probe.py <ADDRESS> --send "<the start frame hex>"
```
If the booth spins on our command → **Phase 0 done.** The frames go straight into
the Flutter `flutter_blue_plus` module later (same UUIDs, same bytes, both OSes).

---

## STATUS: protocol decoded ✅ (2026-06-05)
We captured the Chacktok app driving the lab booth (Android btsnoop log) and
**fully decoded the command protocol** — see **`ble/protocol.md`**. Commands are
12-byte frames written to characteristic `fff1`, with a trivial additive
checksum, no encryption. `ble/booth.py --selftest` reproduces every captured
frame exactly. **The only thing left for Phase 0 is a live replay** to watch the
rig physically spin (do this from the machine nearest the booth).

### Live replay test (the final Phase-0 gate)
From the machine next to the booth, with the booth powered and the Chacktok app
**disconnected** (so the controller advertises):
```bash
python3 ble/booth.py --name "360 Controller" start --speed 5 --secs 5
# spins ~5s at speed 5 then auto-sends STOP.   Clear the platform first!
```
If it spins → Phase 0 complete; the same frames drop straight into the Flutter
`flutter_blue_plus` layer.

## Files
| File | Purpose |
|---|---|
| `ble/scan.py` | find controllers in range, print adv data |
| `ble/explore.py` | connect + dump GATT (read-only, no commands) |
| `ble/parse_btsnoop.py` | decode an Android btsnoop_hci.log → ATT commands (how we got the protocol) |
| `ble/protocol.md` | **the decoded command set** (the deliverable) |
| `ble/booth.py` | build + send spin/stop frames (CAN MOVE THE MOTOR); `--selftest` verifies frames |
| `ble/probe.py` | low-level: send/replay arbitrary frames to `fff1` (CAN MOVE THE MOTOR) |
| `requirements.txt` | `bleak` |
