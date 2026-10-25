#!/usr/bin/env python3
"""Inspect, validate and edit the IMSProg chip database.

The database is a sequence of fixed 0x44-byte records followed by one all-zero
terminator record. See the README "Chip database format" section and the
add-chip skill for field semantics.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

RECORD_SIZE = 0x44
HEAD_SIZE = 0x30

TYPE_BY_NAME = {
    "SPI_FLASH": 0x00,
    "24_EEPROM": 0x01,
    "93_EEPROM": 0x02,
    "25_EEPROM": 0x03,
    "95_EEPROM": 0x04,
    "45_EEPROM": 0x05,
    "SPI_NAND": 0x06,
}
NAME_BY_TYPE = {value: key for key, value in TYPE_BY_NAME.items()}

VCC_BY_NAME = {"3.3": 0x00, "1.8": 0x01, "5.0": 0x02, "2.5": 0x03}
VCC_LABEL = {0x00: "3.3V", 0x01: "1.8V", 0x02: "5.0V", 0x03: "2.5V"}

ADDR4_BY_NAME = {
    "none": 0x00,
    "no": 0x00,
    "generic": 0x01,
    "yes": 0x01,
    "winbond": 0x11,
    "spansion": 0x21,
}


@dataclass
class ParsedRecord:
    index: int
    raw: bytes

    @property
    def head(self) -> str:
        return self.raw[:HEAD_SIZE].split(b"\0", 1)[0].decode("latin1")

    @property
    def head_parts(self) -> tuple[str, str, str]:
        parts = self.head.split(",", 2)
        if len(parts) != 3:
            return (self.head, "", "")
        return (parts[0], parts[1], parts[2])

    @property
    def type_code(self) -> int:
        return self.raw[0x3A]

    @property
    def type_name(self) -> str:
        return NAME_BY_TYPE.get(self.type_code, f"0x{self.type_code:02X}")

    @property
    def capacity_code(self) -> int:
        return self.raw[0x30]

    @property
    def device_id(self) -> int:
        return self.raw[0x31]

    @property
    def manufacturer_id(self) -> int:
        return self.raw[0x32]

    @property
    def jedec(self) -> str:
        return f"{self.manufacturer_id:02X}{self.device_id:02X}{self.capacity_code:02X}"

    @property
    def jedec_key(self) -> tuple[int, int, int]:
        return (self.manufacturer_id, self.device_id, self.capacity_code)

    @property
    def size(self) -> int:
        return int.from_bytes(self.raw[0x34:0x38], "little")

    @property
    def page_size(self) -> int:
        return int.from_bytes(self.raw[0x38:0x3A], "little")

    @property
    def algorithm(self) -> int:
        return self.raw[0x3B]

    @property
    def delay(self) -> int:
        return int.from_bytes(self.raw[0x3C:0x3E], "little")

    @property
    def addr4(self) -> int:
        return self.raw[0x3E]

    @property
    def block_size(self) -> int:
        return self.raw[0x3F] * 256 * 1024 + self.raw[0x40] * 1024

    @property
    def eeprom_pages(self) -> int:
        return self.raw[0x42]

    @property
    def vcc(self) -> int:
        return self.raw[0x43]


def human_size(value: int) -> str:
    for unit, divisor in (("MiB", 1 << 20), ("KiB", 1 << 10)):
        if value >= divisor and value % divisor == 0:
            return f"{value // divisor} {unit}"
    return f"{value} B"


def parse_number(text: str, what: str = "number") -> int:
    cleaned = text.strip().replace("_", "")
    match = re.fullmatch(r"(0[xX][0-9a-fA-F]+|[0-9]+)([kKmMgG](?:i?[bB])?)?", cleaned)
    if not match:
        raise argparse.ArgumentTypeError(f"invalid {what}: {text!r}")
    number = int(match.group(1), 0)
    suffix = (match.group(2) or "").lower()
    multiplier = 1
    if suffix:
        multiplier = {"k": 1 << 10, "m": 1 << 20, "g": 1 << 30}[suffix[0]]
    value = number * multiplier
    if value < 0:
        raise argparse.ArgumentTypeError(f"invalid {what}: {text!r}")
    return value


def parse_jedec(text: str) -> tuple[int, int, int]:
    cleaned = re.sub(r"[\s:_-]", "", text.strip())
    if cleaned.lower().startswith("0x"):
        cleaned = cleaned[2:]
    if not re.fullmatch(r"[0-9a-fA-F]{6}", cleaned):
        raise argparse.ArgumentTypeError(
            "JEDEC ID must be six hex digits in display order: "
            "manufacturer, device, capacity (for example 204419)"
        )
    manufacturer = int(cleaned[0:2], 16)
    device = int(cleaned[2:4], 16)
    capacity = int(cleaned[4:6], 16)
    return manufacturer, device, capacity


def parse_vcc(text: str) -> int:
    cleaned = text.strip().lower().replace("v", "")
    if cleaned in VCC_BY_NAME:
        return VCC_BY_NAME[cleaned]
    try:
        code = int(cleaned, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid VCC: {text!r}") from exc
    if code not in VCC_LABEL:
        raise argparse.ArgumentTypeError("VCC code must be 0..3")
    return code


def parse_addr4(text: str) -> int:
    cleaned = text.strip().lower().replace("_", "-")
    if cleaned in ADDR4_BY_NAME:
        return ADDR4_BY_NAME[cleaned]
    try:
        value = int(cleaned, 0)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid 4-byte address mode: {text!r}") from exc
    if value not in (0x00, 0x01, 0x11, 0x21):
        raise argparse.ArgumentTypeError(
            "4-byte address mode must be 0x00, 0x01, 0x11 or 0x21"
        )
    return value


def load_database(path: Path) -> tuple[list[ParsedRecord], bytes]:
    data = path.read_bytes()
    if not data:
        raise SystemExit(f"error: {path} is empty")
    if len(data) % RECORD_SIZE:
        raise SystemExit(
            f"error: {path} length {len(data)} is not a multiple of {RECORD_SIZE}"
        )
    records: list[ParsedRecord] = []
    terminator_seen = False
    for index in range(len(data) // RECORD_SIZE):
        raw = data[index * RECORD_SIZE : (index + 1) * RECORD_SIZE]
        if raw[0] == 0:
            if any(raw):
                raise SystemExit(
                    f"error: record {index} starts with 0x00 but is not all zero"
                )
            terminator_seen = True
            terminator = raw
            continue
        if terminator_seen:
            raise SystemExit(f"error: data record {index} appears after terminator")
        records.append(ParsedRecord(index, raw))
    if not terminator_seen:
        raise SystemExit(f"error: {path} has no all-zero terminator record")
    return records, terminator


def save_database(path: Path, records: list[ParsedRecord], terminator: bytes) -> None:
    payload = b"".join(record.raw for record in records) + terminator
    # Write atomically so an interrupted run cannot truncate the database.
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(payload)
    temporary.replace(path)


def cmd_check(args: argparse.Namespace) -> int:
    path = Path(args.db)
    records, _ = load_database(path)
    errors: list[str] = []
    warnings: list[str] = []
    group_counts: dict[str, int] = {}

    for record in records:
        prefix = f"record {record.index} ({record.head or '<empty>'})"
        kind, manufacturer, name = record.head_parts
        if not kind or not manufacturer or not name:
            errors.append(f"{prefix}: head must be TYPE,MANUFACTURER,NAME")
        if record.type_code not in NAME_BY_TYPE:
            errors.append(f"{prefix}: unknown type code 0x{record.type_code:02X}")
        elif kind in TYPE_BY_NAME and TYPE_BY_NAME[kind] != record.type_code:
            errors.append(
                f"{prefix}: head type {kind!r} does not match binary type "
                f"0x{record.type_code:02X} ({record.type_name})"
            )
        if record.size <= 0:
            errors.append(f"{prefix}: size is zero")
        if record.page_size <= 0:
            errors.append(f"{prefix}: page/sector size is zero")
        # Block size is meaningful for SPI NOR/NAND. I2C/MicroWire/DataFlash
        # EEPROM records legitimately leave it at zero.
        if record.block_size <= 0 and record.type_code in (0x00, 0x06):
            errors.append(f"{prefix}: block size is zero")
        if record.vcc not in VCC_LABEL:
            errors.append(f"{prefix}: invalid VCC code 0x{record.vcc:02X}")
        group_counts[record.type_name] = group_counts.get(record.type_name, 0) + 1

    # Records are sorted by (manufacturer, device, capacity) within each type.
    by_type: dict[int, list[ParsedRecord]] = {}
    for record in records:
        by_type.setdefault(record.type_code, []).append(record)
    for type_code, group in by_type.items():
        keys = [record.jedec_key for record in group]
        if keys != sorted(keys):
            warnings.append(
                f"type {NAME_BY_TYPE.get(type_code, hex(type_code))} is not sorted "
                "by JEDEC ID"
            )

    print(f"database: {path}")
    print(f"records:  {len(records)} (+1 terminator), {RECORD_SIZE} bytes each")
    for type_name in sorted(group_counts):
        print(f"  {type_name:11s} {group_counts[type_name]:4d}")
    if warnings:
        print("\nwarnings:")
        for warning in warnings:
            print(f"  - {warning}")
    if errors:
        print("\nerrors:")
        for error in errors:
            print(f"  - {error}")
        return 1
    print("\nOK")
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    records, _ = load_database(Path(args.db))
    selected = records
    if args.type:
        type_code = TYPE_BY_NAME.get(args.type.upper())
        if type_code is None:
            raise SystemExit(f"error: unknown type {args.type!r}")
        selected = [record for record in selected if record.type_code == type_code]
    if args.filter:
        needle = args.filter.lower()
        selected = [record for record in selected if needle in record.head.lower()]
    for record in selected:
        print(
            f"{record.index:4d}  {record.jedec}  {human_size(record.size):>9s}  "
            f"page={record.page_size:<5d} block={human_size(record.block_size):>8s}  "
            f"algo=0x{record.algorithm:02X} a4=0x{record.addr4:02X} "
            f"vcc={VCC_LABEL.get(record.vcc, hex(record.vcc)):4s}  {record.head}"
        )
    print(f"\n{len(selected)} record(s)")
    return 0


def cmd_find(args: argparse.Namespace) -> int:
    records, _ = load_database(Path(args.db))
    target = parse_jedec(args.jedec)
    matches = [
        record
        for record in records
        if (record.manufacturer_id, record.device_id, record.capacity_code) == target
    ]
    if not matches:
        print(f"no record found for JEDEC {args.jedec}")
        return 1
    for record in matches:
        print(f"record {record.index}: {record.head}")
        print(f"  JEDEC:         {record.jedec}")
        print(f"  type:          {record.type_name} (0x{record.type_code:02X})")
        print(f"  size:          {human_size(record.size)} ({record.size} bytes)")
        print(f"  page/sector:   {record.page_size}")
        print(f"  block:         {human_size(record.block_size)} ({record.block_size} bytes)")
        print(f"  algorithm:     0x{record.algorithm:02X}")
        print(f"  delay:         {record.delay}")
        print(f"  4-byte addr:   0x{record.addr4:02X}")
        print(f"  EEPROM pages:  {record.eeprom_pages}")
        print(f"  VCC:           {VCC_LABEL.get(record.vcc, hex(record.vcc))}")
        print(f"  raw:           {record.raw.hex(' ')}")
    return 0


def cmd_add(args: argparse.Namespace) -> int:
    path = Path(args.db)
    records, terminator = load_database(path)

    if args.jedec:
        manufacturer, device, capacity = parse_jedec(args.jedec)
    else:
        if None in (args.man, args.dev, args.cap):
            raise SystemExit("error: provide --jedec or all of --man/--dev/--cap")
        manufacturer, device, capacity = args.man, args.dev, args.cap
        for label, value in (
            ("--man", manufacturer),
            ("--dev", device),
            ("--cap", capacity),
        ):
            if not 0 <= value <= 0xFF:
                raise SystemExit(f"error: {label} must be 0..255")

    type_name = args.type.upper()
    if type_name not in TYPE_BY_NAME:
        raise SystemExit(
            f"error: unknown type {args.type!r}; choose from {', '.join(TYPE_BY_NAME)}"
        )
    type_code = TYPE_BY_NAME[type_name]

    head = f"{type_name},{args.manufacturer},{args.name}"
    if len(head.encode("latin1")) > HEAD_SIZE - 1:
        raise SystemExit(
            f"error: head is {len(head)} bytes; maximum is {HEAD_SIZE - 1} "
            "(must keep a NUL terminator before offset 0x30)"
        )

    if args.size <= 0 or args.size > 0xFFFFFFFF:
        raise SystemExit("error: size must be 1..0xFFFFFFFF bytes")
    if not 0 < args.page_size <= 0xFFFF:
        raise SystemExit("error: page/sector size must be 1..65535")
    if args.block_size % 1024:
        raise SystemExit("error: block size must be a multiple of 1024 bytes")
    block_high, block_low = divmod(args.block_size, 256 * 1024)
    block_low //= 1024
    if block_high > 0xFF or block_low > 0xFF:
        raise SystemExit("error: block size does not fit the database field")
    if not 0 <= args.algorithm <= 0xFF:
        raise SystemExit("error: algorithm must be 0..255")
    if not 0 <= args.delay <= 0xFFFF:
        raise SystemExit("error: delay must be 0..65535")
    if not 0 <= args.eeprom_pages <= 0xFF:
        raise SystemExit("error: EEPROM pages must be 0..255")

    raw = bytearray(RECORD_SIZE)
    encoded_head = head.encode("latin1")
    raw[: len(encoded_head)] = encoded_head
    raw[0x30] = capacity
    raw[0x31] = device
    raw[0x32] = manufacturer
    raw[0x33] = 0x00
    raw[0x34:0x38] = args.size.to_bytes(4, "little")
    raw[0x38:0x3A] = args.page_size.to_bytes(2, "little")
    raw[0x3A] = type_code
    raw[0x3B] = args.algorithm
    raw[0x3C:0x3E] = args.delay.to_bytes(2, "little")
    raw[0x3E] = args.addr4
    raw[0x3F] = block_high
    raw[0x40] = block_low
    raw[0x41] = 0x00
    raw[0x42] = args.eeprom_pages
    raw[0x43] = args.vcc

    new_key = (manufacturer, device, capacity)
    for record in records:
        if record.type_code == type_code and record.jedec_key == new_key:
            if not args.allow_duplicate:
                raise SystemExit(
                    f"error: {record.head} already uses JEDEC {record.jedec} "
                    f"(record {record.index}); use --allow-duplicate to add anyway"
                )

    same_type = [record for record in records if record.type_code == type_code]
    if same_type:
        position = None
        for record in same_type:
            if record.jedec_key > new_key:
                position = record.index
                break
        if position is None:
            position = same_type[-1].index + 1
    else:
        position = len(records)

    print(f"insert at record {position} (before record {position} in the old file)")
    print(f"  head:  {head}")
    print(f"  JEDEC: {manufacturer:02X}{device:02X}{capacity:02X}")
    print(f"  raw:   {raw.hex(' ')}")

    if args.dry_run:
        print("\ndry run: database not modified")
        return 0

    records.insert(position, ParsedRecord(position, bytes(raw)))
    # Re-number for a clean report; indices are derived positions only.
    records = [
        ParsedRecord(index, record.raw) for index, record in enumerate(records)
    ]
    save_database(path, records, terminator)
    print(f"\nwrote {path}: {len(records)} records + terminator")
    return 0


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        "--db",
        default="IMSProg_programmer/database/IMSProg.Dat",
        help="database path (default: %(default)s)",
    )

    parser = argparse.ArgumentParser(
        description="Inspect, validate and edit the IMSProg chip database."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    check = subparsers.add_parser("check", parents=[common], help="validate the database")
    check.set_defaults(func=cmd_check)

    listing = subparsers.add_parser("list", parents=[common], help="list records")
    listing.add_argument("--type", help="filter by type, e.g. SPI_FLASH")
    listing.add_argument("--filter", help="case-insensitive substring of the head")
    listing.set_defaults(func=cmd_list)

    find = subparsers.add_parser("find", parents=[common], help="find a JEDEC ID")
    find.add_argument("jedec", help="six hex digits: manufacturer device capacity")
    find.set_defaults(func=cmd_find)

    add = subparsers.add_parser("add", parents=[common], help="add a record")
    add.add_argument("--type", required=True, help="record type, e.g. SPI_FLASH")
    add.add_argument("--manufacturer", required=True, help="manufacturer name")
    add.add_argument("--name", required=True, help="chip name, e.g. XM25RU256C(1.8V)")
    add.add_argument("--jedec", help="six hex digits in display order, e.g. 204419")
    add.add_argument("--man", type=lambda value: int(value, 0), help="manufacturer ID")
    add.add_argument("--dev", type=lambda value: int(value, 0), help="device ID")
    add.add_argument("--cap", type=lambda value: int(value, 0), help="capacity code")
    add.add_argument("--size", type=parse_number, required=True, help="size in bytes or 32M")
    add.add_argument(
        "--page-size", type=parse_number, default=256, help="page/sector size (default: 256)"
    )
    add.add_argument(
        "--block-size",
        type=parse_number,
        default=64 * 1024,
        help="erase block size (default: 64K)",
    )
    add.add_argument(
        "--algorithm", type=lambda value: int(value, 0), default=0, help="algorithm code"
    )
    add.add_argument("--delay", type=parse_number, default=1000, help="bus delay factor")
    add.add_argument(
        "--addr4",
        type=parse_addr4,
        default=0,
        help="0/none, 1/generic, 0x11/winbond, 0x21/spansion",
    )
    add.add_argument("--vcc", type=parse_vcc, default=0, help="1.8, 2.5, 3.3, 5.0 or 0..3")
    add.add_argument("--eeprom-pages", type=parse_number, default=0, help="EEPROM pages")
    add.add_argument("--dry-run", action="store_true", help="print the record only")
    add.add_argument(
        "--allow-duplicate", action="store_true", help="allow an existing JEDEC ID"
    )
    add.set_defaults(func=cmd_add)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
