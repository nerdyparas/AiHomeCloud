# Opus 4.6 — Full Repository Audit, Fix, and Knowledge Base Build
# This prompt authorises file edits. Read everything first. Then act.

---

## Your mandate

You are a senior engineer taking ownership of this repository's AI context
layer. Your job is to make the codebase self-documenting for any AI model
that works on it in the future — including sessions where the model has no
prior context at all.

**You have full write access.** Edit, create, and delete files as needed.
The only constraint: never break working source code. Documentation and
`.md` files are completely yours to reshape.

Work in order. Complete each phase before starting the next.

---

## Phase 0 — Read before you write

Before touching any file, read every file listed below in full.
Do not skim. The entire audit depends on accuracy.

**Source files to read:**
```
lib/core/theme.dart
lib/core/constants.dart
lib/core/error_utils.dart
lib/models/models.dart
lib/models/user_models.dart
lib/models/file_models.dart
lib/models/device_models.dart
lib/models/storage_models.dart
lib/models/service_models.dart
lib/models/notification_models.dart
lib/services/auth_session.dart
lib/services/api_service.dart
lib/services/api/auth_api.dart
lib/services/api/family_api.dart
lib/services/api/files_api.dart
lib/services/api/system_api.dart
lib/services/api/storage_api.dart
lib/services/api/services_network_api.dart
lib/services/network_scanner.dart
lib/services/discovery_service.dart
lib/providers.dart
lib/navigation/app_router.dart
lib/navigation/main_shell.dart
lib/widgets/app_card.dart
lib/widgets/stat_tile.dart
lib/widgets/file_list_tile.dart
lib/widgets/folder_view.dart
lib/widgets/storage_donut_chart.dart
lib/widgets/notification_listener.dart
lib/screens/onboarding/splash_screen.dart
lib/screens/onboarding/pin_entry_screen.dart
lib/screens/onboarding/network_scan_screen.dart
lib/screens/main/dashboard_screen.dart
lib/screens/main/files_screen.dart
lib/screens/main/more_screen.dart
lib/screens/main/family_screen.dart
lib/screens/main/my_folder_screen.dart
lib/screens/main/shared_folder_screen.dart
lib/screens/main/storage_explorer_screen.dart
lib/screens/main/telegram_setup_screen.dart
lib/screens/main/file_preview_screen.dart
lib/screens/main/folder_view_screen.dart
backend/app/main.py
backend/app/config.py
backend/app/store.py
backend/app/models.py
backend/app/auth.py
backend/app/board.py
backend/app/subprocess_runner.py
backend/app/routes/auth_routes.py
backend/app/routes/system_routes.py
backend/app/routes/monitor_routes.py
backend/app/routes/file_routes.py
backend/app/routes/family_routes.py
backend/app/routes/service_routes.py
backend/app/routes/storage_routes.py
backend/app/routes/network_routes.py
backend/app/routes/adguard_routes.py
backend/app/routes/tailscale_routes.py
backend/app/routes/telegram_routes.py
backend/app/routes/telegram_upload_routes.py
backend/app/routes/jobs_routes.py
backend/app/routes/event_routes.py
backend/tests/conftest.py
.github/workflows/backend-tests.yml
.github/workflows/flutter-analyze.yml
pubspec.yaml
```

**Existing docs to read:**
```
.github/copilot-instructions.md
kb/api-contracts.md
kb/architecture.md               (may not exist yet)
kb/engineering-blueprint.md
kb/critique.md
kb/devops-testing-strategy.md
kb/hardware.md
kb/storage-architecture.md
kb/setup-instructions.md
logs.md
README.md
```

After reading, build a mental model of:
- Every class name that exists (vs what docs claim)
- Every route registered (vs what docs claim)
- Every nav tab (vs what docs claim)
- Every widget (vs what docs claim)
- Every env var prefix
- The `run_command()` return signature
- What `tasks.md` should contain vs whether it exists

---

