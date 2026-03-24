# Feature: Phase 1 — Phone Auto Backup

> Agent task — build in full before committing.
> This is a new feature, not a bug fix. Read the entire prompt before writing any code.

---

## Context & goal

AiHomeCloud is a home NAS for Indian families. This feature lets a user
select folders on their phone and automatically back them up to the NAS
in the background — one-way only (phone → NAS). Think Google Photos backup
but to your own hardware.

This is called "Auto Backup" in the UI. Never "Sync" — that implies
two-way which is out of scope for Phase 1.

The feature lives in the More tab (not a new nav tab).
Trash is being removed from More tab in this same session (see Task 0).

---

## STEP 0 — Read existing code first (do not write code yet)

Read these files:

1. lib/screens/main/more_screen.dart — understand current More tab layout
2. lib/services/api_service.dart + lib/services/api/files_api.dart — 
   understand existing upload endpoint and duplicate detection
3. backend/app/routes/file_routes.py — POST /api/v1/files/upload
4. backend/app/telegram/bot_core.py — read _compute_sha256, _check_duplicate,
   _record_file_hash. You will reuse this exact pattern.
5. backend/app/config.py — understand personal_path, family_path, 
   entertainment_path
6. backend/app/store.py — understand get_value / set_value / atomic_update
7. lib/providers/core_providers.dart — understand authSessionProvider
8. pubspec.yaml — check what packages are already present

After reading, confirm you understand:
- How file upload works end to end (Flutter → backend)
- How duplicate detection works in the Telegram flow
- Where personal/family/entertainment folders live on the NAS
- What packages are already available vs need adding

---

## STEP 1 — Remove trash from More tab

In lib/screens/main/more_screen.dart:
- Remove the Trash list tile / card entirely
- Trash remains accessible from the Files tab — do not touch that
- Run: flutter analyze — 0 errors before continuing

---

## STEP 2 — Backend: new endpoints

Add to backend/app/routes/file_routes.py (or a new backup_routes.py if
file_routes.py exceeds 400 lines after additions):

### 2a. POST /api/v1/backup/check-duplicate
Accepts: { "sha256": "...", "filename": "..." }
Returns: { "exists": true/false }

Reuse the existing file hash store pattern from the Telegram flow.
Hash records live in kv.json under key "file_hashes" — same store
already used by _record_file_hash in bot_core.py. Do not create a
separate store. Reuse exactly.

### 2b. POST /api/v1/backup/record-hash
Accepts: { "sha256": "...", "filename": "...", "destination": "..." }
Records the hash after a successful upload so future syncs skip it.
Same pattern as _record_file_hash.

### 2c. GET /api/v1/backup/status
Returns current backup configuration stored in kv.json:
{
  "enabled": bool,
  "jobs": [
    {
      "id": "...",
      "phoneFolder": "DCIM/Camera",   // display name only, opaque to backend
      "destination": "personal",       // "personal" | "family" | "entertainment"
      "lastSyncAt": "ISO timestamp or null",
      "totalUploaded": 123,
      "totalSkipped": 45
    }
  ]
}

### 2d. POST /api/v1/backup/jobs  
Create or update a backup job config.
Body: { "phoneFolder": "...", "destination": "personal|family|entertainment" }
Persists to kv.json under key "backup_jobs".
Returns the job with generated id.

### 2e. DELETE /api/v1/backup/jobs/{job_id}
Remove a backup job config.

### 2f. POST /api/v1/backup/jobs/{job_id}/report
Called by the Flutter app after each sync run to update stats.
Body: { "uploaded": 12, "skipped": 3, "lastSyncAt": "..." }

All endpoints require get_current_user auth.
Add router to main.py.
Write backend tests for all new endpoints in backend/tests/test_backup.py.

---

## STEP 3 — Folder naming and batching logic (Flutter side)

This logic runs on the device before uploading. It determines what NAS
subfolder each file goes into.

### Destination path rules:

For destination = "personal":
  NAS path: personal/{username}/Photos/  or  personal/{username}/Videos/
  (split by file type — photos go to Photos, videos go to Videos)

For destination = "family":
  NAS path: family/Photos/  or  family/Videos/

For destination = "entertainment":
  NAS path: entertainment/Movies/  (videos only — skip non-video files)

### Batch folder naming:

Within the Photos or Videos subfolder, files are grouped into dated
sub-folders. Logic:

1. Get the capture date for each file:
   - First try: EXIF DateTimeOriginal (use exif package)
   - Second try: Parse filename for date patterns:
       WhatsApp: IMG-20240315-WA0001.jpg → 2024-03-15
       Screenshot: Screenshot_20240315-143022.png → 2024-03-15
   - Fallback: file last modified date

2. Group files by month (year + month, not just month)

3. If a month group has ≤ 500 files: one folder named "Mar 2024"
   If a month group has > 500 files: split into "Mar 2024 (1)",
   "Mar 2024 (2)", etc. — never split mid-day within a month group.

4. Folder name format (strictly this format, no timestamps, no underscores):
   Single month:  "Mar 2024"
   Month range:   "Jan – Mar 2024"  (only if files genuinely span months
                   within one batch — do not force ranges)

5. Before creating a folder, check if it already exists on the NAS.
   If "Mar 2024" exists, append to it (up to 500 file limit).
   If full, create "Mar 2024 (2)".

This logic lives in a pure Dart class: lib/services/backup_batcher.dart
Write unit tests for it in test/services/backup_batcher_test.dart covering:
- WhatsApp filename parsing
- Screenshot filename parsing  
- EXIF fallback
- 500-file split with same-day grouping
- Existing folder append vs new folder creation

---

