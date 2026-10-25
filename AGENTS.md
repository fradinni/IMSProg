# AGENTS.md

IMSProg is a Qt5/Qt6 C/C++ suite for CH341A, CH347T and FT232H EEPROM/SPI
programmers. This is the **fradinni fork**: `origin` = `fradinni/IMSProg`,
`upstream` = `bigbigmdm/IMSProg` (read-only). Work on `custom`; `main` mirrors
`upstream/main`.

Fork-only additions to preserve: the Docker/Podman AppImage build
(`build_appimage.sh`, `appimage/`, `docker/`, `.dockerignore`), the
`XM25RU256C(1.8V)` chip record, the README fork header, and `.agents/skills/`.

## Build and verify

```sh
sudo ./build_all.sh                    # full build+install, needs root (Linux)
cmake -S . -B build && cmake --build build --parallel   # all 3 subprojects
cmake -S IMSProg_programmer -B IMSProg_programmer/build
cmake --build IMSProg_programmer/build --parallel
cmake -S IMSProg_programmer -B IMSProg_programmer/build -DFORCE_QT5=ON
./build_appimage.sh [X.Y.Z-custom.N]   # AppImage -> dist/ (Docker/Podman)
CONTAINER_ENGINE=podman ./build_appimage.sh --no-build
clang-format -i path/to/file.cpp       # formatting only
```

There is **no unit-test suite**; validate with a build plus the chip database
checker (the closest thing to a single test):

```sh
python3 .agents/skills/add-chip/scripts/chipdb.py check
python3 .agents/skills/add-chip/scripts/chipdb.py find 204419   # one chip
python3 .agents/skills/add-chip/scripts/chipdb.py list --filter XMC
```

CI (`.github/workflows/`): build on Ubuntu 22/24/26, Fedora, macOS; codespell
warns only and skips `*.ts`. CircleCI and `deployment/macports` are upstream.

## Code style

- C++17; **both Qt5 and Qt6 must compile**. Prefer APIs common to both or guard
  version differences. CMake uses AUTOMOC/AUTOUIC/AUTORCC; UI lives in `.ui`
  files. New dialog = `.h` + `.cpp` + `.ui`, added to the component
  `CMakeLists.txt` (and `${QM_FILES}` when translated).
- `.clang-format`: Allman braces, 4 spaces, 120 columns, pointer right, sorted
  includes with `<Q...>` last. Do not mass-reformat; keep diffs focused and
  match the file you edit (upstream code is inconsistent).
- C++ naming: classes `PascalCase`, members/locals `camelCase`
  (`currentChipSize`), Qt auto-slots `on_<widget>_<signal>`. Keep the GPL
  header and include guards in new files.
- C driver code (`*.c`, `ch34x`, `spi_*`, SNANDer-derived): tabs, K&R braces,
  lowercase `snake_case` functions, `u8/u16/u32` from `types.h`. Leave existing
  formatting untouched.
- Include order used across the project: own header first, then Qt/system
  headers, then project headers. Drivers are pulled in via `extern "C" { ... }`.
- Prefer Qt types (`QString`, `QByteArray`, `QVector`), `qDebug`/`qWarning` for
  diagnostics, `QMessageBox` for user-facing errors. Hardware routines return
  `int`/status enums: check, propagate and report; never silently ignore.
- User-visible strings use `tr()`; add new UI text to `language/*.ts`.

## Chip database

`IMSProg_programmer/database/IMSProg.Dat` is binary: 68-byte records, JEDEC
sorted within each type group, one all-zero terminator. Never hand-edit or
hand-merge it — use the `add-chip` skill/`chipdb.py`, and update `README.md`
plus `IMSProg_programmer/other/index.html` chip lists. After upstream syncs,
confirm the fork entry survives: `chipdb.py find 204419`.

## Structure

- `IMSProg_programmer/` — main app, dialogs, `qhexedit2/`, USB drivers, database
- `IMSProg_editor/` — chip database editor
- `IMSProg_database_update/` — HTTP database updater
- `appimage/`, `docker/`, `build_appimage.sh` — fork AppImage tooling
- `.agents/skills/` — `sync-upstream`, `add-chip`, `release-custom`
- `rpm/imsprog.spec` — official version source; releases `<version>-custom.N`
- `dist/`, `build/` — ignored build output; never commit
