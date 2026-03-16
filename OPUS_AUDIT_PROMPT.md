# Audit Prompt — Claude Opus 4.6
# GitHub Copilot — Read-only analysis. Zero code changes. Zero file edits.
# Output: docs/audit/task_v5.md (and optionally docs/audit/audit_summary.md)

---

## Your role

You are a principal engineer doing a full audit of this repository.
Your ONLY permitted action is creating files inside `docs/audit/`.
You must NOT edit any source file, test file, config file, or workflow file.
You must NOT fix anything. You must NOT suggest "quick fixes" inline.
Every finding goes into `docs/audit/task_v5.md` as a numbered task that
another LLM can execute independently, one task at a time.

---

## What to audit — full scope

Work through each area below in order. Read the relevant files before writing
any findings. Do not skip areas because they look clean.

---

### Area 1 — Repository hygiene

Read every file at the repo root and in `kb/`.

Check for:
- Files that are AI session artifacts (prompt files, task planning docs,
  log files) that have no place in a production repo — list each one with
  its full path
- `.md` files in `kb/` that reference outdated class names, wrong project
  names, paths that no longer exist, or describe architecture that has
  been superseded — note specific stale lines with line numbers
- `README.md` — does it accurately describe the project, setup steps,
  and how to run tests? Note gaps or inaccuracies
- `logs.md` at root — is this a dev session log? Should it be in `.gitignore`
  or deleted?

Specific file to audit carefully:
**`.github/copilot-instructions.md`** — this is loaded by every AI session.
Check every claim it makes:
- Project name consistency (CubieCloud vs AiHomeCloud)
- Class name accuracy (`CubieColors`/`CubieTheme`/`CubieCard` vs actual
  class names in `lib/core/theme.dart` and `lib/widgets/app_card.dart`)
- Widget names listed — do they match what actually exists in `lib/widgets/`?
- `tasks.md` is referenced as "read this first" — does `tasks.md` exist?
- Any path, port, or architecture description that is wrong
- Any section referencing features that have been removed or renamed

---

### Area 2 — Backend: code correctness and completeness

Read all files in `backend/app/`. For each file check:

**config.py**
- Are `family_path`, `family_dir`, `entertainment_path`, `entertainment_dir`
  properties present? (They were planned in Sessions 2A.) If missing, log as bug.
- Is `shared_path` still the primary path or has it been aliased to `family_path`?
- Are there any hardcoded `/srv/nas/` or `/var/lib/cubie/` strings that should
  use `settings.nas_root` or `settings.data_dir`?

**store.py**
- Does `add_user()` accept and store `icon_emoji`? (Planned in emoji task.)
  If missing, log as missing feature with exact function signature needed.
- Does `add_user()` store `icon_emoji` in the user dict? Check the dict literal.
- Are there any direct JSON file reads/writes outside of `store.py`? Log each one.

**models.py**
- Does `CreateUserRequest` have `icon_emoji: str = ""`? If not, log as missing.
- Are there any Pydantic models with fields that no longer match what the
  frontend sends? Cross-reference with `lib/services/api/auth_api.dart`.

**routes/auth_routes.py**
- Does `list_user_names()` return `has_pin` and `icon_emoji` per user?
  (Planned in FIX_USER_PICKER_PIN and emoji tasks.) If it still returns
  only `{"names": [...]}` log as bug with exact fix needed.
- Does `create_user()` pass `icon_emoji` to `store.add_user()`? If not, log.
- Does the login endpoint accept an empty string PIN for no-PIN users? Check.
- Is there a `tasks.md` or any reference to `tasks.md` in this file? (No, but
  check for stale comments referencing old task numbers.)

**routes/telegram_upload_routes.py** and **telegram_bot.py**
- Are there any references to `settings.shared_path / "Entertainment"` that
  should now be `settings.entertainment_path`? Log each occurrence with
  file path and line number.
- Is there a hardcoded IP anywhere? (Was previously bug: `192.168.0.212`)
  Check all files with `grep -n "192.168"`.

**main.py**
- Is there a one-time migration block for `shared/` → `family/`? If not, log.
- Is the telegram queue worker started in the lifespan block? If not, log
  as planned-but-missing (Session 5).

**file_sorter.py**
- Are `ENTERTAINMENT_SORT_RULES` and entertainment-aware `_collect_inboxes()`
  present? If the entertainment path logic is missing, log with scope of fix.

**scripts/first-boot-setup.sh**
- Does the DIRS array include `family/` and `entertainment/` and their
  subdirectories? Or does it still reference the old `shared/` path?
- Is minidlna configured with the new `entertainment/` paths?

---

### Area 3 — Flutter: code correctness and completeness

Read all files in `lib/`. For each area:

