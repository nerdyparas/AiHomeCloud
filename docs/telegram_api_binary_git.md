# telegram-bot-api Binary CI Build — Problem History & Current State

> **Purpose:** Full depth summary for Opus to diagnose and advise.
> **Repo:** `nerdyparas/AiHomeCloud`
> **Workflow file:** `.github/workflows/build.yml`
> **Active tag:** `tgapi-v1.0.0` (currently pointing at commit `96036e6`)
> **Current CI run:** `23219223978` — `in_progress` as of 2026-03-17 22:24 UTC

---

## Goal

Build `telegram-bot-api` (TDLib's local Telegram Bot API server) for three
architectures and publish them as a GitHub Release so that the AiHomeCloud
backend can download the correct pre-built binary for a user's SBC device
instead of recompiling from source on the device.

Target architectures:
- `linux-amd64` — x86_64 servers/PCs
- `linux-arm64` — aarch64 SBCs (Radxa Cubie A7Z, Raspberry Pi 4+, Orange Pi 5)
- `linux-armv7` — armv7l SBCs (Raspberry Pi 2/3 with 32-bit OS)

glibc compat requirement: **2.31 or earlier** (ubuntu 20.04 baseline) so
binaries run on Armbian Focal, Raspberry Pi OS Buster, and Ubuntu 20.04
SBC installations.

The binary is fetched at runtime by
`backend/app/routes/telegram_routes.py:_try_download_prebuilt()`.

---

## Infrastructure Constraint

All builds must run on **free GitHub-hosted x86\_64 runners** (ubuntu-22.04).
No ARM GitHub runners (requires paid Team plan ~$48/yr + ~$0.50/build).

---

## Commit History

| Commit | What it tried |
|--------|--------------|
| `fe46ab5` | Initial cross-arch CI pipeline (ubuntu-20.04 runner) |
| `09ae24f` | glibc-compatible CI + arch-aware Flutter UI |
| `a64c34d` | Changed `runs-on: ubuntu-20.04` → `ubuntu-22.04` + `container: ubuntu:20.04` |
| `7da662c` | Fixed `${{ github.workspace }}` → `${GITHUB_WORKSPACE}` in cmake toolchain path; added `make` to deps |
| `d5ac8e1` | Added `prepare_cross_compiling` step + `TD_GENERATED_BINARIES_DIR=/tmp/td-native` |
| `e808c42` | Removed `TD_GENERATED_BINARIES_DIR` (caused different include-path bug) |
| `96036e6` | **Current:** Replaced cross-compilation entirely with QEMU `docker run --platform` approach |

---

## Failure History — Every CI Run

### Run `23218009428` — CANCELLED
**Approach:** `runs-on: ubuntu-20.04`, direct (no container)
**Stuck:** All 3 jobs queued indefinitely
**Root cause:** `ubuntu-20.04` GitHub-hosted runners were fully deprecated April 2025. Jobs with `labels=['ubuntu-20.04']` have no runner.
**Fix:** Changed to `runs-on: ubuntu-22.04` + `container: ubuntu:20.04`

---

### Run `23218200270` — FAILED
**Approach:** `runs-on: ubuntu-22.04` + `container: ubuntu:20.04` (Docker container job)
**arm64 and armv7:** Failed at **"Configure CMake (cross-compilation)"**

**Error 1:**
```
CMake Error: Could not find toolchain file:
  /home/runner/work/AiHomeCloud/AiHomeCloud/scripts/cmake/toolchain-linux-arm64.cmake
```
**Root cause:** `${{ github.workspace }}` is a template expression expanded by
the host runner BEFORE entering the container. The host path
`/home/runner/work/...` does not match the container mount point
`/__w/AiHomeCloud/AiHomeCloud/...`.
**Fix:** Changed to `${GITHUB_WORKSPACE}` shell env var (set correctly inside container).

**Error 2:**
```
CMAKE_MAKE_PROGRAM is not set
```
**Root cause:** `ubuntu:20.04` minimal image does not include `make`.
CMake defaults to Unix Makefiles generator but can't find the `make` binary.
**Fix:** Added `make` to the `apt-get install` list.

---

### Run `23218551257` — FAILED
**Approach:** `runs-on: ubuntu-22.04` + `container: ubuntu:20.04`, cross-compilation with toolchain files
**arm64 and armv7:** Failed at **"Build"** (Configure now passed ✓)

**Error:**
```
No rule to make target
  '/tmp/tg-src/td/tdutils/generate/auto/mime_type_to_extension.cpp',
  needed by 'td/tdutils/CMakeFiles/tdutils.dir/generate/auto/mime_type_to_extension.cpp.o'.  Stop.
```
**Root cause:** TDLib's CMake build contains C++ code generators (e.g. for
`mime_type_to_extension.cpp`). When `CMAKE_CROSSCOMPILING=TRUE` (set
automatically by CMake when `CMAKE_SYSTEM_PROCESSOR` ≠ host processor), TDLib
**skips adding build rules for these generators** because a cross-compiled
ARM binary can't run on the x86\_64 host. The auto-generated `.cpp` files
never get created.

