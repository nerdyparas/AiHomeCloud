# AiHomeCloud — Blueprint Self-Critique

> **Purpose:** Honest audit of `engineering-blueprint.md` and `devops-testing-strategy.md`.
> Documents concrete bugs in prescriptions, hidden assumptions, scalability risks, and
> structural weaknesses. Every point listed here must be resolved before implementation.
>
> **Date:** March 2026
> **Authored by:** Post-generation review pass

## 2025-07-25 — Audit update

**Fixed since original critique:**
- **Bug B1** (threading.Lock useless in asyncio): **FIXED.** `store.py` now uses `asyncio.Lock()` globally.
- **Bug B3** (bcrypt blocks event loop): **FIXED.** `auth.py` now uses `loop.run_in_executor()` for both hash and verify.

**Still open:**
- **Bug B2** (deploy.sh curl fails against self-signed cert): Not yet fixed.
- All assumption items (A1–A5) remain relevant.
- All scalability risks (S1–S4) remain relevant.
- WebSocket debounce (S1) partially addressed — `main_shell.dart` has 12s debounce and 2-miss threshold, but reconnect logic could still be improved.

---

## 🔴 Concrete Bugs in My Own Prescriptions

### Bug 1 — `threading.Lock` is useless in an asyncio process

**Location:** `engineering-blueprint.md` §2.2 (RISK-02 fix)

**The prescription:**
```python
_file_locks: dict[Path, threading.Lock] = {}
def _write_json_atomic(...):
    with _get_lock(path):  # threading.Lock
```

**Why it is wrong:**

FastAPI with `--workers 1` runs entirely in a single OS thread on the asyncio event loop.
`threading.Lock` only guards against *OS thread* contention. Two coroutines running in the
same thread can both enter `with _get_lock(path):` without blocking each other — because
`threading.Lock.acquire()` in a single-threaded program always succeeds immediately. There
is no other OS thread to hold the lock. The prescribed fix provides **zero concurrency
protection** for the actual problem it was meant to solve.

**Correct fix:**
Use `asyncio.Lock`, used with `async with`, which yields to the event loop during
contention. This forces `store.py` functions to become `async`, which cascades through
every caller. That cascading refactor must be planned — it is not a drop-in replacement.

---

### Bug 2 — The deploy script will always fail its health check

**Location:** `devops-testing-strategy.md` §5.3 (`deploy.sh`)

**The prescription:**
```bash
HEALTH=$(curl -sf --max-time 5 https://$TARGET:8443/api/health ...)
```

**Why it is wrong:**

`curl` validates TLS certificates by default. The Cubie uses a self-signed certificate.
This `curl` call will fail with `SSL certificate problem: self-signed certificate` on every
single deployment. The health check gate that was meant to prevent bad deployments will
always report failure, causing the rollback to trigger on every deploy — even successful ones.

Using `-k` / `--insecure` would suppress the error but reintroduce the MITM risk that TLS
was supposed to prevent.

**Correct fix:**
Pass `--cacert /path/to/cert.pem` to curl, where the cert is distributed to the
deployment machine during the initial setup step. This requires the deployment host to hold
a copy of the device cert, which must be documented as a prerequisite.

---

### Bug 3 — bcrypt on ARM blocks the asyncio event loop

**Location:** `engineering-blueprint.md` §3.2 (SEC-03 fix)

**The prescription:**
```python
from passlib.hash import bcrypt
user["pin_hash"] = bcrypt.hash(pin)  # Called synchronously in a route handler
```

**Why it is wrong:**

On ARM Cortex-A55, `bcrypt.hash()` at cost=10 takes approximately **300–500 ms**. Called
synchronously inside a route handler in a single-worker asyncio process, this blocks the
entire event loop for half a second. Every other API request queued during that window is
stalled — including WebSocket monitor frames, file listing requests, and any concurrent
user's activity.

**Correct fix:**
```python
import asyncio
hashed = await asyncio.get_event_loop().run_in_executor(None, bcrypt.hash, pin)
```

Every `bcrypt.hash()` and `bcrypt.verify()` call must be offloaded to a thread pool via
`run_in_executor`. The blueprint never mentioned this. The hardware checklist would only
catch this if a tester timed a concurrent request during a login operation.

---

## 🟠 Hidden Assumptions That Invalidate Entire Sections

### Assumption 1 — "JSON store reads are a low-frequency path"

**Location:** `engineering-blueprint.md` §1.1 (Scale table) + §1.3 (NFR-PERF-04)