**lib/core/constants.dart**
- Are `familyPath` and `entertainmentPath` constants present?
  (`/srv/nas/family/` and `/srv/nas/entertainment/`)
- Does `sharedPath` still point to the old path or has it been updated?

**lib/services/api/auth_api.dart**
- Does `UserPickerEntry` model exist with `name`, `hasPin`, `iconEmoji` fields?
- Does `fetchUserEntries()` method exist (replacing `fetchUserNames`)?
- Does `createUser()` accept `iconEmoji` named parameter?
- Is `fetchUserNames` still present anywhere as a call site that should
  have been updated to `fetchUserEntries`? Grep for all call sites.

**lib/screens/onboarding/**
- Does `profile_creation_screen.dart` exist?
- Does `splash_screen.dart` auto-scan (no button tap required) as planned
  in Session 1A?
- Does `pin_entry_screen.dart` implement the tap-first, PIN-only-if-needed
  logic from FIX_USER_PICKER_PIN? Or does it still auto-show the PIN field?

**lib/navigation/app_router.dart**
- Are `/user-picker` and `/profile-creation` routes registered?
- Does the redirect logic allow authenticated users to reach `/user-picker`?
- Is `/pin-entry` kept for backwards compatibility?

**lib/widgets/**
- Does `user_avatar.dart` exist? (Planned in emoji task.)
- Does `emoji_picker_grid.dart` exist? (Planned in emoji task.)
- Are there any widgets that import a class that no longer exists
  (e.g., `CubieCard`, `CubieColors`)?

**lib/screens/main/files_screen.dart**
- Does it show 3 folder cards (Personal, Family, Entertainment)?
- Does it reference `AppConstants.familyPath` and `AppConstants.entertainmentPath`?
- Or does it still show only 2 cards (personal + Shared)?

**lib/screens/main/more_screen.dart**
- Has the redesign been applied (4 grouped cards + footer)?
- Or does it still have 9 section headers?
- Is `_ProfileCard` widget present?
- Is `_TailscaleRow` widget present?

**lib/screens/main/dashboard_screen.dart**
- Has the `_HeroStatusCard` been added?
- Has the active storage badge been removed?
- Has `_SystemCompactCard` replaced the 2×2 grid?
- Does `_StorageDeviceTile` show the Windows-style progress bar?

---

### Area 4 — Tests: coverage gaps and broken tests

**Backend tests** — read `backend/tests/conftest.py` and all `test_*.py` files.

Check for:
- `test_auth.py` — does it test the new `list_user_names` response format
  (`has_pin`, `icon_emoji` fields)? If it only tests the old `names` list
  format, it will pass on the old code and fail to catch regressions.
- `test_auth.py` — does it test empty-string PIN login for no-PIN users?
- `test_store.py` — does it test `add_user` with `icon_emoji` parameter?
- `test_telegram_bot.py` — does it test any of the entertainment path logic?
  Or does it hardcode `shared/Entertainment`?
- `test_file_sorter.py` — does it test `ENTERTAINMENT_SORT_RULES` and
  entertainment inbox collection? If not, log with suggested test cases.
- Is there any test for the `family/` path migration logic in `main.py`?
- Are there any tests that are currently skipped with `@pytest.mark.skip`
  without a documented reason?

**Flutter tests** — read `test/` directory.

Check for:
- `test/screens/` — which screens have zero test coverage? List them.
- Is `pin_entry_screen` tested for the tap-first flow?
- Is `profile_creation_screen` tested at all?
- Is `stat_tile_test.dart` testing the new two-column layout or the old
  vertical layout? (If old layout was updated, test may be wrong.)
- `test/widgets/app_card_test.dart` — does it still pass given any
  `AppCard` API changes?
- Are there any tests importing `CubieCard` or `CubieColors` that will fail?

---

### Area 5 — CI/CD: workflow correctness

Read `.github/workflows/backend-tests.yml` and `.github/workflows/flutter-analyze.yml`.

Check for:
- **Python version mismatch**: CI uses Python 3.12. The Radxa Cubie runs
  Python 3.11 (as established in previous sessions). Does this matter for
  any f-string, match statement, or type hint syntax used? Note any
  Python 3.12-only syntax found in backend code.
- **Missing path triggers**: `flutter-analyze.yml` only triggers on
  `lib/**`, `test/**`, `pubspec.yaml`. It does NOT trigger on changes to
  `lib/core/theme.dart` (already covered by `lib/**`, fine) but does it
  trigger on `analysis_options.yaml` changes? Check.
- **Missing path triggers for scripts**: `backend-tests.yml` triggers on
  `backend/**`. Changes to `scripts/first-boot-setup.sh` are never tested
  by CI — is there a `bash -n` (syntax check) step? If not, log.
- **Flutter version**: `flutter-version: '3.41.x'` — is this the version
  actually used in development? Check `pubspec.yaml` for SDK constraints.
- **No integration test job**: Is there a plan for device tests or is the
  `test_hardware_integration.py` always ignored? Log as gap if no strategy.
- **bandit and pip-audit**: Are these actually blocking PRs on failure or
  just informational? Check if they use `continue-on-error`.

---

### Area 6 — Redundant code

Search the entire codebase for:

- Any file that imports `MyFolderScreen` or `SharedFolderScreen` — these
  may have been superseded by `FilesScreen`. Check if they are still
  referenced in the router or anywhere. If they exist but are unreachable,
  log as dead code.
- The old `_TailscaleCard` widget — if the More screen redesign is done,
  this may now be unused. Check all import/usage sites.
- `QrPairPayload` in `user_models.dart` — is QR pairing still used anywhere
  in the app? Search all import sites. If unused, log as dead code.
- Any `print()` calls in backend Python files — should be `logger.*`.
- Any `debugPrint()` or `print()` calls in Flutter files in `lib/` (not `test/`).
- Duplicate constant definitions — search for any value defined in both
  `AppConstants` and hardcoded elsewhere.
- `_uptime()` helper — after dashboard redesign, does it exist in multiple
  widgets? It should exist once or be extracted to a utility.

---

### Area 7 — Security and safety

- Check all FastAPI endpoints for missing authentication where it should
  be required. Pay special attention to any new endpoints added in recent
  sessions (family paths, entertainment paths).
- Check `list_user_names` — it is intentionally public (no auth). Confirm
  it returns ONLY `name` and `has_pin` and `icon_emoji`, never the PIN hash,
  never the user ID, never `is_admin`.
- Check `first-boot-setup.sh` for any `chmod 777` or world-writable
  directories being created.
- Check if `CUBIE_SECRET_KEY` or any secret defaults are hardcoded in
  `config.py` — they should require environment variables.

---

## Output format — docs/audit/task_v5.md

Create `docs/audit/task_v5.md` with this exact structure:

```markdown
# AiHomeCloud — Audit Task List v5
# Generated by: Claude Opus 4.6
# Date: [today]
# Status: All tasks OPEN — none have been applied

---

## How to use this file

Work through tasks in order. Each task is self-contained.
Mark a task DONE by changing [ ] to [x] after completing and verifying it.
Do not skip tasks — if a task has no findings, mark it N/A with a note.

---

## CRITICAL — Must fix before next device test

### TASK-001: [Short title]
**File:** path/to/file.ext (line N)
**Finding:** Clear description of what is wrong or missing.
**Fix:** Exact description of what change is needed. Include the old value
and the new value where applicable. Be specific enough that the fix can be
applied without reading any other document.
**Test:** How to verify the fix worked (command to run, or behaviour to check).

### TASK-002: ...

---

## HIGH — Should fix before release

### TASK-0NN: ...

---

## MEDIUM — Technical debt and coverage gaps

### TASK-0NN: ...

---

## LOW — Hygiene and cleanup

### TASK-0NN: ...

---

## N/A — Checked, no issues found

List each Area that was clean with a one-line note.
```

Priority rules:
- **CRITICAL**: Will cause a crash, a security issue, or a test failure on CI
- **HIGH**: Feature is broken or silently wrong (wrong path, missing field, stale route)
- **MEDIUM**: Test gap, dead code, missing coverage, orphaned file
- **LOW**: Naming, hygiene, minor inconsistency

---

## Output format — docs/audit/audit_summary.md (optional but recommended)

If the total number of tasks exceeds 20, also create `docs/audit/audit_summary.md`:

```markdown
# Audit Summary

## Total findings: N
- CRITICAL: N
- HIGH: N
- MEDIUM: N
- LOW: N

## Biggest risks
[3-5 bullet points of the most impactful issues found]

## What is clean
[Brief list of areas with no issues]

## Recommended fix order
[Ordered list of task IDs in the sequence another LLM should tackle them,
 with a one-line reason for the ordering]
```

---

## Constraints — strictly enforced

1. **No source file edits.** Read-only. If you find yourself writing code
   into a source file, stop and put it in `task_v5.md` instead.
2. **No deletions.** Do not delete any file. Log it as a task.
3. **No assumptions.** If you cannot read a file to verify a claim,
   say "could not verify — check manually" in the task.
4. **One task per finding.** Do not bundle multiple bugs into one task.
   Each task must be independently actionable.
5. **Be specific.** "Update auth_routes.py" is not a task.
   "auth_routes.py line 175: `list_user_names` returns `{names: [...]}` but
   should return `{users: [{name, has_pin, icon_emoji}]}`" is a task.
6. **Output files only in `docs/audit/`.** Create the directory if needed.
   Do not create files anywhere else.
