import argparse
import asyncio
from dataclasses import dataclass

from bleak import BleakClient, BleakScanner


DEVICE_NAME = "360 Controller_X290"
DEVICE_ADDRESS = "2F:87:34:C3:85:28"
WRITE_CHAR_UUID = "0000fff1-0000-1000-8000-00805f9b34fb"


@dataclass(frozen=True)
class CapturedCommand:
    label: str
    frame: bytes
    note: str


CAPTURED_COMMANDS = {
    "start-ccw-speed1-5s": CapturedCommand(
        "start-ccw-speed1-5s",
        bytes.fromhex("aacc221122000511006bccaa"),
        "Captured start: speed 1, counterclockwise, duration 5.",
    ),
    "stop-speed1": CapturedCommand(
        "stop-speed1",
        bytes.fromhex("aacc3311220000110077ccaa"),
        "Captured stop while speed was 1: action 0x33, speed byte 0x11.",
    ),
    "start-cw-speed1-5s": CapturedCommand(
        "start-cw-speed1-5s",
        bytes.fromhex("aacc111122000511005accaa"),
        "Captured start: speed 1, clockwise, duration 5.",
    ),
    "start-cw-speed5-5s": CapturedCommand(
        "start-cw-speed5-5s",
        bytes.fromhex("aacc115522000511009eccaa"),
        "Captured start: speed 5, clockwise, duration 5.",
    ),
    "start-cw-speed5-10s": CapturedCommand(
        "start-cw-speed5-10s",
        bytes.fromhex("aacc115522000a1100a3ccaa"),
        "Captured start: speed 5, clockwise, duration 10.",
    ),
    "stop-speed5": CapturedCommand(
        "stop-speed5",
        bytes.fromhex("aacc33552200001100bbccaa"),
        "Captured stop while speed was 5: action 0x33, speed byte 0x55.",
    ),
    "start-a-5s": CapturedCommand(
        "start-a-5s",
        bytes.fromhex("aacc221122000511006bccaa"),
        "Legacy alias: captured speed 1, counterclockwise, duration 5.",
    ),
    "stop-a": CapturedCommand(
        "stop-a",
        bytes.fromhex("aacc3311220000110077ccaa"),
        "Legacy alias: captured stop while speed was 1.",
    ),
    "start-b-5s": CapturedCommand(
        "start-b-5s",
        bytes.fromhex("aacc111122000511005accaa"),
        "Legacy alias: captured speed 1, clockwise, duration 5.",
    ),
    "stop-b": CapturedCommand(
        "stop-b",
        bytes.fromhex("aacc3311220000110077ccaa"),
        "Legacy alias: captured stop while speed was 1.",
    ),
    "start-dir11-5s": CapturedCommand(
        "start-dir11-5s",
        bytes.fromhex("aacc111122000511005accaa"),
        "Legacy name: direction/start byte 0x11, speed byte 0x11, duration 5.",
    ),
    "stop-dir11": CapturedCommand(
        "stop-dir11",
        bytes.fromhex("aacc3311220000110077ccaa"),
        "Observed after start-dir11-5s; likely stop for direction byte 0x11.",
    ),
    "start-dir22-5s": CapturedCommand(
        "start-dir22-5s",
        bytes.fromhex("aacc221122000511006bccaa"),
        "Legacy name: direction/start byte 0x22, speed byte 0x11, duration 5.",
    ),
    "stop-dir22": CapturedCommand(
        "stop-dir22",
        bytes.fromhex("aacc3322220000110088ccaa"),
        "Observed after direction 0x22 starts; likely stop for direction byte 0x22.",
    ),
    "start-dir22-10s": CapturedCommand(
        "start-dir22-10s",
        bytes.fromhex("aacc221122000a110070ccaa"),
        "Synthetic legacy name: direction/start byte 0x22, speed byte 0x11, duration 10.",
    ),
    "altstart-dir22-5s": CapturedCommand(
        "altstart-dir22-5s",
        bytes.fromhex("aacc112222000511006bccaa"),
        "Observed later in the app session; first byte differs, duration 5.",
    ),
    "altstart-dir22-3s": CapturedCommand(
        "altstart-dir22-3s",
        bytes.fromhex("aacc1122220003110069ccaa"),
        "Observed later in the app session; first byte differs, duration 3.",
    ),
}