## STEP 4 — Duplicate detection (Flutter side)

Before uploading any file:
1. Compute SHA-256 of the file
2. Call POST /api/v1/backup/check-duplicate
3. If exists: skip, count as "skipped"
4. If not: upload via existing POST /api/v1/files/upload endpoint, 
   then call POST /api/v1/backup/record-hash

This is identical to the Telegram upload flow. Reuse the pattern.
Do not call check-duplicate in a loop for 1000 files — batch the
SHA-256 computation in groups of 20, check each before uploading,
to avoid hammering the NAS.

---

## STEP 5 — Flutter background service

Use WorkManager (already in most Flutter NAS projects — check pubspec.yaml,
add if missing: flutter_workmanager).

Create: lib/services/backup_worker.dart

The worker:
- Runs every 6 hours (periodic task) and on-demand (one-shot task)
- Only runs when on WiFi (constraint: NetworkType.unmetered)
- Processes one backup job at a time
- For each job:
  1. Enumerate files in the phone folder using file_picker or
     permission_handler + Directory API
  2. Filter: only files added/modified since lastSyncAt
     (use file modified date as a fast pre-filter before SHA-256)
  3. Run duplicate check + upload in batches of 20
  4. Call /api/v1/backup/jobs/{id}/report when done
- Shows a persistent notification during upload with progress
  (X of Y files, current filename)
- On completion: shows a summary notification
  "Backed up 47 photos to AiHomeCloud"
- On error: silent retry on next scheduled run — no error notification
  unless 3 consecutive runs have failed

Permissions required (add to AndroidManifest.xml):
- READ_MEDIA_IMAGES
- READ_MEDIA_VIDEO
- READ_EXTERNAL_STORAGE (for Android < 13)
- FOREGROUND_SERVICE
- RECEIVE_BOOT_COMPLETED (so WorkManager survives reboot)

---

## STEP 6 — UI: Auto Backup screen

Entry point: a list tile in More screen labeled "Auto Backup"
with a subtitle showing status: "3 folders · Last backed up 2h ago"
or "Not set up" if no jobs configured.

Create: lib/screens/main/auto_backup_screen.dart

Screen layout (keep it simple — this is a non-technical user):

### Empty state (no jobs):
  Large icon (cloud upload)
  Title: "Back up your photos automatically"
  Subtitle: "Select folders on your phone and they'll be safely
             copied to your AiHomeCloud — over WiFi, in the background."
  Button: "Set up backup"

### Setup flow (bottom sheet, not a new screen):
  Step 1 — Pick phone folder:
    Label: "Which folder on your phone?"
    Use file_picker to let user select a folder
    Show the folder name (not full path): "Camera", "WhatsApp Images", etc.

  Step 2 — Pick AHC destination:
    Label: "Where should it go on your AiHomeCloud?"
    Three tappable cards (not a dropdown):
      [ My Personal Files ]   subtitle: "Only you can see these"
      [ Family Folder ]       subtitle: "Shared with everyone"  
      [ Entertainment ]       subtitle: "Movies and videos"
    
  Step 3 — Confirm:
    Summary: "Camera photos → Your Personal Files"
    WiFi-only toggle (default on — do not let users turn this off easily,
    default protects them from mobile data charges)
    Button: "Start backup"
    
  Trigger an immediate one-shot WorkManager task on confirm.

### Active state (jobs exist):
  For each job, show a card:
    Folder name (phone side)  →  Destination name
    "Last synced: 2 hours ago · 342 files backed up"
    Swipe to delete or kebab menu with "Remove"
  
  Button at bottom: "Add another folder"

  "Back up now" button — triggers immediate one-shot WorkManager run

### Do not show:
  - /dev paths, NAS paths, technical identifiers
  - Per-file progress in the UI (only in notification)
  - Error details (just "Last sync had issues — will retry automatically")

---

## STEP 7 — Wire everything together

1. Register WorkManager task in lib/main.dart
2. Add Auto Backup tile to More screen (replacing Trash tile removed in Step 1)
3. Add route to lib/navigation/app_router.dart: '/auto-backup'
4. Add backup API methods to lib/services/api/files_api.dart (or a new
   lib/services/api/backup_api.dart part file):
   - checkDuplicate(sha256, filename) → bool
   - recordHash(sha256, filename, destination)
   - getBackupStatus() → BackupStatus
   - createBackupJob(phoneFolder, destination) → BackupJob
   - deleteBackupJob(jobId)
   - reportSyncRun(jobId, uploaded, skipped, lastSyncAt)

5. Add models to lib/models/:
   - BackupJob, BackupStatus to a new lib/models/backup_models.dart

---

## STEP 8 — Validation

Backend:
  cd backend && python -m pytest tests/ -q
  All existing tests pass + new test_backup.py tests pass

Flutter:
  flutter analyze — 0 errors
  flutter test — all pass including new backup_batcher_test.dart

Manual check on device:
  - Select DCIM/Camera folder, destination = Personal
  - Trigger "Back up now"
  - Verify files appear in personal/{username}/Photos/Mar 2024/
  - Run again — verify no duplicates uploaded (all skipped)
  - Verify notification appears during upload and summary on completion

---

## Docs to update

- kb/architecture.md — add AutoBackupScreen to screen inventory,
  BackupWorker to services, backup_models.dart to models
- kb/api-contracts.md — add all 6 new backup endpoints
- kb/features.md — mark "Phone Auto Backup (Phase 1)" as implemented
- kb/changelog.md — "2026-03-XX: Phase 1 Auto Backup — background
  phone-to-NAS backup with duplicate detection and dated folder grouping"
- README.md — add Auto Backup to feature list