TDLib documents this: you must run `prepare_cross_compiling` as a native
build target first, which generates the auto files into the source tree.

**Fix:** Added a new step before the cross cmake configure:
```yaml
- name: Prepare auto-generated files (native TDLib tools)
  if: ${{ matrix.cross }}
  run: |
    cmake -S /tmp/tg-src/td -B /tmp/td-native -DCMAKE_BUILD_TYPE=Release
    cmake --build /tmp/td-native --target prepare_cross_compiling
```
Also added `TD_GENERATED_BINARIES_DIR=/tmp/td-native` to the cross cmake
configure (later found to be wrong — see next run).

---

### Run `23218869404` — FAILED
**Approach:** Same container approach, cross-compilation, with `prepare_cross_compiling` step
**arm64 and armv7:** Failed at **"Build"** (prepare_cross_compiling step passed ✓)

**Error:**
```
/tmp/tg-src/telegram-bot-api/ClientParameters.h:9:10:
fatal error: td/db/KeyValueSyncInterface.h: No such file or directory
```
**Root cause:** `TD_GENERATED_BINARIES_DIR=/tmp/td-native` changes how TDLib
resolves include paths. It redirects include lookup to the `/tmp/td-native`
binary directory instead of the source tree, breaking non-generated headers
like `td/db/KeyValueSyncInterface.h` which live in the source tree.

**Observation from logs:** `prepare_cross_compiling` DID write the auto files
into the source tree (`/tmp/tg-src/td/tdutils/generate/auto/`).
`mime_type_to_extension.cpp` was generated. The `tdutils` library files
started compiling (progress up to ~35% of tdutils). The new error was
previously hidden by the first error.

**Fix:** Removed `TD_GENERATED_BINARIES_DIR` from cross cmake configure.
`prepare_cross_compiling` writes auto files directly into the source tree
so they're found via normal CMake source-tree paths.

---

### Run `23219223978` — IN PROGRESS (current)
**Approach:** Abandoned cross-compilation entirely. Switched to QEMU.

**Strategy:**
1. `docker/setup-qemu-action@v3` registers QEMU binfmt\_misc handlers on the ubuntu-22.04 runner
2. `docker run --rm --platform linux/arm64 ubuntu:20.04 bash -c "cmake ..."` runs the full build inside a native ARM64 container via QEMU user-mode emulation
3. The ARM64 OS inside the container sees a native `aarch64-linux-gnu` gcc — no cross-compilation, no toolchain file, no `CMAKE_CROSSCOMPILING` flag

**Step status (checked at 22:26 UTC):**
- linux-amd64: ✓ QEMU setup, ✓ clone, ▶ Build
- linux-arm64: ✓ QEMU setup, ✓ clone, ▶ Build
- linux-armv7: ✓ QEMU setup, ✓ clone, ▶ Build

All three are actively building. No failures so far.

**Trade-off:** arm64/armv7 will take ~45-60 min under QEMU emulation (vs
~15 min cross-compiled). Well within the 6h GitHub Actions job limit.

---

## Current `build.yml` — Full Structure