DIRECTION_ALIASES = {
    "cw": 0x11,
    "clock": 0x11,
    "clockwise": 0x11,
    "dir11": 0x11,
    "b": 0x11,
    "ccw": 0x22,
    "cclock": 0x22,
    "counterclockwise": 0x22,
    "dir22": 0x22,
    "a": 0x22,
}


def build_frame(direction: int, speed: int, duration: int, byte6: int = 0x11) -> bytes:
    if not 0 <= speed <= 9:
        raise ValueError("speed must be 0..9")
    if direction not in (0x11, 0x22):
        raise ValueError("direction must be 0x11/cw or 0x22/ccw based on the capture")
    if not 0 <= duration <= 0xFF:
        raise ValueError("duration must be 0..255")
    speed_byte = speed * 0x11
    payload = bytes([direction, speed_byte, 0x22, 0x00, duration, byte6, 0x00])
    checksum = sum(payload) & 0xFF
    return bytes.fromhex("aacc") + payload + bytes([checksum]) + bytes.fromhex("ccaa")


def build_stop_frame(speed: int, byte6: int = 0x11) -> bytes:
    if not 0 <= speed <= 9:
        raise ValueError("speed must be 0..9")
    speed_byte = speed * 0x11
    payload = bytes([0x33, speed_byte, 0x22, 0x00, 0x00, byte6, 0x00])
    checksum = sum(payload) & 0xFF
    return bytes.fromhex("aacc") + payload + bytes([checksum]) + bytes.fromhex("ccaa")


def direction_value(value: str) -> int:
    normalized = value.lower()
    if normalized in DIRECTION_ALIASES:
        return DIRECTION_ALIASES[normalized]
    return int(value, 0)


async def scan() -> None:
    devices = await BleakScanner.discover(timeout=10, return_adv=True)
    for device, adv in devices.values():
        uuids = ", ".join(adv.service_uuids or [])
        print(f"{device.address:>20}  rssi={adv.rssi:>4}  name={device.name!r}  uuids={uuids}")


async def find_target() -> str:
    devices = await BleakScanner.discover(timeout=10, return_adv=True)
    for device, adv in devices.values():
        names = {device.name, adv.local_name}
        if DEVICE_NAME in names or device.address.upper() == DEVICE_ADDRESS:
            print(f"Using {device.address} ({device.name or adv.local_name})")
            return device.address
    raise RuntimeError(f"Could not find {DEVICE_NAME}; make sure the phone app is disconnected.")


async def send_frame(frame: bytes, address: str | None = None) -> None:
    target = address or await find_target()
    print(f"Connecting to {target}")
    async with BleakClient(target) as client:
        print(f"Writing {frame.hex()} to {WRITE_CHAR_UUID}")
        await client.write_gatt_char(WRITE_CHAR_UUID, frame, response=False)
    print("Done")


async def main() -> None:
    parser = argparse.ArgumentParser(description="Experimental ChackTok BLE controller.")
    parser.add_argument("--scan", action="store_true", help="Scan for nearby BLE devices and exit.")
    parser.add_argument("--address", help="Override BLE address.")
    parser.add_argument("--command", choices=sorted(CAPTURED_COMMANDS), help="Send one captured command.")
    parser.add_argument("--raw", help="Send a raw hex frame.")
    parser.add_argument("--build", action="store_true", help="Build and send a start frame from fields.")
    parser.add_argument("--stop", action="store_true", help="Build and send a stop frame for the given speed.")
    parser.add_argument(
        "--direction",
        type=direction_value,
        default=0x11,
        help="Direction byte: cw/clock/dir11/0x11 or ccw/cclock/dir22/0x22.",
    )
    parser.add_argument("--speed", type=int, default=1, help="App speed value, 0..9. Captured: 1 => 0x11, 5 => 0x55.")
    parser.add_argument("--duration", type=lambda s: int(s, 0), default=5)
    args = parser.parse_args()

    if args.scan:
        await scan()
        return

    selected = [args.command is not None, args.raw is not None, args.build, args.stop]
    if sum(selected) != 1:
        parser.error("Choose exactly one of --command, --raw, --build, or --stop.")

    if args.command:
        command = CAPTURED_COMMANDS[args.command]
        print(command.note)
        frame = command.frame
    elif args.raw:
        frame = bytes.fromhex(args.raw.replace(" ", ""))
    elif args.stop:
        frame = build_stop_frame(args.speed)
    else:
        frame = build_frame(args.direction, args.speed, args.duration)

    await send_frame(frame, args.address)


if __name__ == "__main__":
    asyncio.run(main())