## Phase 1 — Fix `.github/copilot-instructions.md`

This file is loaded automatically by GitHub Copilot on every session.
Every inaccuracy in it wastes tokens and causes bugs.

Rewrite it completely using only facts you verified in Phase 0.
Do not preserve any claim you cannot confirm from source code.

The rewritten file must contain these sections in this order:

### 1. Header
```markdown
# Copilot Instructions — AiHomeCloud
> Single source of truth for AI-assisted development.
> Last updated: [today's date]
> **If you change source code, update the relevant kb/ file before committing.**
```

### 2. How to orient yourself (5 lines max)
- Where to find the task list
- Where to find recent decisions  
- Where to find deep architecture docs
- The two validation commands
- The one-task-per-session discipline

### 3. Architecture Quick Reference

Two tables — Backend and Frontend — built from what you actually read.

**Backend table must include:**
- All route files you found in `backend/app/routes/` (not an assumed list)
- Correct env prefix (verify from `config.py`)
- Correct `run_command()` return signature from `subprocess_runner.py`
- Correct data dir and NAS root paths from `config.py`

**Frontend table must include:**
- Correct theme class names (verify from `lib/core/theme.dart`)
- Correct widget class names (verify from `lib/widgets/*.dart`)
- Correct nav tab names and count (verify from `main_shell.dart`)
- Correct API service structure (`api_service.dart` + `lib/services/api/` split)
- Correct onboarding screen names (verify from `lib/screens/onboarding/`)
- Correct main screen names (verify from `lib/screens/main/`)

### 4. Critical invariants (verbatim — these must stay exactly as written)
```
- run_command() returns (rc, stdout, stderr) — always unpack all three
- friendlyError(e) is the only error surface shown to users — never $e or e.toString()
- settings.nas_root and settings.data_dir are the only path references — never hardcode
- store.py is the only JSON persistence layer — no direct file reads elsewhere
- All HTTP calls need .timeout(ApiService._timeout) — no raw client calls
- Never shell=True in subprocess — always use run_command()
- Never show /dev/ paths, partition names, or filesystem types to users
- All file ops go through _safe_resolve() to sandbox under NAS root
- JWT sub claim = user_id — use user.get("sub") in all backend handlers
```

### 5. Common patterns

Keep the existing "Adding a new API endpoint" pattern (it is correct).
Keep "Adding a new screen" pattern.
Add a new pattern: **"Adding a new widget"**:
1. Create `lib/widgets/<name>.dart`
2. Use `AppCard` as container if it's a card-style component
3. Use `AppColors` for all colours — no hex literals
4. Update `kb/architecture.md` widget inventory table

### 6. KB index

Table of all `kb/` files with a one-line description of each.
Include every file you're going to create in Phase 2.

### 7. Self-maintenance rules (new section — critical)

This section instructs every future AI session how to keep docs current.
Write it as a checklist that triggers on specific code changes:

```markdown
## Keeping Documentation Current

These rules apply to every AI session working on this repo.
Treat documentation updates as part of the task — not optional.

| When you do this... | Also update this... |
|---|---|
| Add or change an API endpoint | `kb/api-contracts.md` — add/update the endpoint row |
| Add a new screen | `kb/architecture.md` — screen inventory table |
| Add a new widget | `kb/architecture.md` — widget inventory table |
| Add a new provider | `kb/architecture.md` — provider table |
| Add a new route to the router | `kb/architecture.md` — route table |
| Add a new backend route file | This file — backend table |
| Change a class/file name | This file — update the table row immediately |
| Change coding conventions | This file — update the relevant section |
| Add a new kb/ file | This file — add it to the KB index |
| Complete a significant feature | `kb/changelog.md` — one-line dated entry |
| Change hardware or deployment | `kb/hardware.md` or `kb/setup-instructions.md` |

**Never leave a session with stale documentation.**
If you're short on tokens, update documentation before adding new features.
```

---

## Phase 2 — Rebuild `kb/` for scale