```yaml
jobs:
  build:
    runs-on: ubuntu-22.04          # Host: x86_64
    # NO container: directive       # QEMU handles arch via docker run
    strategy:
      matrix:
        include:
          - {target: linux-amd64, platform: linux/amd64}
          - {target: linux-arm64, platform: linux/arm64}
          - {target: linux-armv7, platform: linux/arm/v7}
    steps:
      - Checkout
      - Set up QEMU (docker/setup-qemu-action@v3, platforms: arm64,arm)
      - Clone telegram-bot-api source (into /tmp/tg-src on runner)
      - Build:
          docker run --rm
            --platform ${{ matrix.platform }}
            -v /tmp/tg-src:/src
            -v /tmp/tg-output:/out
            ubuntu:20.04
            bash -xc "
              apt-get install cmake g++ libssl-dev zlib1g-dev gperf make
              cmake -S /src -B /tmp/build -DCMAKE_BUILD_TYPE=Release
              cmake --build /tmp/build --target telegram-bot-api --parallel $(nproc)
              strip /tmp/build/telegram-bot-api -o /out/telegram-bot-api-ARCH
            "
      - Verify binary (file + ls -lh output)
      - Upload artifact (actions/upload-artifact@v4)

  release:
    needs: build
    runs-on: ubuntu-22.04
    steps:
      - Download all artifacts (actions/download-artifact@v4, merge-multiple: true)
      - Resolve release tag (from workflow_dispatch input or GITHUB_REF)
      - Write release notes (markdown with binary table)
      - Create GitHub Release (gh release create with all 3 binaries)
```

---

## What Opus Should Know

### TDLib cross-compilation specifics
TDLib (the library backing `telegram-bot-api`) has internal code generators:
- `td_generate_db_cpp` — generates database code
- `tdmime_auto` — generates `mime_type_to_extension.cpp` via a CMake `add_executable` → `add_custom_command` chain

When `CMAKE_CROSSCOMPILING=TRUE`:
- CMake detects the host ≠ target processor
- TDLib's `CMakeLists.txt` wraps generator compilation in `if(NOT CMAKE_CROSSCOMPILING)`
- The `prepare_cross_compiling` target EXISTS specifically for this: it runs a native cmake+build of just the td library subdirectory to produce auto files, writing them to the source tree
- HOWEVER: `TD_GENERATED_BINARIES_DIR` is a DIFFERENT variable — it tells TDLib to look for pre-built generator *executables* in a specific path, which then changes how generated file include paths are resolved — this broke non-generated headers

### Why `container: ubuntu:20.04` (Docker container job) was dropped
GitHub Actions "container jobs" (`container:` key in job definition) mount the
workspace at `/__w/...` instead of `/home/runner/work/...`, which means
template expressions like `${{ github.workspace }}` evaluate to the wrong path
inside the container. The `${GITHUB_WORKSPACE}` env var is set correctly, but
there are multiple other subtle differences between container jobs and plain
runner jobs with `docker run`. Switching to explicit `docker run` calls inside
a plain `ubuntu-22.04` runner is simpler and more transparent.

### Why QEMU is the right answer here
- Zero cross-compilation issues by definition (ARM OS, ARM compiler)
- Same cmake invocation for all 3 architectures
- glibc version guaranteed by container image (ubuntu:20.04 = glibc 2.31)
- `docker/setup-qemu-action` is a well-maintained GitHub Action maintained by Docker Inc
- Widely used pattern for multi-arch builds (e.g. building Docker images for ARM)

### Potential remaining issues to watch for
1. **QEMU emulation crashes** — very rare but possible for complex C++ builds; would manifest as signal 11 or exec format error in cmake output
2. **nproc under QEMU** — `$(nproc)` inside QEMU container reports host nproc (good — uses all cores)
3. **cmake version** — ubuntu:20.04 ships cmake 3.16. `telegram-bot-api`'s `CMakeLists.txt` requires `cmake_minimum_required(VERSION 3.0.2)` — well satisfied
4. **apt mirror flakiness** — QEMU containers pull from `archive.ubuntu.com`; transient 503s could fail the apt-get step; not seen in practice
5. **disk space** — `telegram-bot-api` full build tree ~4-6 GB in `/tmp/build` inside container. GitHub Actions runners have ~14 GB free disk.
6. **timeout** — `github.timeout-minutes` default is 360 (6h). QEMU arm64 build expected ~45-60 min. Should be fine.