The blueprint states `JSON store write frequency ≤ 1 write/second` and dismisses the
database question. But **read frequency** is what matters for `get_current_user`.

Every authenticated HTTP request calls:
`require_admin` → `store.find_user()` → `get_users()` → `path.read_text()` → `json.loads()`

During a file transfer that issues many small requests (directory listings, metadata
fetches), this is a file open + read + JSON parse on **every request**. On a slow SD card
(`/var/lib/cubie/` lives there), each `read_text()` can take 5–20 ms. NFR-PERF-04 mentions
"cache for 1 second" but no implementation was provided. Without the cache, the "low
frequency" assumption collapses under any real use pattern.

**Required fix:** Implement the 1-second TTL in-memory cache for `get_users()` before any
performance testing is considered valid.

---

### Assumption 2 — No job tracking for long-running operations

**Location:** `engineering-blueprint.md` §2.2 (subprocess_runner.py)

The blueprint prescribes `asyncio.create_subprocess_exec` with a 30-second timeout for all
subprocess calls. It then prescribes using this for `format`, `mount`, and firmware updates.

**The conflict:** `mkfs.ext4` on a 1 TB disk takes **3–8 minutes**. With a 30-second
timeout it always fails on large disks. With no timeout it hangs the only worker
indefinitely if the process stalls.

The blueprint has **no concept of long-running job tracking**. Operations that exceed 10
seconds require the `202 Accepted` + polling pattern:

```
POST /api/v1/storage/format → 202 { "jobId": "abc123" }
GET  /api/v1/jobs/abc123    → { "status": "running", "progress": 42, "message": "Writing..." }
GET  /api/v1/jobs/abc123    → { "status": "completed" }
```

Without this, format, OTA firmware update, and large-file indexing all have unresolvable
timeout conflicts. This is a foundational API pattern gap, not a detail.

---

### Assumption 3 — Device token = always admin bypasses the multi-user model

**Location:** `engineering-blueprint.md` §2.1 (RISK-06 / auth.py), `auth.py` prototype

```python
if user.get("type") == "device":
    return user  # Device tokens are admin-level
```

The hidden assumption: device tokens are issued once during pairing and are held only by
the admin who performed the pairing. But the blueprint never specifies:

- Is there **one token for the whole device** (phone), or **one token per user per device**?
- If one token, all users on that phone are silently admin.
- If per-user tokens, how are they issued after pairing? What flow derives them?
- How does the backend know which family member is making the request?

The multi-user access model — who can read whose files, who can administer — is entirely
unspecified. The `type == "device"` shortcut is a security architecture gap hiding behind a
convenience clause. This must be resolved before FR-AUTH-06 is considered designed.

---

### Assumption 4 — "Multiple SBC support" has zero architectural backing

**Location:** `engineering-blueprint.md` Introduction, `kb/hardware.md`

The stated product goal is supporting multiple low-cost ARM SBCs. The entire backend is
written against Cubie A7Z specifics with no abstraction layer:

| Hardcoded assumption | Reality on other boards |
|---|---|
| SD card is `/dev/mmcblk0` | On some boards it is `/dev/mmcblk1` or `/dev/mmcblk2` |
| LAN interface `eth0`/`end0`/`enp1s0` | Orange Pi 5 uses `enP4p65s0` |
| Temp at `thermal_zone0` | Rock Pi 5 has different zone numbering; requires zone scanning |
| `lsblk TRAN=usb` for USB detection | Safe across boards |
| `bluetoothctl power on/off` | Safe on most Debian-based Linux |
| `nmcli` for WiFi management | Safe on most Debian-based Linux |

There is no `CUBIE_BOARD_TYPE` config, no board detection at startup, and no HAL (Hardware
Abstraction Layer) for the `system/` layer. A user on Orange Pi 5 gets broken network
management and wrong temperature readings. "Multiple SBC support" remains a stated goal
with zero architectural support in the current design.

**Required fix:** The `system/` layer (block_devices.py, net_utils.py, proc_reader.py)
must have board-specific configuration injected via settings, with sensible defaults and
a startup diagnostic that logs "detected interface: enP4p65s0" rather than silently
returning empty data.

---

### Assumption 5 — QR cert pinning overstated as eliminating TOFU

**Location:** `engineering-blueprint.md` §3.3 (Pairing Security)

The blueprint claims the QR code containing the cert fingerprint "eliminates the Trust On
First Use window." This is overstated.

