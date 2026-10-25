---
name: add-chip
description: >-
  Add a custom chip to the IMSProg chip database. Use when the user asks to add
  support for a chip, port a flashrom chip definition into IMSProg, update
  IMSProg_programmer/database/IMSProg.Dat, or fix a chip's JEDEC ID, size,
  block size, voltage, 4-byte addressing or security-register algorithm. Covers
  researching the part, choosing the record fields, inserting the 68-byte
  record, updating the documented chip lists and validating the database.
---

# Add a custom chip to IMSProg.Dat

Announce at start: "I'm using the add-chip skill to add the chip to the
IMSProg database."

## 1. Gather the chip data

Prefer authoritative sources:

- **flashrom**: `flashchips/<vendor>.c` for the chip entry and
  `include/flashchips.h` for the JEDEC/model ID. This is the quickest way to
  get size, page size, voltage and 4-byte/OTP features.
- **Vendor datasheet**: confirm the JEDEC ID, voltage range, page size and
  supported erase commands.
- **Existing IMSProg records**: use the closest chip from the same vendor as
  the template for algorithm and 4-byte conventions.

Record these values before touching the database:

| Value | Example (XM25RU256C) |
|---|---|
| Type | `SPI_FLASH` |
| Manufacturer | `XMC` |
| Name | `XM25RU256C(1.8V)` |
| JEDEC ID | `20 44 19` → display `204419` |
| Size | `32 MiB` (33554432 bytes) |
| Page/sector size | `256` |
| Erase block | `64 KiB` |
| VCC | `1.8 V` |
| 4-byte addressing | `0x11` (Winbond) |
| Security/OTP algorithm | `0x03` |
| Delay | `1000` (default) |

### Choosing the optional fields

- **VCC**: `0x00` = 3.3 V, `0x01` = 1.8 V, `0x02` = 5.0 V,
  `0x03` = 2.5 V. Add a suffix to the name for non-3.3 V parts:
  `(1.8V)`, `(2.5V)`, `(5.0V)`.
- **4-byte addressing** (`0x3E`): `0x00` = unused, `0x01` = generic
  EN4B/EX4B (`0xB7`/`0xE9`), `0x11` = Winbond-style EN4B/EX4B plus EAR
  `0xC5`/`0xC8`, `0x21` = Spansion BRWR/BRRD. For a chip whose flashrom entry
  has `FEATURE_4BA_ENTER_WREN` **and** `FEATURE_4BA_EAR_C5C8`, use `0x11`.
  Use `0x21` for `FEATURE_4BA_ENTER_EAR7`/Spansion-style parts.
- **Security/OTP algorithm** (`0x3B`): match the vendor and command set in
  `IMSProg_programmer/dialogsecurity.cpp`. XMC generally uses `0x03`
  (Winbond/Boya/XMC/Spansion table). Use `0x00` when the chip has no
  security registers.
- **Block size** (`0x40`): IMSProg normally uses the largest common erase
  block, usually `64K`. The field is `0x3F * 256 KiB + 0x40 * 1 KiB`, so
  `64K` is stored as `0x3F=0`, `0x40=0x40`.
- **Type** (`0x3A`): `0x00` SPI NOR, `0x01` 24xxx I2C, `0x02` 93xxx
  MicroWire, `0x03` 25xxx SPI EEPROM, `0x04` 95xxx ST SPI EEPROM,
  `0x05` AT45DB DataFlash, `0x06` SPI NAND.

## 2. Inspect the current database

```sh
python3 .agents/skills/add-chip/scripts/chipdb.py check
python3 .agents/skills/add-chip/scripts/chipdb.py find 204419
python3 .agents/skills/add-chip/scripts/chipdb.py list --filter XMC
```

`check` must print `OK` before and after the change. It also reports records
whose type group is not JEDEC-sorted; that is a warning, not a failure.

## 3. Add the record

Always preview first:

```sh
python3 .agents/skills/add-chip/scripts/chipdb.py add \
  --type SPI_FLASH \
  --manufacturer XMC \
  --name "XM25RU256C(1.8V)" \
  --jedec 204419 \
  --size 32M \
  --page-size 256 \
  --block-size 64K \
  --algorithm 0x03 \
  --addr4 winbond \
  --vcc 1.8 \
  --dry-run
```

If the preview is correct, run the same command without `--dry-run`.

The script:

- derives `manuf`, `device` and `capacity` from the six-digit `--jedec`
  (display order, e.g. `20 44 19` → `204419`),
- writes the 68-byte record in the correct little-endian layout,
- inserts it in JEDEC order inside the existing type group,
- refuses an existing JEDEC ID unless `--allow-duplicate` is given,
- preserves exactly one all-zero terminator record.

Use `--man/--dev/--cap` instead of `--jedec` if the ID is not known as a
single six-digit value.

### Manual fallback

If a script cannot be used, the record layout is documented in the README
section "Chip database format". Keep these invariants:

- each record is exactly `0x44` bytes,
- the head at `0x00..0x2F` is `TYPE,MANUFACTURER,NAME` with NUL padding and
  must leave a NUL terminator,
- the file ends with one all-zero 68-byte record,
- file length is a multiple of 68,
- records stay sorted by JEDEC ID within their type group.

Never hand-merge this binary file during a git conflict; use the
`sync-upstream` skill's database procedure instead.

## 4. Update the documented chip lists

Add the chip name to both places, in the same order it appears in the
database:

- `README.md` → the vendor section under "List of supported chips".
- `IMSProg_programmer/other/index.html` → the matching vendor paragraph.

For XMC, `README.md` currently has a block like:

```text
XM25QH10B, XM25QH20B, ... XM25QH128C, XM25QH256C, ... XM25RU256C(1.8V), ...
```

Keep the lines readable and reflow only the affected paragraph.

## 5. Validate

```sh
python3 .agents/skills/add-chip/scripts/chipdb.py check
python3 .agents/skills/add-chip/scripts/chipdb.py find 204419
```

Confirm the expected values in the `find` output: type, size, page size, block
size, algorithm, 4-byte mode and VCC. If an AppImage was built, extract it and
confirm the packaged database contains the chip:

```sh
CHECK_DIR=$(mktemp -d -p /tmp/opencode)
cd "$CHECK_DIR"
"/path/to/IMSProg-*.AppImage" --appimage-extract >/dev/null
grep -a XM25RU256C squashfs-root/usr/share/imsprog/IMSProg.Dat
cd /
rm -rf "$CHECK_DIR"
```

For a source-tree build, grep the installed `IMSProg.Dat` directly.

Optionally build to make sure the database is packaged:

```sh
CONTAINER_ENGINE=podman ./build_appimage.sh --no-build \
  "$(awk '/^Version:/ {print $2; exit}' rpm/imsprog.spec)-chip-check"
```

## 6. Finish

- Keep the change focused on the database entry and the two documentation
  lists.
- Do not commit or push unless the user asked for it.
- When finishing, report the chip's JEDEC ID, the fields chosen (especially
  voltage and 4-byte mode), the validation result, and whether a build was
  performed.