---

## Downstream: How the Binary Gets Used

### Backend route: `backend/app/routes/telegram_routes.py`

```python
async def _try_download_prebuilt() -> tuple[bool, str]:
    """Returns (success, reason_for_failure_or_empty)."""
    machine = platform.machine().lower()
    target_map = {"x86_64": "linux-amd64", "aarch64": "linux-arm64", ...}
    target = target_map.get(machine)
    if not target:
        return False, f"No pre-built binary for architecture {machine} — compiling from source..."

    url = f"https://github.com/nerdyparas/AiHomeCloud/releases/latest/download/telegram-bot-api-{target}"
    # Downloads with curl --retry 1 (fail fast on 404)
    # Verifies ELF header
    # Installs to /usr/local/bin/telegram-bot-api
    # Returns (True, "") on success
    # Returns (False, human-readable-reason) on any failure
```

The download URL pattern is:
```
https://github.com/nerdyparas/AiHomeCloud/releases/latest/download/telegram-bot-api-linux-arm64
```

The GitHub Release `latest` redirect is used — no hardcoded version tag.

If download fails (404 = no release yet), the code falls back to compiling
from source on the SBC directly, which takes 20-40 minutes.

### Flutter UI: `lib/screens/main/telegram_setup_screen.dart`

- Calls `GET /api/v1/system/arch` to detect device arch
- Shows a chip: green (prebuilt available) or amber (will compile)
- Confirmation dialog text adapts based on arch availability
- Job progress messages include the fallback reason if download fails

---

## Files Modified This Session

| File | Change |
|------|--------|
| `.github/workflows/build.yml` | Entire build job rewritten 6 times (see commit history) |
| `backend/app/routes/telegram_routes.py` | `_try_download_prebuilt()` returns `(bool, str)`, curl retry 3→1 |
| `backend/app/routes/system_routes.py` | Added `GET /api/v1/system/arch` endpoint |
| `lib/services/api/system_api.dart` | Added `getDeviceArch()` method |
| `lib/screens/main/telegram_setup_screen.dart` | Arch detection chip + adapted dialog |
| `lib/l10n/app_en.arb` | 5 new l10n strings for arch UI |

---

## What Opus Can Help With

If run `23219223978` fails, Opus should:

1. Check failure step and error message from:
   ```bash
   gh api repos/nerdyparas/AiHomeCloud/actions/runs/23219223978/jobs | \
     python3 -c "import json,sys; data=json.load(sys.stdin); [print(j['id'], j['name'], j.get('conclusion')) for j in data['jobs']]"
   # Then get logs:
   gh api repos/nerdyparas/AiHomeCloud/actions/jobs/<JOB_ID>/logs | grep -E "error:|Error|Stop\." | grep -v warning | head 30
   ```

2. Possible next failure points:
   - **QEMU exec format error** → QEMU not properly registered, check `Set up QEMU` step logs
   - **cmake not found / version too old** → unlikely (ubuntu:20.04 has cmake 3.16)
   - **OpenSSL detection fails** → cmake configure step; check if `libssl-dev` installed correctly in container
   - **Disk space** → `No space left on device` during `cmake --build`
   - **Linker errors** (`undefined reference to ...`) → library linking issue; may need `libssl1.1` or `libatomic`
   - **strip fails** → binary not produced, cmake build silently failed earlier

3. If QEMU approach itself fails, the next alternative to explore is using
   **GitHub Actions' built-in multi-platform matrix with `buildx`** — but this
   would require restructuring around Docker image builds rather than plain
   binary artifacts. Or use **`cross` Rust-style tooling** equivalent for C++.

4. Another alternative (if all CI approaches fail): pre-clone
   `telegram-bot-api` source, cmake configure natively on amd64 to generate
   all auto files, then run cross-compilation using `clang` with
   `--target=aarch64-linux-gnu` + sysroot (avoids the TDLib CMake
   `if(NOT CMAKE_CROSSCOMPILING)` guard since clang doesn't set that flag
   the same way gcc does).
