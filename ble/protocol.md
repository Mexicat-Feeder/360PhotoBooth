# 360 Booth BLE Protocol (Chacktok controller `360 Controller_X290`)

Reverse-engineered from two Android `btsnoop_hci.log` captures of the **Chacktok
app** driving the lab booth (2026-06-05), and confirmed by a **controlled
single-variable experiment** (capture 2 = "Bluetooth report 2.0"). Fully decoded,
no encryption, trivial checksum.

## Device
- BLE name: `360 Controller_X290` (box label says "360 Controller-8132"; the
  advertised name differs — this is the lab's only booth). Match by **name**.
- MAC seen: `2F:87:34:C3:85:28` (rotating/private — do not hardcode).
- Chip: KT6368A (BLE + SPP transparent serial).

## GATT
| Handle | UUID | Use |
|---|---|---|
| 0x0003 | `0000fff1-…` | **write commands here** (Write Without Response) **and** notifications |
| 0x0004 | CCCD of fff1 | write `01 00` to enable notifications |
| 0x0006 | `0000fff2-…` | present, unused by app |
| 0x0009 | `0000fff3-…` | present, unused by app |

## Frame format (12 bytes, fixed)
```
 byte:  0   1   2     3      4    5    6     7    8    9    10  11
       AA  CC  cmd  speed   22   00  secs   11   00  CHK   CC  AA
```
- **CHK** = `(sum of bytes[2..8]) & 0xFF`
- **byte[2] `cmd`** — action + direction (all confirmed live + by experiment):
  - `0x22` = run **counter-clockwise**
  - `0x11` = run **clockwise**
  - `0x33` = **stop**
- **byte[3] `speed`** — speed setting N encoded as `N*0x11` == `(N<<4)|N`:
  speed 1 = `0x11`, 2 = `0x22`, 5 = `0x55`, **9 = `0x99` (app max)**.
  Valid app range is **1..9**. Values above 9 (`0xaa`..`0xff`) are **clamped to max**
  by the controller — they spin no faster than speed 9 (this is why an earlier
  10/12/15 ramp showed no further increase). The RPM spread from 1→9 is real but
  modest on this rig. (Proven: changing only the app speed slider 1→5 changed *only*
  this byte `0x11`→`0x55`.) Matches the lab's `controllerv2_UI.py` exactly.
- **byte[6] `secs`** — spin **duration in seconds**; the controller **auto-stops**
  after this many seconds. `0x00` on stop.
  (Proven: changing only the app time 5→10 changed *only* this byte, `0x05`→`0x0a`.)
  The app ALSO sends an explicit `stop` frame at the end (redundant safety).
- bytes [4]=`0x22`, [5]=`0x00`, [7]=`0x11`, [8]=`0x00` constant. byte[3] on a stop
  frame just echoes the last speed (value irrelevant).

## Ack
After every command the controller notifies on fff1 with a constant 7-byte ack
`f7 34 c3 85 28 2f 87` = "received".

## Controlled experiment (capture 2) — the proof
Record (columns = speed, direction, time):
| run | speed | dir | time | start frame |
|----|----|----|----|----|
| 1 | 1 | ccw | 5  | `aa cc 22 11 22 00 05 11 00 6b cc aa` |
| 2 | 1 | cw  | 5  | `aa cc 11 11 22 00 05 11 00 5a cc aa` |
| 3 | 5 | cw  | 5  | `aa cc 11 55 22 00 05 11 00 9e cc aa` |
| 4 | 5 | cw  | 10 | `aa cc 11 55 22 00 0a 11 00 a3 cc aa` |

1→2 flips byte[2] (direction). 2→3 flips byte[3] (speed). 3→4 flips byte[6] (time).
Clean one-byte-per-change = unambiguous mapping.

## Status: FULLY DECODED ✅
`ble/booth.py --selftest` reproduces **all 11 frames from both captures** exactly.

### Minimal driver (what the Flutter app does)
1. scan, match peripheral by **name** "360 Controller"
2. connect (retry — BlueZ/cheap module connects are flaky), enable notify on fff1
3. write-without-response to fff1:
   - spin = `build(0x22|0x11, speed_N, duration_secs)`  (auto-stops after duration)
   - stop = `build(0x33, anything, 0)`
4. controller auto-stops at `secs`; app should also send `stop` as a backup.

### Note / correction
An earlier pass mislabeled byte[6] as "speed" — it is **duration**. That's why
on-device "speed" sweeps showed no change (they were varying the timer). Speed is
**byte[3]**.