The `kb/` folder is the long-term memory of this codebase. Restructure it
so it stays useful as the codebase doubles or triples in size.

### Files to keep and update

**`kb/hardware.md`** — keep, verify facts against `config.py` and `board.py`.
Remove the hardcoded `192.168.0.212` default IP — it was a dev-only value and
should not be in documentation.

**`kb/storage-architecture.md`** — keep, update if `config.py` shows different
paths than documented.

**`kb/setup-instructions.md`** — keep, verify commands against actual scripts.
Flag any step that references "QR pairing" — check if that flow still exists
in the current onboarding screens.

**`kb/api-contracts.md`** — this is critically stale (only 77 lines for a codebase
with 14 route files). Rebuild it by reading every route file.
Structure: one `##` section per route file. For each endpoint: method, path,
auth required (yes/no/admin), request body fields, response fields.
This is the most important kb file — make it complete.

**`kb/engineering-blueprint.md`** — keep, trim to remove any sections that
contradict the actual code you read. Add a note at the top:
`> Verified against codebase as of [today].`

**`kb/devops-testing-strategy.md`** — at 1,170 lines this is too long to be
useful as a quick reference. Keep the file but add a 20-line summary section
at the very top with: test commands, CI trigger rules, what's excluded and why
(`test_hardware_integration.py`), coverage areas.

**`kb/critique.md`** — keep as-is. It is a living self-audit document.
Prepend a dated entry for today noting what was fixed in this session.

### Files to create

**`kb/architecture.md`** — the single map of the whole system.

Structure:
```markdown
# Architecture Map

## System overview
[2-paragraph description of what AiHomeCloud is and how the two halves connect]

## Backend route inventory
| File | Prefix | Auth | Purpose |
[one row per route file, filled from what you read]

## Frontend screen inventory
| Screen file | Route path | Tab | Purpose |
[one row per screen, both main/ and onboarding/]

## Widget inventory
| Widget | File | Purpose |
[one row per widget in lib/widgets/]

## Provider inventory
| Provider | Type | Purpose |
[key providers from lib/providers.dart]

## API service structure
[Explain the api_service.dart singleton + lib/services/api/ split]

## Navigation structure
[Describe ShellRoute, the N tabs, and key named routes with their purposes]

## State management patterns
[Explain when to use FutureProvider vs StreamProvider vs StateNotifier]
```

**`kb/features.md`** — feature inventory for planning.

Structure:
```markdown
# Feature Inventory

## Implemented features
[List every user-facing feature with the screen(s) it lives in]

## Planned / in-progress
[List features that are in prompts or partially implemented — infer from
 the MASTER_PROMPT files and TASK files at the repo root]

## Deferred
[Features explicitly deferred — infer from kb/critique.md and prompt files]
```

**`kb/flutter-patterns.md`** — Flutter-specific patterns extracted from
the actual codebase. Not prescriptions — descriptions of what actually exists.

Sections:
- Widget composition patterns (how AppCard is used as container)
- Animation patterns (flutter_animate usage)
- Error handling patterns (friendlyError usage in .when() and catch blocks)
- Loading state patterns (AsyncValue.when with loading/error/data)
- Navigation patterns (push vs go, when to use each)
- Form patterns (TextEditingController + dialog pattern)

**`kb/backend-patterns.md`** — Python/FastAPI patterns from the actual codebase.

Sections:
- Route structure (Depends() chain, how auth is composed)
- `run_command()` usage with tuple unpacking
- `store.py` usage (the lock, cache invalidation pattern)
- Path safety (`_safe_resolve()` usage)
- Error response patterns (HTTPException codes used)
- Background tasks pattern (if used)

**`kb/changelog.md`** — replaces `logs.md` as the permanent record.

Create it by extracting the useful facts from `logs.md` (the commit
descriptions and decisions) and reformatting as:

```markdown
# Changelog

## [date] — Session summary
**Features completed:** ...
**Key decisions:** ...
**Known issues introduced:** ...
```

