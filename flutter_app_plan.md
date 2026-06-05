# Flutter App — Build & Test Plan

The BLE control is solved (`ble/protocol.md`, `ble/booth.py`, `ble/controllerv2_UI.py`).
Now we build the cross-platform app. This doc covers **how we test on Linux**
(the big question), the **stack**, and the **build milestones**.

---

## 1. How we test — the key facts

Two real constraints (NOT "Linux can't do BLE" — we already drove the booth from
this box via Python `bleak`/BlueZ):

> 1. **Emulators have no Bluetooth radio.** A Flutter app in an Android emulator
>    (or iOS simulator) cannot do BLE at all — no host passthrough. Emulator =
>    UI/flow only.
> 2. **`flutter_blue_plus` doesn't target Linux desktop** (Android/iOS/macOS/
>    Windows only). But **other Flutter BLE packages DO support Linux** via BlueZ:
>    **`universal_ble`** (Android/iOS/macOS/Windows/Linux/web) and `quick_blue`.

So we **can** run a Flutter **Linux desktop build on this box that really controls
the booth** (same BlueZ stack `bleak` used) — great for fast BLE iteration without
a phone. What each target can do:

| Target | BLE | Camera | Use it for |
|---|---|---|---|
| **Flutter Linux desktop build** (this box) | ✅ real (universal_ble/quick_blue) | ✅ webcam | real booth control + UI, fast iteration, no phone |
| **Android emulator** (this box) | ❌ no radio | ✅ host webcam | UI/flow only, with FakeBooth |
| **Physical Android tablet** (Pixel 9) | ✅ real | ✅ real | production target; final end-to-end validation |

**Strategy: a BLE abstraction so the package + platform are swappable.**
- `BoothController` (interface): `scan()`, `connect()`, `spin(dir, speed, secs)`,
  `stop()`, connection-state stream.
- `RealBoothController` — a Linux+mobile BLE package (**`universal_ble`**
  preferred so the *same* code runs on this box AND the tablet), a direct port of
  `booth.py`. (Fallback: `flutter_blue_plus` on Android only — one-file swap
  behind the interface.)
- `FakeBoothController` — logs commands, emits simulated "spinning" (for the
  emulator / pure-UI work).

Day-to-day: iterate real BLE on the **Linux desktop build right here**, iterate UI
fast on the **emulator with FakeBooth**, and do final validation on the **tablet**.

### The dev loop — how you SEE the app (no phone needed)
- `flutter run -d linux` → app opens **as a window on this PC**, **hot-reload <1s**
  on save. This is the main way you'll watch it; with `universal_ble` it can also
  really drive the booth.
- `flutter run` (emulator) → a **phone-shaped** screen on this PC for checking the
  portrait layout (FakeBooth for BLE, webcam for camera).
- A real Android is only plugged in (USB or wireless adb) for **final on-device
  validation**, not daily work.

**Also handy:** the tablet connects over **USB or wireless adb** (`adb pair` /
`adb connect`) — with wireless adb it can sit at the booth while you code across
the room; only the phone needs BLE range.

---

## 2. Stack

> **One codebase, many targets.** The same Dart source compiles to Linux desktop
> (our dev/preview + real BLE here), Android (the tablet APK), and iOS — no
> rewrite or "conversion." Only per-platform glue differs: permission manifests
> (Android `AndroidManifest.xml` / iOS `Info.plist`), window-vs-kiosk, and
> responsive layout (design portrait-first for the tablet). The `BoothController`
> abstraction + `universal_ble` keep the BLE code identical across all of them.

