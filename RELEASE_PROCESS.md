# Release Process — telegram-bot-api Binaries

## Overview

Pre-built `telegram-bot-api` binaries for multiple architectures are published
as GitHub Release assets. AiHomeCloud downloads the correct binary automatically
when a user enables the **2 GB Telegram file transfer** feature — eliminating a
25–40 minute source compilation on the device.

The binaries are cross-compiled on x86_64 GitHub Actions free-tier runners using
standard GNU cross-compilation toolchains. No ARM hardware or paid runners are
needed.

---

## Architecture Support

| Binary artifact | CPU arch | Target devices |
|-----------------|----------|----------------|
| `telegram-bot-api-linux-amd64` | x86_64 | Servers, PCs, VMs |
| `telegram-bot-api-linux-arm64` | aarch64 | Raspberry Pi 4/5, Radxa Cubie A7Z, Orange Pi 5, Rock 4 |
| `telegram-bot-api-linux-armv7` | armv7l | Raspberry Pi 2/3 (32-bit OS), older SBCs |

---

## How to Create a New Release

### Option A — Tag-triggered (recommended for production)

```bash
# Tag the commit you want to release
git tag tgapi-v1.0.0
git push origin tgapi-v1.0.0
```

The `build.yml` workflow starts automatically, builds all three binaries in
parallel (~15 min), and publishes a GitHub Release with them attached.

### Option B — Manual dispatch

1. Go to **Actions → Build telegram-bot-api Binaries → Run workflow**
2. Enter a release tag (e.g. `tgapi-v1.0.0`)
3. Click **Run workflow**

The same build + release steps run and publish the release.

---

## CI Workflow Summary

File: `.github/workflows/build.yml`

```
Push tgapi-v* tag  (or manual dispatch)
   ↓
Three parallel build jobs (ubuntu-22.04 x86_64 runner each)
   │
   ├── linux-amd64  — native g++, cmake, libssl-dev, zlib1g-dev
   ├── linux-arm64  — gcc-aarch64-linux-gnu + libssl-dev:arm64 (multiarch)
   └── linux-armv7  — gcc-arm-linux-gnueabihf + libssl-dev:armhf (multiarch)
   ↓
Artifacts uploaded (retention: 30 days)
   ↓
Release job: downloads all 3 artifacts → gh release create → assets attached
```

**Typical build times (parallel):**

| Job | Estimated time |
|-----|---------------|
| linux-amd64 (native) | 5–8 min |
| linux-arm64 (cross) | 10–15 min |
| linux-armv7 (cross) | 10–15 min |
| Total wall-clock | ~15 min |

**GitHub Actions free minutes used:** ~30–38 min per release (3 parallel × ~13 min avg).
GitHub Free tier includes 2,000 min/month — one release uses ~2% of the monthly budget.

---

## How AiHomeCloud Uses the Binary

When a user enables 2 GB mode in the app, `telegram_routes.py` runs the
`_run_local_api_setup` job:

1. **Download attempt first** — tries `https://github.com/nerdyparas/AiHomeCloud/releases/latest/download/telegram-bot-api-linux-{arch}`
2. If download succeeds → skips all source compilation steps
3. If download fails (no release, network error) → falls back to full source
   compilation on the device (~25–40 min)

This means:
- Users with any supported SBC get instant 2 GB mode activation
- Users on unsupported architectures (armv6) still get compilation as fallback
- No dependency on the release being present — the system is always functional

---

## Updating the Binary

The `telegram-bot-api` upstream does not release often. When a new upstream
version is needed:

1. Check [tdlib/telegram-bot-api releases](https://github.com/tdlib/telegram-bot-api/releases) for changes
2. Run the workflow (Option A or B above) to rebuild from the latest upstream commit
3. Use a new tag: `git tag tgapi-v1.1.0 && git push origin tgapi-v1.1.0`

The install script always downloads from `releases/latest`, so existing devices
will get the new binary on their next 2 GB mode setup.

---

## Troubleshooting

### Build fails at cmake configure step (cross-compilation)

Check that the multiarch packages installed correctly:
```
sudo dpkg --add-architecture arm64
sudo apt-get install libssl-dev:arm64
```
If `apt-get update` fails, the `ports.ubuntu.com` mirror may be temporarily down.
The workflow retries automatically on failure via `--retry 3`.

### Binary fails to start on device

Verify the binary matches the device architecture:
```bash
file /usr/local/bin/telegram-bot-api
uname -m
```
If they don't match, re-run the install script manually:
```bash
sudo bash scripts/install.sh
```

### Release assets missing

If the `release` job failed after the `build` jobs succeeded, the artifacts are
still available under **Actions → workflow run → Artifacts** for 30 days.
Download them manually and re-attach with:
```bash
gh release upload tgapi-v1.0.0 telegram-bot-api-linux-*
```