Add one entry for today: "Repository audit — copilot-instructions.md
rewritten, kb/ restructured, stale documentation corrected."

### Files to delete from repo root

After extracting their useful content into `kb/changelog.md`:
- `logs.md` — dev session log, not for the repo
- `MASTER_PROMPT_v5.md` — AI session artifact, not source code
- `MASTER_PROMPT_v6.md` — AI session artifact, not source code
- `TASK_13_TELEGRAM_LARGE_FILES.md` — AI task prompt, not source code

Check git history note: these files being in the repo is fine — deleting
them removes them from the working tree. The history is preserved.

Before deleting each file, extract any decision or architecture fact that
isn't captured elsewhere and write it into `kb/changelog.md` or the
relevant `kb/` file.

---

## Phase 3 — Create `tasks.md` at repo root

The file `tasks.md` is referenced in `copilot-instructions.md` as "read
this first" but does not exist. Create it.

Populate it by reading:
- `MASTER_PROMPT_v5.md` and `MASTER_PROMPT_v6.md` (before deleting them)
- `TASK_13_TELEGRAM_LARGE_FILES.md` (before deleting)
- `kb/critique.md` for known open issues
- Any TODO/FIXME comments found in the codebase during Phase 0

Structure:
```markdown
# AiHomeCloud — Open Tasks
Last updated: [today]

## In progress
[Any work that appears partially implemented]

## Up next (prioritised)
[Concrete tasks ready to implement, in order]

## Backlog
[Known future work, not yet prioritised]

## Deferred
[Explicitly deferred items with reason]

## Done (recent)
[Last 5-10 completed items for context]
```

---

## Phase 4 — Validate

Run these commands and fix any issues they surface before finishing:

```bash
# Backend syntax check — must pass
find backend/app -name "*.py" | xargs python3 -m py_compile && echo "Backend OK"

# Flutter analyze — must show 0 errors (not counting new .md files)
flutter analyze --no-fatal-infos

# Confirm kb/ structure is complete
ls -la kb/
```

After validation, produce a completion report:

```
## Audit complete

### Files modified
- .github/copilot-instructions.md — rewritten
- kb/api-contracts.md — rebuilt (N endpoints documented)
- kb/[other files] — [what changed]

### Files created
- kb/architecture.md
- kb/features.md
- kb/flutter-patterns.md
- kb/backend-patterns.md
- kb/changelog.md
- tasks.md

### Files deleted
- logs.md (content moved to kb/changelog.md)
- MASTER_PROMPT_v5.md (decisions preserved in kb/changelog.md)
- MASTER_PROMPT_v6.md (decisions preserved in kb/changelog.md)
- TASK_13_TELEGRAM_LARGE_FILES.md (tasks moved to tasks.md backlog)

### Inaccuracies corrected in copilot-instructions.md
[Bulleted list of every wrong claim that was fixed, e.g.:]
- Project name: CubieCloud → AiHomeCloud
- Theme class: CubieColors → AppColors
- Widget: CubieCard → AppCard
- Nav tabs: 5 → 3 (Home, Files, More)
- tasks.md: referenced but missing → created
- [etc.]

### Documentation gaps that remain
[Anything you could not verify or complete — be specific]
```

---

## Constraints

- **Never edit source code.** `.dart`, `.py`, `.yaml`, `.sh`, `.json` config
  files are read-only in this session. Only `.md` files and `tasks.md`.
- **Never invent facts.** If you cannot verify a claim from the source files
  you read, write "verify manually" rather than guessing.
- **Accuracy over completeness.** A short accurate doc is better than a long
  one with wrong class names. Every claim must trace back to a file you read.
- **One truth per fact.** If the same fact (e.g., theme class name) appears
  in both `copilot-instructions.md` and `kb/architecture.md`, both must say
  the same thing. Duplicated facts drift. When you write the same fact in two
  places, add a note "(see also kb/architecture.md)" to one of them.