**The gap:** The QR is only trustworthy if it is viewed on a secure channel (directly on
the Cubie's connected monitor or on an already-trusted phone). If the admin screenshots
the QR and shares it via WhatsApp, Telegram, email, or SMS, an attacker who intercepts the
message has the fingerprint, OTP, serial, and IP — everything needed to impersonate the
device or perform a race-condition first-connection.

Additionally, the "re-pair action clears the fingerprint" is a **downgrade attack vector**.
Any party who can trigger the re-pair dialog (social engineering, brief physical access to
phone) opens a fresh TOFU window. The blueprint does not specify what user-visible friction
guards the re-pair action (e.g., requires admin PIN confirmation first).

The correct claim is: the QR approach *reduces* the TOFU window to the QR display moment,
not *eliminates* it.

---

## 🟡 Scalability Risks (Within the Stated 8-User Bound)

### Risk 1 — WebSocket `degraded` state causes constant UI flicker

**Location:** `engineering-blueprint.md` §2.6 (Connection State Machine)

On a home LAN with a phone in power-saving mode, the WebSocket connection drops every time
the screen turns off — typically every 30–60 seconds. As prescribed, the UI would flash
amber/degraded constantly during normal evening use.

No debounce delay was specified. The state machine needs a minimum sustained-disconnection
threshold before showing `degraded` (e.g., only show `degraded` after 10 continuous seconds
of WebSocket disconnection, not immediately on the first drop).

---

### Risk 2 — `FutureProvider` has no error recovery path

**Location:** `engineering-blueprint.md` §2.5 (Flutter State Architecture)

When a `FutureProvider` API call fails, Riverpod marks it as error state. The user sees
an error widget. `FutureProvider` does not automatically retry. The user must pull-to-refresh
or navigate away and back. For providers like `storageDevicesProvider` or `deviceInfoProvider`,
this is a dead-end UX.

The blueprint does not propose migrating existing `FutureProvider`s to `AsyncNotifier`,
which supports explicit refresh, retry-with-backoff, and optimistic updates. This gap means
any network hiccup leaves the app in a manually-unrecoverable state.

---

### Risk 3 — File pagination spec is incomplete

**Location:** `engineering-blueprint.md` FR-FILE-01

`?page=&limit=` was specified but never designed:

- **Sort key:** What determines order? Alphabetical? Modification date? Is it configurable?
- **Stability:** If a file is created between page 1 and page 2 requests, does it appear twice (if sorted by `modified` descending) or not at all?
- **Total count:** Does the response include `{"total": 1000, "items": [...]}` or just items? Flutter needs the total to render a progress indicator and know when to stop loading pages.
- **Cursor vs. offset:** Offset-based pagination (`page=2&limit=50`) is unstable under concurrent writes. Cursor-based (`after=<last_item_id>`) is stable but more complex.

A pagination spec without sort key stability and total count is a note to self, not an
implementable specification.

---

### Risk 4 — AI event queue + full re-scan is O(library size)

**Location:** `devops-testing-strategy.md` §8.1 (File Event Infrastructure)

Section 8.1 sets `asyncio.Queue(maxsize=1000)` for file events and states "indexer will
re-scan on startup" after queue overflow. If the v2 indexer starts after years of operation
with millions of files uploaded (filling and overflowing the 1000-slot queue many times),
the startup re-scan must enumerate the entire filesystem.

For a 4 TB NAS with 500,000 files, a full filesystem scan with stat() calls takes
**5–30 minutes** and saturates the NAS I/O, impacting every user's file access during
that window.

A complete design requires incremental indexing using filesystem modification timestamps
(scan only directories modified since `last_indexed_at`, stored per-directory in
`index.db`). The "re-scan on startup" strategy was a placeholder, not an algorithm.

---

## 🔵 Structural Weaknesses in the Blueprint Itself

### Weakness 1 — Layer discipline has no CI enforcement mechanism

**Location:** `engineering-blueprint.md` §2.2 (Target Directory Structure)

The three-layer architecture (`routes/` → `services/` → `system/`) is stated as a rule
with one grep check: `! grep -rn "shell=True" backend/app/"`. This only catches one
specific violation. A developer who calls `asyncio.create_subprocess_exec` directly in a
route handler violates the architecture silently.

Layer discipline without tooling enforcement has a half-life of approximately two months in
an AI-assisted codebase where generated code routinely ignores structural conventions.

**Required enforcement:**
- Import guard: `system/` modules should raise `ImportError` if imported from `routes/`
  directly (use a `__init__.py` check or a custom `ruff` plugin rule)
- Add to CI: check that no file in `routes/` contains `import asyncio` + `create_subprocess`
- The `subprocess_runner.py` import path should be the only path that imports `asyncio.subprocess`

---

### Weakness 2 — AI RAM budget math ignores OS and services (~300 MB)

**Location:** `devops-testing-strategy.md` §8.3

**The claim:**
> "backend (256 MB) + Phi-3.5-mini (450 MB) = 706 MB — acceptable"

**What was omitted:**

| Component | Typical RSS |
|---|---|
| Linux kernel + systemd | ~150 MB |
| Samba (`smbd` + `nmbd`) | ~60–100 MB |
| NFS server | ~40 MB |
| DLNA (minidlnad) | ~30 MB |
| journald buffer | ~30 MB |
| SSH daemon | ~10 MB |
| **OS + services subtotal** | **~320–360 MB** |

**Actual footprint:**
- Baseline without AI: ~550–600 MB
- Backend + Phi-3.5-mini: +706 MB
- **Total peak: ~1.25–1.35 GB**

This is within the 8 GB ceiling, but the arithmetic was presented as careful when it was
not. During a peak spike (AI indexing running + large file upload + 3 WebSocket clients
+ Samba transfer), the combined RSS could approach 1.8–2.0 GB. Still safe on 8 GB, but
the claim "706 MB — acceptable" understates the real footprint by ~40%.

Additionally, Phi-3.5-mini's 450 MB figure is its **steady-state inference footprint**.
Model load from disk (cold start) peaks at ~700 MB before settling. The blueprint did not
distinguish peak vs. steady-state memory, which matters for the `systemd` `MemoryMax=`
parameter in the service unit.

---

### Weakness 3 — pip-tools pinning is architecture-dependent

**Location:** `devops-testing-strategy.md` §5.4

The blueprint prescribes `pip-compile requirements.in` running on `ubuntu-latest` in
GitHub Actions (x86_64). Packages like `cryptography`, `passlib[bcrypt]`, and `psutil`
all require compiled binary wheels.

`pip-compile` on x86_64 produces a `requirements.txt` pinned to **x86_64 wheel versions**.
When `pip install -r requirements.txt` runs on the ARM64 Cubie, pip may:

1. Find an ARM64 wheel for the exact pinned version → works
2. Find no ARM64 wheel → fall back to building from source (requires `build-essential`,
   `libssl-dev`, `libffi-dev` on the device — slow and fragile)
3. Find no ARM64 wheel and no build deps → fail completely

**Correct fix:** Run `pip-compile` with explicit cross-platform targeting:
```bash
pip-compile requirements.in \
  --platform linux_aarch64 \
  --python-version 3.12 \
  --implementation cp \
  --output-file requirements-arm64.txt
```
This requires `pip-tools >= 7.0` and resolves only packages with `linux_aarch64` wheels
available on PyPI. The ARM64-targeted lock file should be used on the device; the standard
one (or no locking) used in CI.

---

### Weakness 4 — OTP is lost on backend restart; not called out as a trade-off

**Location:** `engineering-blueprint.md` §3.3 (Pairing Security)

The OTP pairing design states OTPs are "stored in memory with 5-minute TTL." If the
backend restarts during the 5-minute window (power glitch, deployment, systemd watchdog
restart), the OTP is silently discarded.

This is a regression from the current static key (which survives restarts trivially). The
blueprint never acknowledged this trade-off, leaving implementers unaware.

**Options (each with trade-offs):**

| Option | Pro | Con |
|---|---|---|
| Keep in-memory only | Simple; no disk I/O | Lost on restart |
| Persist to `otp.json` with TTL check on read | Survives restarts | More code; file I/O |
| Explicit trade-off documentation only | Zero code | User frustration during pairing on unstable hardware |

The choice must be explicit. The blueprint silently chose in-memory by not mentioning the
alternative, which is not the same as making a considered decision.

---

### Weakness 5 — Soft-delete `.trash/` has no emptying policy

**Location:** `engineering-blueprint.md` FR-FILE-04

FR-FILE-04 requires deleted files to move to `.trash/` before permanent removal. The
blueprint never specified:

- **When is `.trash/` emptied?** Never? After 30 days? On explicit user "empty trash"
  action? On unmount?
- **Storage accounting:** `.trash/` resides on the NAS volume. It counts against the
  `StorageStats` total but is invisible in the file browser. A user who "deletes" 100 GB
  of files sees their storage usage unchanged with no explanation.
- **Quota enforcement:** Does a user's personal folder quota include their `.trash/` items?
- **Unmount safety:** On `POST /api/v1/storage/unmount`, is `.trash/` cleared first?
  Or does its content remain on the raw device, visible if the device is mounted elsewhere?
- **Admin visibility:** Can an admin see all users' `.trash/` contents? Should they be able to?

A soft-delete feature without an emptying policy is not a complete feature — it is a
half-measure that defers data loss by an indeterminate period while consuming invisible
storage. It must be specified fully or deferred entirely (keep hard delete in v1, implement
soft delete in v2 as a complete feature).

---

## Summary Table

| ID | Issue | Severity | Location |
|---|---|---|---|
| B1 | `threading.Lock` is inert in asyncio — zero protection | **Critical bug** | blueprint §2.2 RISK-02 |
| B2 | `curl` against self-signed cert always fails in deploy.sh | **Critical bug** | devops §5.3 |
| B3 | `bcrypt.hash()` blocks event loop on ARM; not offloaded | **High bug** | blueprint §3.2 SEC-03 |
| A1 | JSON store read on every request; cache not implemented | **High assumption** | blueprint NFR-PERF-04 |
| A2 | No job-tracking pattern for long-running ops (format, OTA) | **High assumption** | blueprint §2.2 |
| A3 | `type=="device"` → admin bypasses undefined multi-user model | **High assumption** | blueprint FR-AUTH-06 |
| A4 | "Multiple SBC" goal has no HAL or board abstraction | **Medium assumption** | blueprint intro, §2.3 |
| A5 | TOFU window not eliminated, only reduced; re-pair is a downgrade vector | **Medium assumption** | blueprint §3.3 |
| S1 | WS `degraded` flickers on every screen lock; no debounce | **Medium UX risk** | blueprint §2.6 |
| S2 | `FutureProvider` has no retry/recovery path on error | **Medium risk** | blueprint §2.5 |
| S3 | Pagination spec missing sort stability, total count, cursor vs. offset | **Medium risk** | blueprint FR-FILE-01 |
| S4 | AI startup full re-scan is O(library size), not incremental | **Medium scalability** | devops §8.1 |
| W1 | Layer discipline has no CI import guard or tooling enforcement | **Structural** | blueprint §2.2 |
| W2 | AI RAM budget ignores OS + services baseline (~320 MB) | **Structural** | devops §8.3 |
| W3 | pip-compile runs on x86_64; ARM64 wheels not guaranteed | **Deployment risk** | devops §5.4 |
| W4 | OTP lost on restart; not documented as a trade-off | **UX risk** | blueprint §3.3 |
| W5 | Soft-delete has no emptying policy, quota accounting, or unmount behavior | **Incomplete spec** | blueprint FR-FILE-04 |

---

## Execution Guidance

**Fix before writing any code from the blueprints (B1–B3 invalidate implementations):**

1. Replace all `threading.Lock` prescriptions with `asyncio.Lock` + async store functions
   — design the async cascade first
2. Fix `deploy.sh` health check: add `--cacert` path and document cert distribution as a
   deployment prerequisite
3. Wrap every `bcrypt.hash()` / `bcrypt.verify()` call in `run_in_executor`
4. Define the job-tracking pattern (`/api/v1/jobs/{id}`) before implementing format, OTA,
   or any operation that exceeds 10 seconds
5. Resolve the multi-user token model (device token vs. per-user token) — this is a
   security architecture decision, not an implementation detail

**Fix before v1 release (A1–S4 are real product risks):**

6. Implement the 1-second TTL cache for `get_users()` in `store.py`
7. Add debounce to WebSocket `degraded` state (10-second sustained threshold)
8. Replace `FutureProvider`s with `AsyncNotifier` where retry is needed
9. Complete the pagination spec: sort key, stability contract, total count in response
10. Document OTP-on-restart trade-off explicitly; decide persist vs. in-memory

**Fix before v2 / AI features:**

11. Design incremental indexing strategy (scan only `mtime`-changed directories)
12. Add cross-platform `pip-compile` to CI using `--platform linux_aarch64`
13. Add `CUBIE_BOARD_TYPE` config and board-specific adapters in `system/`
14. Complete soft-delete spec before implementing: emptying policy, quota, unmount behavior
15. Add CI import guard for layer discipline enforcement

---

*Document version: 1.0 — March 2026*
*Source: Post-generation self-review of `engineering-blueprint.md` and `devops-testing-strategy.md`*