- **Flutter (Dart)** — single codebase, iOS port later = rebuild + Info.plist perms.
- Packages:
  - `universal_ble` — BLE (the booth); cross-platform incl. **Linux** so we can
    test real booth control in a Linux desktop build on this box. (`flutter_blue_plus`
    is the Android-only fallback, swappable behind `BoothController`.)
  - `camera` — record the guest (1080p30)
  - `permission_handler` — BLE + camera + mic + (Android 12+) BLUETOOTH_SCAN/CONNECT
  - `dio` — multipart upload + progress to the AMD backend
  - `qr_flutter` — result handoff
  - `riverpod` — app state / the flow state machine
  - `path_provider` — temp video file location

---

## 3. BLE port (the heart, already proven)
`RealBoothController` mirrors `booth.py` exactly:
- scan, match peripheral by **name contains "360 Controller"** (addr is random)
- connect with **retry** (cheap KT6368A module is flaky), enable notify on `fff1`
- frame builder: `AA CC | dir speed 22 00 secs 11 00 | CHK | CC AA`,
  `dir` = `0x22` ccw / `0x11` cw / `0x33` stop, `speed = N*0x11` (N 1..9),
  `secs` = duration, `CHK = sum(bytes[2..8]) & 0xFF`
- write **without response** to `fff1`; controller auto-stops after `secs`; also
  send an explicit `stop` as backup.

---

## 4. Build milestones

### F0 — Toolchain + scaffold (this Linux box)
- Install: JDK 17, Flutter SDK, Android cmdline-tools + platform-tools, an
  emulator image; `flutter doctor` clean; accept Android licenses.
- For the **Linux desktop build** (our real-BLE dev target): `clang cmake ninja-build
  pkg-config libgtk-3-dev` (apt — needs sudo). BLE there uses the existing BlueZ.
- `flutter create app` in the repo (`app/`). Add the packages above.
- Wire Android permissions in `AndroidManifest.xml` (BLUETOOTH_SCAN/CONNECT with
  `neverForLocation`, CAMERA, RECORD_AUDIO, INTERNET).

### F1 — BLE in-app (port booth.py) → test on the **Linux desktop build** first
- `BoothController` + `Real` (universal_ble) + `Fake`.
- A minimal **Booth Test screen**: connection status, CW/CCW buttons, speed
  slider (1–9), spin/stop. This is "booth.py, in the app."
- **Gate:** `flutter run -d linux` on **this box** → the app spins the rig (BlueZ,
  exactly as our Python did). Then confirm the same build on the **tablet**.

### F2 — Core UX flow (emulator + FakeBooth)
- Riverpod state machine + screens:
  Attract → Info entry (name, email/phone) → "step on the platform" countdown →
  **Recording+Spin** (start camera recording + `spin()`, timed) → stop → Uploading
  → Generating (live preview) → Result (video + QR) → back to Attract.
- Camera record 1080p30; lock exposure/WB before spin; sync start/stop with `spin`.

### F3 — Backend integration
- `POST /jobs` multipart upload (video + guest info), SSE progress (incl. ComfyUI
  live preview frames), result fetch + QR. Backend = the reused FastAPI (can stub
  a local mock first so this is testable on the emulator).

### F4 — Integration + hardening + iOS pass
- Full end-to-end on the Pixel next to the booth + backend on the LAN.
- Auto-reconnect BLE, error/timeout states, kiosk/full-screen, "skip AI" fallback.
- iOS: add Info.plist usage strings; build on a Mac when ready.

### Test matrix per milestone
| Milestone | Where tested |
|---|---|
| F0 scaffold | emulator / linux build (app boots) |
| F1 BLE | **Linux desktop build on this box** (real booth), then tablet |
| F2 UX | emulator + FakeBooth (+ webcam) |
| F3 backend | emulator + backend on LAN |
| F4 integration | **tablet near booth + backend** |

---

## 5. Open choices
- **Dev device:** use the **Pixel 9** (already our capture phone) as the BLE test
  device? (Recommended.)
- **App on the spinning arm** (Topology A) is still the plan — the test device
  doubles as the eventual booth device.
- **Backend** not built yet for this app; F2 can run fully on a mock so we don't
  block on it.
