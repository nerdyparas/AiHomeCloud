# Audit Summary

## Total findings: 29
- CRITICAL: 6
- HIGH: 11
- MEDIUM: 8
- LOW: 4

## Biggest risks

1. **copilot-instructions.md is dangerously stale** (TASK-001 through TASK-008) — every AI coding session reads this file. Wrong class names (`CubieColors`→`AppColors`), wrong project name, reference to a non-existent `tasks.md`, wrong tab count, and outdated screen/widget lists mean AI assistants generate broken code or waste time on phantom files. This is the single highest-impact fix.

2. **Zero test coverage for `/auth/users/names` endpoint** (TASK-013) — this is the login picker endpoint. A format regression (e.g., reverting `has_pin`/`icon_emoji` fields) would break the user picker on all devices with no CI signal.

3. **Four KB docs reference `shared/` paths that no longer exist** (TASK-009 through TASK-012) — AI sessions consulting the KB for storage architecture get wrong directory names, leading to incorrect implementations.

4. **Entertainment sort logic is untested** (TASK-015) — `file_sorter.py` has entertainment rules but `test_file_sorter.py` has zero entertainment tests. A regression would silently break auto-sorting of media files.

5. **14 of 15 Flutter screens have zero test coverage** (TASK-021) — only `DashboardScreen` has a test file. Core user flows (file picker, PIN entry, profile creation) are completely untested.

## What is clean

- **Backend auth coverage** — all HTTP endpoints use `Depends(get_current_user)` or `Depends(require_admin)`, all WebSocket endpoints validate JWT tokens before accepting
- **No security leaks** — `list_user_names` returns only safe fields, no hardcoded IPs, no `print()` calls, no `chmod 777`
- **JWT secret handling** — auto-generated and persisted, never committed
- **No Python 3.12-only syntax** — code is compatible with the device's Python 3.11
- **Backend subprocess safety** — all calls go through `subprocess_runner.run_command()`, no `shell=True`
- **Flutter code quality** — no `CubieCard`/`CubieColors` imports, no `print()`/`debugPrint()`, all API calls use `.timeout()`
- **Dashboard, Files, More screens** — all redesigns correctly implemented
- **QrPairPayload** — still actively used, not dead code
- **CI blocking checks** — `bandit` and `pip-audit` are properly blocking (no `continue-on-error`)

## Recommended fix order

1. **TASK-001 → TASK-008** (copilot-instructions.md) — fix all at once in one commit, takes ~10 minutes, eliminates the root cause of most AI session confusion
2. **TASK-009 → TASK-012** (KB `shared/`→`family/` updates) — fix all four KB files in one commit
3. **TASK-013** (test `/auth/users/names`) — highest-risk untested endpoint
4. **TASK-014** (test `icon_emoji` in store) — quick to write, catches emoji regressions
5. **TASK-015** (test entertainment sorting) — prevents silent media sorting breakage
6. **TASK-016, TASK-017** (CI path triggers) — small YAML edits, big CI coverage improvement
7. **TASK-018, TASK-019** (delete dead screen files) — quick cleanup
8. **TASK-020** (extract duplicate `_uptime()`) — minor refactor
9. **TASK-022** (test migration logic) — important for device updates
10. **TASK-026 → TASK-029** (repo root hygiene) — cleanup session artifacts
11. **TASK-021** (Flutter screen tests) — largest effort, do incrementally
12. **TASK-023, TASK-024, TASK-025** (CI improvements) — lower priority, plan and batch
